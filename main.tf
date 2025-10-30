provider "aws" {
  region = "us-west-2"
}

# ---------------------------
# Management VPC
# ---------------------------
module "management_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "4.0.2"

  name = "management-vpc"
  cidr = "10.10.0.0/16"

  azs             = ["us-west-2a", "us-west-2b"]
  public_subnets  = ["10.10.1.0/24", "10.10.2.0/24"]
  private_subnets = ["10.10.11.0/24", "10.10.12.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = {
    Project = "AcmePOC"
    Role    = "Management"
  }
}

# ---------------------------
# Application VPC
# ---------------------------
module "app_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "4.0.2"

  name = "app-vpc"
  cidr = "10.20.0.0/16"

  azs             = ["us-west-2a", "us-west-2b"]
  public_subnets  = ["10.20.1.0/24", "10.20.2.0/24"]
  private_subnets = ["10.20.11.0/24", "10.20.12.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = {
    Project = "AcmePOC"
    Role    = "Application"
  }
}

# ---------------------------
# Inspection VPC
# ---------------------------
module "inspection_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "4.0.2"

  name = "inspection-vpc"
  cidr = "10.30.0.0/16"

  azs             = ["us-west-2a", "us-west-2b"]
  public_subnets  = ["10.30.1.0/24", "10.30.2.0/24"]
  private_subnets = ["10.30.11.0/24", "10.30.12.0/24"] # Place GWLB and Palo interfaces here

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = {
    Project = "AcmePOC"
    Role    = "Inspection"
  }
}

# ---------------------------
# Security Groups
# ---------------------------

# Bastion Host SG
resource "aws_security_group" "bastion_sg" {
  name        = "bastion-sg"
  description = "Allow SSH from your IP only"
  vpc_id      = module.management_vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["YOUR_IP/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Project = "AcmePOC" }
}

# NGINX Server SG
resource "aws_security_group" "nginx_sg" {
  name        = "nginx-sg"
  description = "Allow HTTP/HTTPS inbound"
  vpc_id      = module.app_vpc.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Project = "AcmePOC" }
}

# ---------------------------
# EC2 Instances (Bastion & NGINX)
# ---------------------------
resource "aws_instance" "bastion" {
  ami           = "ami-0abcdef1234567890" # replace with latest AWS Linux 2
  instance_type = "t3.micro"
  subnet_id     = module.management_vpc.public_subnets[0]
  security_groups = [aws_security_group.bastion_sg.name]
  key_name = "YOUR_KEY_NAME"
  tags = { Name = "Bastion", Project = "AcmePOC" }
}

resource "aws_instance" "nginx" {
  ami           = "ami-0abcdef1234567890" # replace with latest Amazon Linux or Ubuntu
  instance_type = "t3.micro"
  subnet_id     = module.app_vpc.public_subnets[0]
  security_groups = [aws_security_group.nginx_sg.name]
  key_name = "YOUR_KEY_NAME"
  tags = { Name = "NGINX", Project = "AcmePOC" }
}

# ---------------------------
# Route Tables for Inspection via Palo
# ---------------------------

# Private route table for App VPC to route traffic via Inspection VPC
resource "aws_route_table" "app_private_routes" {
  vpc_id = module.app_vpc.vpc_id

  route {
    cidr_block = "0.0.0.0/0"
    # point to Palo NVA once manually deployed
    gateway_id = "" # fill after deploying Palo
  }

  tags = { Project = "AcmePOC", Role = "App Private" }
}

# Private route table for Management VPC to route traffic via Inspection VPC
resource "aws_route_table" "mgmt_private_routes" {
  vpc_id = module.management_vpc.vpc_id

  route {
    cidr_block = "0.0.0.0/0"
    # point to Palo NVA once manually deployed
    gateway_id = "" # fill after deploying Palo
  }

  tags = { Project = "AcmePOC", Role = "Mgmt Private" }
}

