# Base variables

service     = "rewards"
env         = "dev"
aws_region  = "eu-west-1"
owner       = "Product Owner"
cost_centre = "Product"


# Networking

vpc_cidr_block = "10.0.0.0/16"
public_subnet_cidr_blocks = ["10.0.1.0/24","10.0.2.0/24"]
private_subnet_cidr_blocks = ["10.0.3.0/24","10.0.4.0/24"]
azs = ["eu-west-1a","eu-west-1b"]

# EC2
ec2_instance_type = "t3.micro"

# ALB + Container

app_port = 5001
docker_image = "normstorm009/sample:latest"

# Ansible
ansible_instance_type = "t3.medium"
ansible_port          = 3000
github_repo_url = "https://github.com/NormStorm009/assessment_1.git"
github_branch   = "add_webserver"