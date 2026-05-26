# Base Variables

variable "aws_region" {
  default = "eu-west-1"
  description = "The Aws region you wish to deploy in"
}

variable "service" {
  description = "This is the service name"
}

variable "env" {
  description = "This would be the environment you wish to depoloy too"

  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "environment must be either dev or prod"
  }
}

variable "cost_centre" {
  description = "The responsible Cost centre for the Solution/Service"
}

variable "owner" {
  description = "This is the Owner and point of contact for the Solution/Service"
}


# Networking Variables

variable "vpc_cidr_block" {
    description = "This would be the full CIDR range foer the VPC"
    type = string
}

variable "public_subnet_cidr_blocks" {
    description = "This would be the list of CIDR range for the Public Subnet"
    type = list
}

variable "private_subnet_cidr_blocks" {
    description = "This would be the list of CIDR range for the Private Subnet"
    type = list
}

variable "azs" {
    description = "This would be the list of Availability zones"
    type = list
}


# ALB variables:

variable "app_port" {
  description = "This wouild be the container port in this instance"
}

variable "health_check_path" {
  description = "Path the ALB health check hits on the app container"
  type        = string
  default     = "/health"
}