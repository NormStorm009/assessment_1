# Solution — Architecture & Design

## Overview

The stack is split into two layers: Terraform handles infrastructure provisioning and Ansible (via Semaphore) handles application deployment. The separation keeps infrastructure changes and application changes on separate paths.

```
Internet
    │
    ▼
┌──────────────────────────────────────┐
│  ALB (public)                        │
│  :80  → app     :8080 → Semaphore   │
└──────────────┬───────────────────────┘
               │ (private subnets)
     ┌─────────┴──────────┐
     ▼                    ▼
┌──────────┐     ┌─────────────────┐
│ App EC2  │◄SSH─│ Ansible Node    │
│ Docker   │     │ Semaphore :3000 │
└──────────┘     └─────────────────┘
     │                    │
     └──────────┬──────────┘
                ▼
          NAT Gateway → IGW
```

## Key decisions

**Single ALB with two listeners** — port 80 for the app and port 8080 for Semaphore. Avoids a second load balancer or separate DNS while keeping traffic paths clean.

**Semaphore for Ansible** — rather than SSHing into the control node and running `ansible-playbook` manually, Semaphore provides a UI with run history and a pre-seeded project (repo, inventory, SSH key, task template). Everything is wired up at boot via `ansible_init.sh` so it's ready to use immediately after `terraform apply`.

**SSH key management via SSM Parameter Store** — Terraform generates the key pair and stores the private key as a SecureString. The Ansible node fetches it at boot. The private key never touches a developer's machine or the repository.

**No bastion host** — all shell access to private instances goes through SSM Session Manager. The app server only accepts SSH from the Ansible security group; the Ansible node only accepts traffic on port 3000 from the ALB security group.

**IMDSv2 enforced** on both instances (`http_tokens = "required"`).

**S3 for ALB access logs** — bucket name is globally unique using account ID as a suffix. 30-day lifecycle in dev; Glacier transition at 1 year in prod. Public access fully blocked; only the regional ELB service account can write.

## Trade-offs

**Local Terraform state** — state lives in `terraform.tfstate` on the developer's machine. Fine for this demo; a shared team setup would use an S3 backend with a DynamoDB lock table to prevent concurrent applies.

**Single NAT Gateway** — placed in one AZ to keep costs down. If that AZ goes down, private instances in the other AZ lose outbound internet access. In production you'd run one NAT per AZ.

**No HTTPS** — the ALB only listens on HTTP. Adding TLS requires a domain name for ACM certificate validation, which is out of scope here.

**Semaphore default password** — `changeme` is hardcoded in `ansible_init.sh`. In production this would be generated at runtime and stored in Secrets Manager. The Semaphore dashboard should also be restricted to a known CIDR rather than being open on the ALB.

**No `terraform plan` in CI** — the PR workflow runs format and validation checks only. Running a plan against live AWS state requires a remote backend and IAM credentials scoped carefully. For this demo the infrastructure is managed locally and the CI pipeline focuses on keeping the code clean and triggering Ansible on merge.

**Single EC2 instance (no ASG)** — the launch template is already structured for an ASG but a single instance was sufficient for the assessment. Replacing `aws_instance` with an ASG is a near-mechanical change.

**`force_destroy = true` on the S3 bucket** — makes `terraform destroy` work cleanly in dev. Should be `false` in production.
