# Assessment 1 — Rewards Service Infrastructure

Terraform + Ansible stack provisioning the Rewards service on AWS (`eu-west-1`). The stack includes a public ALB, an app EC2 instance running a Docker container in a private subnet, and an Ansible control node (Semaphore) also in a private subnet.

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) ≥ 1.5
- [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- AWS credentials configured (`aws configure` or environment variables)

## Running locally

```bash
git clone https://github.com/NormStorm009/assessment_1.git
cd assessment_1/rewards_terraform

terraform init
terraform apply -var-file=envs/dev.tfvars
```

Both instances bootstrap via `user_data`. Allow 5–8 minutes after `apply` completes for Semaphore to finish seeding.

```bash
# Get the ALB address
terraform output alb_dns_name

# Check the app
curl http://$(terraform output -raw alb_dns_name)/health

# Open the Semaphore dashboard
open http://$(terraform output -raw alb_dns_name):8080
```

Semaphore default credentials: `admin` / `changeme` — change on first login.

## Running the Ansible playbook

From the Semaphore dashboard (`http://<alb-dns>:8080`):

1. Log in
2. Go to **Task Templates → Deploy App → Run**

Alternatively via SSM (no bastion needed):

```bash
ANSIBLE_ID=$(terraform output -raw ansible_instance_id)
APP_IP=$(terraform output -raw app_server_private_ip)

aws ssm send-command \
  --region eu-west-1 \
  --instance-id "$ANSIBLE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters "$(jq -n \
    --arg ip "$APP_IP" \
    '{commands:[
      "cd /tmp && rm -rf assessment_1 && git clone --depth 1 https://github.com/NormStorm009/assessment_1.git",
      ("ANSIBLE_COLLECTIONS_PATHS=/usr/share/ansible/collections ansible-playbook /tmp/assessment_1/rewards_terraform/playbooks/deploy_app.yml -i \""+$ip+",\" --private-key /opt/ansible/app_server.pem -u ec2-user -e \"app_port=5001 docker_image=normstorm009/sample:latest\"")
    ]}')"
```

## Tear down

```bash
terraform destroy -var-file=envs/dev.tfvars
```

## Repository layout

```
rewards_terraform/
├── main.tf               # Provider config
├── variables.tf          # Input variables
├── locals.tf             # Naming and default tags
├── outputs.tf            # ALB DNS, instance IDs
├── networking.tf         # VPC, subnets, IGW, NAT, routes
├── security_groups.tf    # ALB, app, Ansible SGs
├── alb.tf                # ALB, listeners, target groups
├── web_server.tf         # App EC2 + target group attachment
├── ansible.tf            # Ansible control node EC2
├── iam.tf                # IAM role and SSM policies
├── keys.tf               # TLS key pair + SSM parameter
├── s3.tf                 # ALB access-log bucket
├── init.sh               # App server user-data
├── ansible_init.sh       # Ansible node user-data (installs + seeds Semaphore)
└── envs/dev.tfvars       # Dev variable values

.github/workflows/
├── pr.yml                # PR checks: secret validation, fmt, validate
└── deploy.yml            # Merge to main: trigger Ansible via SSM
```
