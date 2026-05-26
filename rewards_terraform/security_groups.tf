
# ALB Security group
resource "aws_security_group" "alb_sg" {
  name        = "${local.name}-sg-alb"
  description = "Allow HTTP and HTTPS inbound from internet to ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description      = "HTTP from internet"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "HTTPS from internet"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "Ansible dashboard from internet"
    from_port        = 8080
    to_port          = 8080
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    description      = "All outbound via Internet Gateway"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name        = "${local.name}-sg-alb"
  }
}


# App Server Security Group
resource "aws_security_group" "app" {
  name        = "${local.name}-sg-app"
  description = "Allow inbound from ALB only on app port"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "App port from ALB only"
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    description     = "SSH from Ansible control node"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.ansible.id]
  }

  egress {
    description      = "All outbound - Docker pulls, SSM, AWS APIs"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name        = "${local.name}-sg-app"
  }
}


# Ansible Control Node Security Group
resource "aws_security_group" "ansible" {
  name        = "${local.name}-sg-ansible"
  description = "Allow inbound from ALB only on ansible dashboard port"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Semaphore dashboard from ALB only"
    from_port       = var.ansible_port
    to_port         = var.ansible_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    description      = "All outbound - Docker pulls, SSM, AWS APIs"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name        = "${local.name}-sg-ansible"
  }
}