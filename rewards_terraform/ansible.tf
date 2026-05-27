# Ansible Control Node - Launch Template
resource "aws_launch_template" "ansible" {
  name_prefix   = "${local.name}-ansible-lt-"
  image_id      = data.aws_ami.al2023.id
  instance_type = var.ansible_instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.ec2.arn
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.ansible.id]
    subnet_id                   = aws_subnet.private_subnet_1.id
  }

  user_data = base64encode(templatefile("${path.module}/ansible_init.sh", {
    ansible_port    = var.ansible_port
    app_server_ip   = aws_instance.app.private_ip
    app_port        = var.app_port
    docker_image    = var.docker_image
    github_repo_url = var.github_repo_url
    github_branch   = var.github_branch
    ssm_key_param = aws_ssm_parameter.ansible_private_key.name
    aws_region    = var.aws_region
  }))

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  monitoring { enabled = true }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${local.name}-ansible"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name = "${local.name}-ansible-vol"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# EC2 Instance
resource "aws_instance" "ansible" {
  launch_template {
    id      = aws_launch_template.ansible.id
    version = "$Latest"
  }

  tags = {
    Name = "${local.name}-ansible"
  }
}

# Register with ALB Target Group
resource "aws_lb_target_group_attachment" "ansible" {
  target_group_arn = aws_lb_target_group.ansible.arn
  target_id        = aws_instance.ansible.id
  port             = var.ansible_port
}
