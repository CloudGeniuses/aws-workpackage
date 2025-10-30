############################
# TERRAFORM & PROVIDER
############################

terraform {
  required_version = ">= 1.5.0"

  cloud {
    organization = "my-org"

    workspaces {
      name = "palo-nva-project"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

############################
# VARIABLES
############################

variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "us-west-2"
}

variable "management_vpc_cidr" {
  description = "CIDR block for Management VPC"
  type        = string
  default     = "10.10.0.0/16"
}

variable "app_vpc_cidr" {
  description = "CIDR block for App VPC"
  type        = string
  default     = "10.20.0.0/16"
}

variable "inspection_vpc_cidr" {
  description = "CIDR block for Inspection VPC"
  type        = string
  default     = "10.30.0.0/16"
}

variable "azs" {
  description = "List of Availability Zones"
  type        = list(string)
  default     = [
    "a",
    "b"
  ]
}

variable "office_ip" {
  description = "Your office public IP for SSH/SSM"
  type        = string
  default     = "YOUR_OFFICE_IP/32"
}

variable "key_pair" {
  description = "SSH key pair name for EC2 instances"
  type        = string
  default     = "YOUR_KEY_PAIR"
}

############################
# VPCs
############################

resource "aws_vpc" "management" {
  cidr_block           = var.management_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "Management-VPC" }
}

resource "aws_vpc" "app" {
  cidr_block           = var.app_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "App-VPC" }
}

resource "aws_vpc" "inspection" {
  cidr_block           = var.inspection_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "Inspection-VPC" }
}

############################
# PUBLIC SUBNETS
############################

resource "aws_subnet" "management_public" {
  vpc_id                  = aws_vpc.management.id
  cidr_block              = "10.10.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}${var.azs[0]}"
  tags = { Name = "management-public" }
}

resource "aws_subnet" "app_public" {
  vpc_id                  = aws_vpc.app.id
  cidr_block              = "10.20.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}${var.azs[0]}"
  tags = { Name = "app-public" }
}

resource "aws_subnet" "inspection_public" {
  vpc_id                  = aws_vpc.inspection.id
  cidr_block              = "10.30.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}${var.azs[0]}"
  tags = { Name = "inspection-public" }
}

############################
# PRIVATE SUBNETS
############################

resource "aws_subnet" "management_private" {
  vpc_id            = aws_vpc.management.id
  cidr_block        = "10.10.2.0/24"
  availability_zone = "${var.aws_region}${var.azs[1]}"
  tags = { Name = "management-private" }
}

resource "aws_subnet" "app_private" {
  vpc_id            = aws_vpc.app.id
  cidr_block        = "10.20.2.0/24"
  availability_zone = "${var.aws_region}${var.azs[1]}"
  tags = { Name = "app-private" }
}

resource "aws_subnet" "inspection_private" {
  vpc_id            = aws_vpc.inspection.id
  cidr_block        = "10.30.2.0/24"
  availability_zone = "${var.aws_region}${var.azs[1]}"
  tags = { Name = "inspection-private" }
}

############################
# INTERNET GATEWAYS
############################

resource "aws_internet_gateway" "management" {
  vpc_id = aws_vpc.management.id
  tags = { Name = "management-igw" }
}

resource "aws_internet_gateway" "app" {
  vpc_id = aws_vpc.app.id
  tags = { Name = "app-igw" }
}

resource "aws_internet_gateway" "inspection" {
  vpc_id = aws_vpc.inspection.id
  tags = { Name = "inspection-igw" }
}

############################
# NAT GATEWAYS
############################

resource "aws_eip" "management_nat" { vpc = true }
resource "aws_nat_gateway" "management" {
  allocation_id = aws_eip.management_nat.id
  subnet_id     = aws_subnet.management_public.id
  tags = { Name = "management-nat" }
}

resource "aws_eip" "app_nat" { vpc = true }
resource "aws_nat_gateway" "app" {
  allocation_id = aws_eip.app_nat.id
  subnet_id     = aws_subnet.app_public.id
  tags = { Name = "app-nat" }
}

resource "aws_eip" "inspection_nat" { vpc = true }
resource "aws_nat_gateway" "inspection" {
  allocation_id = aws_eip.inspection_nat.id
  subnet_id     = aws_subnet.inspection_public.id
  tags = { Name = "inspection-nat" }
}

############################
# PRIVATE ROUTE TABLES
############################

resource "aws_route_table" "management_private" { vpc_id = aws_vpc.management.id }
resource "aws_route_table" "app_private"        { vpc_id = aws_vpc.app.id }
resource "aws_route_table" "inspection_private" { vpc_id = aws_vpc.inspection.id }

resource "aws_route_table_association" "management_private_assoc" {
  subnet_id      = aws_subnet.management_private.id
  route_table_id = aws_route_table.management_private.id
}

resource "aws_route_table_association" "app_private_assoc" {
  subnet_id      = aws_subnet.app_private.id
  route_table_id = aws_route_table.app_private.id
}

resource "aws_route_table_association" "inspection_private_assoc" {
  subnet_id      = aws_subnet.inspection_private.id
  route_table_id = aws_route_table.inspection_private.id
}

resource "aws_route" "management_private_nat" {
  route_table_id         = aws_route_table.management_private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.management.id
}

resource "aws_route" "app_private_nat" {
  route_table_id         = aws_route_table.app_private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.app.id
}

resource "aws_route" "inspection_private_nat" {
  route_table_id         = aws_route_table.inspection_private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.inspection.id
}

############################
# SECURITY GROUPS
############################

resource "aws_security_group" "management_sg" {
  name        = "management-sg"
  description = "Allow SSH to Bastion"
  vpc_id      = aws_vpc.management.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.office_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "app_sg" {
  name        = "app-sg"
  description = "Allow HTTP/HTTPS"
  vpc_id      = aws_vpc.app.id

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
}

# Inspection Security Group (SSM port-forward ready)
resource "aws_security_group" "inspection_sg" {
  name        = "inspection-sg"
  description = "Allow SSM port forwarding (22/443)"
  vpc_id      = aws_vpc.inspection.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.office_ip]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.office_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

############################
# EC2 INSTANCES
############################

# Bastion Host
resource "aws_instance" "bastion" {
  ami           = "ami-0c5204531f799e0c6"
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.management_public.id
  key_name      = var.key_pair
  security_groups = [
    aws_security_group.management_sg.name
  ]
  tags = { Name = "Management-Bastion" }
}

# NGINX Webserver
resource "aws_instance" "nginx" {
  ami           = "ami-0c5204531f799e0c6"
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.app_private.id
  key_name      = var.key_pair
  security_groups = [
    aws_security_group.app_sg.name
  ]

  tags = { Name = "App-NGINX" }

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              amazon-linux-extras install nginx1 -y
              systemctl enable nginx
              systemctl start nginx
              EOF
}

############################
# VPC PEERING
############################

resource "aws_vpc_peering_connection" "management_app" {
  vpc_id      = aws_vpc.management.id
  peer_vpc_id = aws_vpc.app.id
  auto_accept = true
  tags = { Name = "Management-App-Peering" }
}

# Routes for VPC Peering
resource "aws_route" "management_to_app" {
  route_table_id            = aws_route_table.management_private.id
  destination_cidr_block    = aws_vpc.app.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.management_app.id
}

resource "aws_route" "app_to_management" {
  route_table_id            = aws_route_table.app_private.id
  destination_cidr_block    = aws_vpc.management.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.management_app.id
}

############################
# PLACEHOLDER: PALO ALTO NVA
############################

# Attach your Palo Alto NVA instances or NLB here in the Inspection VPC
# Example route placeholder to Inspection VPC via NVA (update NVA ID when ready)
# resource "aws_route" "management_to_inspection" {
#   route_table_id         = aws_route_table.management_private.id
#   destination_cidr_block = aws_vpc.inspection.cidr_block
#   network_interface_id   = aws_instance.palo_alto_nva.primary_network_interface_id
# }

