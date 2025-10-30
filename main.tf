########################################
# TERRAFORM & PROVIDER CONFIG
########################################

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

########################################
# VARIABLES
########################################

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-west-2"
}

variable "key_pair" {
  description = "Key pair name (for optional manual SSH)"
  type        = string
  default     = "YOUR_KEY_PAIR"
}

variable "azs" {
  description = "Availability zones list"
  type        = list(string)
  default     = [
    "a",
    "b"
  ]
}

variable "management_vpc_cidr" {
  description = "Management VPC CIDR"
  type        = string
  default     = "10.10.0.0/16"
}

variable "app_vpc_cidr" {
  description = "App VPC CIDR"
  type        = string
  default     = "10.20.0.0/16"
}

variable "inspection_vpc_cidr" {
  description = "Inspection VPC CIDR"
  type        = string
  default     = "10.30.0.0/16"
}

########################################
# VPCs
########################################

resource "aws_vpc" "management" {
  cidr_block           = var.management_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "Management-VPC"
  }
}

resource "aws_vpc" "app" {
  cidr_block           = var.app_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "App-VPC"
  }
}

resource "aws_vpc" "inspection" {
  cidr_block           = var.inspection_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "Inspection-VPC"
  }
}

########################################
# SUBNETS
########################################

resource "aws_subnet" "management_public" {
  vpc_id                  = aws_vpc.management.id
  cidr_block              = "10.10.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}${var.azs[0]}"

  tags = {
    Name = "management-public"
  }
}

resource "aws_subnet" "management_private" {
  vpc_id            = aws_vpc.management.id
  cidr_block        = "10.10.2.0/24"
  availability_zone = "${var.aws_region}${var.azs[1]}"

  tags = {
    Name = "management-private"
  }
}

resource "aws_subnet" "app_public" {
  vpc_id                  = aws_vpc.app.id
  cidr_block              = "10.20.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}${var.azs[0]}"

  tags = {
    Name = "app-public"
  }
}

resource "aws_subnet" "app_private" {
  vpc_id            = aws_vpc.app.id
  cidr_block        = "10.20.2.0/24"
  availability_zone = "${var.aws_region}${var.azs[1]}"

  tags = {
    Name = "app-private"
  }
}

resource "aws_subnet" "inspection_public" {
  vpc_id                  = aws_vpc.inspection.id
  cidr_block              = "10.30.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}${var.azs[0]}"

  tags = {
    Name = "inspection-public"
  }
}

resource "aws_subnet" "inspection_private" {
  vpc_id            = aws_vpc.inspection.id
  cidr_block        = "10.30.2.0/24"
  availability_zone = "${var.aws_region}${var.azs[1]}"

  tags = {
    Name = "inspection-private"
  }
}

# Palo mgmt subnet (eth0)
resource "aws_subnet" "inspection_mgmt" {
  vpc_id                  = aws_vpc.inspection.id
  cidr_block              = "10.30.10.0/24"
  availability_zone       = "${var.aws_region}${var.azs[0]}"
  map_public_ip_on_launch = false

  tags = {
    Name = "inspection-mgmt"
  }
}

########################################
# INTERNET & NAT GATEWAYS
########################################

resource "aws_internet_gateway" "management" {
  vpc_id = aws_vpc.management.id

  tags = {
    Name = "management-igw"
  }
}

resource "aws_internet_gateway" "app" {
  vpc_id = aws_vpc.app.id

  tags = {
    Name = "app-igw"
  }
}

resource "aws_internet_gateway" "inspection" {
  vpc_id = aws_vpc.inspection.id

  tags = {
    Name = "inspection-igw"
  }
}

resource "aws_eip" "management_nat" {
  domain = "vpc"

  tags = {
    Name = "management-nat-eip"
  }
}

resource "aws_eip" "app_nat" {
  domain = "vpc"

  tags = {
    Name = "app-nat-eip"
  }
}

resource "aws_eip" "inspection_nat" {
  domain = "vpc"

  tags = {
    Name = "inspection-nat-eip"
  }
}

resource "aws_nat_gateway" "management" {
  allocation_id = aws_eip.management_nat.id
  subnet_id     = aws_subnet.management_public.id

  tags = {
    Name = "management-nat"
  }
}

resource "aws_nat_gateway" "app" {
  allocation_id = aws_eip.app_nat.id
  subnet_id     = aws_subnet.app_public.id

  tags = {
    Name = "app-nat"
  }
}

resource "aws_nat_gateway" "inspection" {
  allocation_id = aws_eip.inspection_nat.id
  subnet_id     = aws_subnet.inspection_public.id

  tags = {
    Name = "inspection-nat"
  }
}

########################################
# ROUTE TABLES
########################################

# -------- PUBLIC RTs (IGW egress) --------

resource "aws_route_table" "management_public" {
  vpc_id = aws_vpc.management.id

  tags = {
    Name = "management-public-rt"
  }
}

resource "aws_route" "management_public_default" {
  route_table_id         = aws_route_table.management_public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.management.id
}

resource "aws_route_table_association" "management_public_assoc" {
  subnet_id      = aws_subnet.management_public.id
  route_table_id = aws_route_table.management_public.id
}

resource "aws_route_table" "app_public" {
  vpc_id = aws_vpc.app.id

  tags = {
    Name = "app-public-rt"
  }
}

resource "aws_route" "app_public_default" {
  route_table_id         = aws_route_table.app_public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.app.id
}

resource "aws_route_table_association" "app_public_assoc" {
  subnet_id      = aws_subnet.app_public.id
  route_table_id = aws_route_table.app_public.id
}

resource "aws_route_table" "inspection_public" {
  vpc_id = aws_vpc.inspection.id

  tags = {
    Name = "inspection-public-rt"
  }
}

resource "aws_route" "inspection_public_default" {
  route_table_id         = aws_route_table.inspection_public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.inspection.id
}

resource "aws_route_table_association" "inspection_public_assoc" {
  subnet_id      = aws_subnet.inspection_public.id
  route_table_id = aws_route_table.inspection_public.id
}

# -------- PRIVATE RTs (NAT egress) --------

resource "aws_route_table" "management_private" {
  vpc_id = aws_vpc.management.id

  tags = {
    Name = "management-private-rt"
  }
}

resource "aws_route" "management_private_default" {
  route_table_id         = aws_route_table.management_private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.management.id
}

resource "aws_route_table_association" "management_private_assoc" {
  subnet_id      = aws_subnet.management_private.id
  route_table_id = aws_route_table.management_private.id
}

resource "aws_route_table" "app_private" {
  vpc_id = aws_vpc.app.id

  tags = {
    Name = "app-private-rt"
  }
}

resource "aws_route" "app_private_default" {
  route_table_id         = aws_route_table.app_private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.app.id
}

resource "aws_route_table_association" "app_private_assoc" {
  subnet_id      = aws_subnet.app_private.id
  route_table_id = aws_route_table.app_private.id
}

resource "aws_route_table" "inspection_private" {
  vpc_id = aws_vpc.inspection.id

  tags = {
    Name = "inspection-private-rt"
  }
}

resource "aws_route" "inspection_private_default" {
  route_table_id         = aws_route_table.inspection_private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.inspection.id
}

resource "aws_route_table_association" "inspection_private_assoc" {
  subnet_id      = aws_subnet.inspection_private.id
  route_table_id = aws_route_table.inspection_private.id
}

########################################
# TRANSIT GATEWAY
########################################

resource "aws_ec2_transit_gateway" "tgw" {
  description = "Central TGW for inter-VPC routing"

  tags = {
    Name = "Main-TGW"
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "management_attach" {
  subnet_ids         = [aws_subnet.management_private.id]
  transit_gateway_id = aws_ec2_transit_gateway.tgw.id
  vpc_id             = aws_vpc.management.id

  tags = {
    Name = "TGW-Attach-Management"
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "app_attach" {
  subnet_ids         = [aws_subnet.app_private.id]
  transit_gateway_id = aws_ec2_transit_gateway.tgw.id
  vpc_id             = aws_vpc.app.id

  tags = {
    Name = "TGW-Attach-App"
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "inspection_attach" {
  subnet_ids         = [aws_subnet.inspection_private.id]
  transit_gateway_id = aws_ec2_transit_gateway.tgw.id
  vpc_id             = aws_vpc.inspection.id

  tags = {
    Name = "TGW-Attach-Inspection"
  }
}

resource "aws_ec2_transit_gateway_route_table" "main" {
  transit_gateway_id = aws_ec2_transit_gateway.tgw.id

  tags = {
    Name = "TGW-Main-Route-Table"
  }
}

resource "aws_ec2_transit_gateway_route" "route_to_management" {
  destination_cidr_block         = var.management_vpc_cidr
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.management_attach.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.main.id
}

resource "aws_ec2_transit_gateway_route" "route_to_app" {
  destination_cidr_block         = var.app_vpc_cidr
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.app_attach.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.main.id
}

resource "aws_ec2_transit_gateway_route" "route_to_inspection" {
  destination_cidr_block         = var.inspection_vpc_cidr
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.inspection_attach.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.main.id
}

########################################
# IAM ROLE FOR SSM
########################################

data "aws_iam_policy" "ssm_managed" {
  arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role" "ssm_role" {
  name = "SSMInstanceRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_attach" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = data.aws_iam_policy.ssm_managed.arn
}

resource "aws_iam_instance_profile" "ssm_profile" {
  name = "SSMInstanceProfile"
  role = aws_iam_role.ssm_role.name
}

########################################
# SECURITY GROUPS
########################################

resource "aws_security_group" "management_sg" {
  name        = "management-sg"
  description = "Allow SSM and internal"
  vpc_id      = aws_vpc.management.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "app_sg" {
  name        = "app-sg"
  description = "Allow HTTP/HTTPS internally"
  vpc_id      = aws_vpc.app.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.inspection.cidr_block]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.inspection.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Palo Alto Management SG (for mgmt eth0 in inspection-mgmt subnet)
resource "aws_security_group" "palo_mgmt_sg" {
  name        = "palo-mgmt-sg"
  description = "Security group for Palo Alto management interface"
  vpc_id      = aws_vpc.inspection.id

  ingress {
    description = "Allow HTTPS (GUI) from Inspection VPC only"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.inspection_vpc_cidr]
  }

  ingress {
    description = "Allow SSH from Inspection VPC only (optional)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.inspection_vpc_cidr]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "palo-mgmt-sg"
  }
}

########################################
# INSTANCES (SSM-ENABLED)
########################################

resource "aws_instance" "bastion" {
  ami                  = "ami-0c5204531f799e0c6"
  instance_type        = "t3.micro"
  subnet_id            = aws_subnet.management_private.id
  iam_instance_profile = aws_iam_instance_profile.ssm_profile.name
  security_groups      = [aws_security_group.management_sg.id]

  tags = {
    Name = "Management-Bastion"
  }
}

resource "aws_instance" "nginx" {
  ami                  = "ami-0c5204531f799e0c6"
  instance_type        = "t3.micro"
  subnet_id            = aws_subnet.app_private.id
  iam_instance_profile = aws_iam_instance_profile.ssm_profile.name
  security_groups      = [aws_security_group.app_sg.id]

  tags = {
    Name = "App-NGINX"
  }

  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    amazon-linux-extras install nginx1 -y
    systemctl enable nginx
    systemctl start nginx
  EOF
}

########################################
# PLACEHOLDER - PALO ALTO NVA
########################################

# Manually deploy Palo Alto in Inspection VPC with three ENIs:
#  - eth0 (mgmt)  -> subnet: aws_subnet.inspection_mgmt.id  + SG: aws_security_group.palo_mgmt_sg.id
#  - eth1 (untrust) -> subnet: aws_subnet.inspection_public.id (assign EIP)
#  - eth2 (trust)   -> subnet: aws_subnet.inspection_private.id
# Then steer TGW routes through the firewall for egress / East-West.
