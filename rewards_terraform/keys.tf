# Generate RSA key pair so the Ansible node can SSH into app servers
resource "tls_private_key" "ansible" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Register public key with EC2
resource "aws_key_pair" "app" {
  key_name   = "${local.name}-app-key"
  public_key = tls_private_key.ansible.public_key_openssh

  tags = {
    Name        = "${local.name}-app-key"
    Environment = var.env
  }
}

# Store private key in SSM Parameter Store as a SecureString
# The Ansible node fetches this at boot to seed Semaphore's key store
resource "aws_ssm_parameter" "ansible_private_key" {
  name  = "/${local.name}/ansible/private-key"
  type  = "SecureString"
  value = tls_private_key.ansible.private_key_pem

  tags = {
    Name        = "${local.name}-ansible-private-key"
    Environment = var.env
  }
}
