#!/bin/bash

set -euo pipefail

exec > >(tee /var/log/user-data.log | logger -t user-data) 2>&1

# ── System setup ──────────────────────────────────────────────────────────────
dnf update -y
dnf install -y docker jq
systemctl enable --now docker
usermod -aG docker ec2-user

# ── Fetch SSH private key from SSM ────────────────────────────────────────────
mkdir -p /opt/ansible

aws ssm get-parameter \
  --name "${ssm_key_param}" \
  --with-decryption \
  --region "${aws_region}" \
  --query "Parameter.Value" \
  --output text > /opt/ansible/app_server.pem
chmod 600 /opt/ansible/app_server.pem

# ── Start Semaphore ───────────────────────────────────────────────────────────
# Default credentials: admin / changeme  <-- change on first login
docker pull semaphoreui/semaphore:latest
docker run -d \
  --name semaphore \
  --restart unless-stopped \
  -p ${ansible_port}:3000 \
  -e SEMAPHORE_DB_DIALECT=bolt \
  -e SEMAPHORE_ADMIN=admin \
  -e SEMAPHORE_ADMIN_PASSWORD=changeme \
  -e SEMAPHORE_ADMIN_NAME=Admin \
  -e SEMAPHORE_ADMIN_EMAIL=admin@local \
  -v semaphore_data:/home/semaphore \
  semaphoreui/semaphore:latest

# ── Wait for Semaphore to be healthy ─────────────────────────────────────────
echo "Waiting for Semaphore..."
until curl -sf "http://localhost:${ansible_port}/api/ping" > /dev/null 2>&1; do
  sleep 5
done
echo "Semaphore is ready"

# ── Seed Semaphore via API ────────────────────────────────────────────────────
SEM_URL="http://localhost:${ansible_port}"
COOKIE=/tmp/sem_cookies.txt

# Authenticate
curl -sf -X POST "$SEM_URL/api/auth/login" \
  -H "Content-Type: application/json" \
  -c "$COOKIE" \
  -d '{"auth":"admin","password":"changeme"}' > /dev/null

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
    --arg inv "[app_servers]\n${app_server_ip} ansible_user=ec2-user" \
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
curl -sf -X POST "$SEM_URL/api/project/$PROJECT_ID/templates" \
  -H "Content-Type: application/json" \
  -b "$COOKIE" \
  -d "$(jq -n \
    --argjson pid "$PROJECT_ID" \
    --argjson iid "$INV_ID" \
    --argjson rid "$REPO_ID" \
    --argjson eid "$ENV_ID" \
    '{project_id:$pid,inventory_id:$iid,repository_id:$rid,environment_id:$eid,
      name:"Deploy App",
      playbook:"rewards_terraform/playbooks/deploy_app.yml",
      type:"job"}')" \
  > /dev/null

echo "Semaphore pre-configuration complete — log in and hit Run"
