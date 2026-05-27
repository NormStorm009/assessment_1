#!/bin/bash

set -euo pipefail

LOG=/var/log/user-data.log
exec > >(tee -a "$LOG") 2>&1

# Echo to /dev/console so progress is visible in the EC2 system log without SSM
log() { echo "[user-data] $*" | tee /dev/console; }
trap 'log "FAILED at line $LINENO: $BASH_COMMAND"' ERR

log "started"

# ── System setup ──────────────────────────────────────────────────────────────
# Wait for any in-progress dnf operations from first-boot services
while pgrep -x dnf > /dev/null 2>&1; do
  log "waiting for dnf lock..."
  sleep 5
done

log "dnf update"
dnf update -y

# ansible-core from dnf: provides ansible-playbook, much lighter than pip install ansible
log "dnf install"
dnf install -y ansible-core jq git openssl

log "packages installed"

# Install community.docker collection system-wide so Semaphore's semaphore user can find it
ansible-galaxy collection install community.docker \
  -p /usr/share/ansible/collections --timeout 120
log "ansible collections installed"

# ── Fetch SSH private key from SSM ────────────────────────────────────────────
mkdir -p /opt/ansible

aws ssm get-parameter \
  --name "${ssm_key_param}" \
  --with-decryption \
  --region "${aws_region}" \
  --query "Parameter.Value" \
  --output text > /opt/ansible/app_server.pem
chmod 600 /opt/ansible/app_server.pem

log "ssh key fetched"

# ── Install Semaphore binary ──────────────────────────────────────────────────
# Resolve latest version from the redirect URL — no API call, no rate limit risk
SEMAPHORE_VERSION=$(curl -fsSL \
  -o /dev/null \
  -w "%%{url_effective}" \
  "https://github.com/semaphoreui/semaphore/releases/latest" \
  | sed 's|.*/tag/v||')
log "semaphore version: $SEMAPHORE_VERSION"

curl -fsSL "https://github.com/semaphoreui/semaphore/releases/download/v$SEMAPHORE_VERSION/semaphore_$${SEMAPHORE_VERSION}_linux_amd64.tar.gz" \
  | tar xz -C /usr/local/bin/ semaphore
chmod +x /usr/local/bin/semaphore

log "semaphore binary installed"

# ── Configure Semaphore ───────────────────────────────────────────────────────
useradd -r -s /sbin/nologin semaphore 2>/dev/null || true

mkdir -p /etc/semaphore /var/lib/semaphore /tmp/semaphore

# Generate random cookie secrets
COOKIE_HASH=$(openssl rand -base64 32)
COOKIE_ENC=$(openssl rand -base64 32)

jq -n \
  --arg port ":${ansible_port}" \
  --arg ch "$COOKIE_HASH" \
  --arg ce "$COOKIE_ENC" \
  '{
    bolt:              {host: "/var/lib/semaphore/database.boltdb"},
    tmp_path:          "/tmp/semaphore",
    port:              $port,
    cookie_hash:       $ch,
    cookie_encryption: $ce
  }' > /etc/semaphore/config.json

# Give semaphore ownership of all its dirs before starting the service
chown -R semaphore:semaphore /etc/semaphore /var/lib/semaphore /tmp/semaphore /opt/ansible

log "semaphore configured"

# ── Systemd service ───────────────────────────────────────────────────────────
cat > /etc/systemd/system/semaphore.service << 'EOF'
[Unit]
Description=Semaphore Ansible Dashboard
After=network.target

[Service]
Type=simple
User=semaphore
WorkingDirectory=/var/lib/semaphore
ExecStart=/usr/local/bin/semaphore server --config /etc/semaphore/config.json
Restart=on-failure
Environment=HOME=/var/lib/semaphore
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=ANSIBLE_COLLECTIONS_PATHS=/usr/share/ansible/collections

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl start semaphore

# ── Wait for Semaphore to finish DB migrations ────────────────────────────────
# Must be healthy before we try to add the admin user — migrations must run
# on a clean DB first, otherwise the user record ends up in the wrong schema.
log "waiting for semaphore migrations..."
until curl -sf "http://localhost:${ansible_port}/api/ping" > /dev/null 2>&1; do
  sleep 5
done
sleep 10  # Extra buffer for BoltDB migration to fully commit
log "semaphore migrations complete"

# ── Add admin user to the fully-migrated DB ───────────────────────────────────
# Stop the service so the BoltDB file lock is released before we write to it.
systemctl stop semaphore
sleep 3

/usr/local/bin/semaphore user add \
  --admin \
  --login    admin \
  --name     Admin \
  --email    admin@local \
  --password changeme \
  --config   /etc/semaphore/config.json

log "admin user added to migrated DB"

# ── Restart Semaphore and wait for it to be ready ────────────────────────────
systemctl enable semaphore
systemctl start semaphore

log "waiting for semaphore to restart..."
until curl -sf "http://localhost:${ansible_port}/api/ping" > /dev/null 2>&1; do
  sleep 5
done
sleep 5
echo "Semaphore is ready"

# ── Seed Semaphore via API ────────────────────────────────────────────────────
SEM_URL="http://localhost:${ansible_port}"
COOKIE=/tmp/sem_cookies.txt

# Authenticate — check HTTP status code (login returns 204 No Content on success)
AUTH_CODE=$(curl -s -o /tmp/auth_body.txt -w "%%{http_code}" \
  -X POST "$SEM_URL/api/auth/login" \
  -H "Content-Type: application/json" \
  -c "$COOKIE" \
  -d '{"auth":"admin","password":"changeme"}')
log "auth http_code=$AUTH_CODE body=$(cat /tmp/auth_body.txt)"
log "cookie jar: $(cat $COOKIE 2>/dev/null | grep -v '^#' | grep -v '^$' || echo 'empty')"

# v2.18+ renamed the field to "login" — retry if not a 2xx
if [[ "$AUTH_CODE" != 2* ]]; then
  AUTH_CODE=$(curl -s -o /tmp/auth_body.txt -w "%%{http_code}" \
    -X POST "$SEM_URL/api/auth/login" \
    -H "Content-Type: application/json" \
    -c "$COOKIE" \
    -d '{"login":"admin","password":"changeme"}')
  log "auth retry http_code=$AUTH_CODE body=$(cat /tmp/auth_body.txt)"
  log "cookie jar after retry: $(cat $COOKIE 2>/dev/null | grep -v '^#' | grep -v '^$' || echo 'empty')"
fi

[[ "$AUTH_CODE" == 2* ]] || { log "FATAL: could not authenticate to Semaphore (last code $AUTH_CODE)"; exit 1; }

# Create project
PROJECT_ID=$(curl -sf -X POST "$SEM_URL/api/projects" \
  -H "Content-Type: application/json" \
  -b "$COOKIE" \
  -d '{"name":"rewards","alert":false,"max_parallel_tasks":0}' \
  | jq -r '.id')
echo "Project: $PROJECT_ID"

# SSH key — used by Ansible to connect to the app server
KEY_ID=$(curl -sf -X POST "$SEM_URL/api/project/$PROJECT_ID/keys" \
  -H "Content-Type: application/json" \
  -b "$COOKIE" \
  -d "$(jq -n \
    --argjson pid "$PROJECT_ID" \
    --arg pk "$(cat /opt/ansible/app_server.pem)" \
    '{name:"app-server-ssh",type:"ssh",project_id:$pid,ssh:{login:"ec2-user",private_key:$pk}}')" \
  | jq -r '.id')
echo "SSH Key: $KEY_ID"

# None key — public repo, no credentials needed
NONE_KEY_ID=$(curl -sf -X POST "$SEM_URL/api/project/$PROJECT_ID/keys" \
  -H "Content-Type: application/json" \
  -b "$COOKIE" \
  -d "$(jq -n --argjson pid "$PROJECT_ID" '{name:"github-none",type:"none",project_id:$pid}')" \
  | jq -r '.id')
echo "None Key: $NONE_KEY_ID"

# Repository — points at the repo containing the playbooks
REPO_ID=$(curl -sf -X POST "$SEM_URL/api/project/$PROJECT_ID/repositories" \
  -H "Content-Type: application/json" \
  -b "$COOKIE" \
  -d "$(jq -n \
    --argjson pid "$PROJECT_ID" \
    --argjson kid "$NONE_KEY_ID" \
    --arg url "${github_repo_url}" \
    --arg branch "${github_branch}" \
    '{name:"rewards-repo",project_id:$pid,git_url:$url,git_branch:$branch,ssh_key_id:$kid}')" \
  | jq -r '.id')
echo "Repo: $REPO_ID"

# Inventory — app server private IP pre-wired
INV_ID=$(curl -sf -X POST "$SEM_URL/api/project/$PROJECT_ID/inventory" \
  -H "Content-Type: application/json" \
  -b "$COOKIE" \
  -d "$(jq -n \
    --argjson pid "$PROJECT_ID" \
    --argjson kid "$KEY_ID" \
    --arg inv $'[app_servers]\n${app_server_ip} ansible_user=ec2-user' \
    '{name:"app-servers",project_id:$pid,inventory:$inv,ssh_key_id:$kid,type:"static"}')" \
  | jq -r '.id')
echo "Inventory: $INV_ID"

# Environment — app_port and docker_image pre-populated as extra vars
ENV_JSON=$(jq -cn --arg p "${app_port}" --arg i "${docker_image}" '{"app_port":$p,"docker_image":$i}')
ENV_ID=$(curl -sf -X POST "$SEM_URL/api/project/$PROJECT_ID/environment" \
  -H "Content-Type: application/json" \
  -b "$COOKIE" \
  -d "$(jq -n \
    --argjson pid "$PROJECT_ID" \
    --arg json "$ENV_JSON" \
    '{name:"dev-vars",project_id:$pid,json:$json}')" \
  | jq -r '.id')
echo "Environment: $ENV_ID"

# Task Template — everything wired up, ready to run from the dashboard
# type: omitted = regular task (valid values: "", "build", "deploy" — NOT "job")
# app: "ansible" tells Semaphore to use ansible-playbook for execution
TMPL_RESP=$(curl -s -o /tmp/tmpl_body.txt -w "%%{http_code}" \
  -X POST "$SEM_URL/api/project/$PROJECT_ID/templates" \
  -H "Content-Type: application/json" \
  -b "$COOKIE" \
  -d "$(jq -n \
    --argjson pid "$PROJECT_ID" \
    --argjson iid "$INV_ID" \
    --argjson rid "$REPO_ID" \
    --argjson eid "$ENV_ID" \
    '{project_id:$pid,inventory_id:$iid,repository_id:$rid,environment_id:$eid,
      name:"Deploy App",
      app:"ansible",
      playbook:"rewards_terraform/playbooks/deploy_app.yml"}')")
log "template create http_code=$TMPL_RESP body=$(cat /tmp/tmpl_body.txt)"

echo "Semaphore pre-configuration complete — log in and hit Run"
