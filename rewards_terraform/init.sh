#!/bin/bash

set -euo pipefail

exec > >(tee /var/log/user-data.log | logger -t user-data) 2>&1

dnf update -y
dnf install -y docker
systemctl enable --now docker
usermod -aG docker ec2-user
docker pull ${docker_image}
docker run -d \
  --name rewards \
  --restart unless-stopped \
  -p ${app_port}:${app_port} \
  -e PORT=${app_port} \
  ${docker_image}