data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}


# Launch Template
resource "aws_launch_template" "app" {
  name_prefix   = "${local.name}-lt-"
  image_id      = data.aws_ami.al2023.id   # from data.tf
  instance_type = var.ec2_instance_type
  key_name      = aws_key_pair.app.key_name

  iam_instance_profile {
    arn = aws_iam_instance_profile.ec2.arn
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.app.id]
    subnet_id                   = aws_subnet.private_subnet_1.id
  }

  user_data = base64encode(templatefile("${path.module}/init.sh", {
    app_port = var.app_port
    docker_image = var.docker_image
  }))

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  monitoring { enabled = true }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${local.name}-app"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name        = "${local.name}-app-vol"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# EC2 Instance
resource "aws_instance" "app" {
  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  tags = {
    Name        = "${local.name}-app"
  }
}

# Register with ALB Target Group
resource "aws_lb_target_group_attachment" "app" {
  target_group_arn = aws_lb_target_group.app.arn
  target_id        = aws_instance.app.id
  port             = var.app_port
}