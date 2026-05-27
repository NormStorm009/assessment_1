output "alb_dns_name" {
  description = "Public DNS name of the Application Load Balancer"
  value       = aws_lb.public_alb.dns_name
}

output "ansible_instance_id" {
  description = "EC2 instance ID of the Ansible control node (Semaphore)"
  value       = aws_instance.ansible.id
}

output "app_instance_id" {
  description = "EC2 instance ID of the app server"
  value       = aws_instance.app.id
}

output "app_server_private_ip" {
  description = "Private IP address of the app server (used by Ansible inventory)"
  value       = aws_instance.app.private_ip
}

output "app_port" {
  description = "Port the application container listens on"
  value       = var.app_port
}

output "docker_image" {
  description = "Docker image running on the app server"
  value       = var.docker_image
}
