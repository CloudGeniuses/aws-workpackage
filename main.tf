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
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "key_pair" {
  description = "Existing key pair to allow optional SSH"
  type        = string
  default     = "palo-nva-fw-01"
}

variable "azs" {
  description = "AZ suffixes"
  type        = list(string)
  default     = [
    "a",
    "b",
  ]
}

variable "management_vpc_cidr" {
  type    = string
  default = "10.10.0.0/16"
}

variable "app_vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "inspection_vpc_cidr" {
  type    = string
  default = "10.30.0.0/16"
}

########################################
# LOCALS
########################################

locals {
  bastion_subnet_cidr = "10.10.2.0/24"
}

########################################
# VPCs
########################################

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

########################################
# SUBNETS
########################################

resource "aws_subnet" "management_public" {
  vpc_id                  = aws_vpc.management.id
  cidr_block              = "10.10.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}${var.azs[0]}"
  tags = { Name = "management-public" }
}

resource "aws_subnet" "management_private" {
  vpc_id            = aws_vpc.management.id
  cidr_block        = local.bastion_subnet_cidr
  availability_zone = "${var.aws_region}${var.azs[1]}"
  tags = { Name = "management-private" }
}

resource "aws_subnet" "app_private" {
  vpc_id            = aws_vpc.app.id
  cidr_block        = "10.20.2.0/24"
  availability_zone = "${var.aws_region}${var.azs[1]}"
  tags              = { Name = "app-private" }
}

resource "aws_subnet" "inspection_private" {
  vpc_id            = aws_vpc.inspection.id
  cidr_block        = "10.30.2.0/24"
  availability_zone = "${var.aws_region}${var.azs[1]}"
  tags              = { Name = "inspection-private" }
}

resource "aws_subnet" "inspection_mgmt" {
  vpc_id            = aws_vpc.inspection.id
  cidr_block        = "10.30.10.0/24"
  availability_zone = "${var.aws_region}${var.azs[0]}"
  tags              = { Name = "inspection-mgmt" }
}

########################################
# INTERNET & NAT
########################################

resource "aws_internet_gateway" "management" {
  vpc_id = aws_vpc.management.id
}

resource "aws_internet_gateway" "app" {
  vpc_id = aws_vpc.app.id
}

resource "aws_internet_gateway" "inspection" {
  vpc_id = aws_vpc.inspection.id
}

resource "aws_eip" "management_nat" {
  domain = "vpc"
}

resource "aws_eip" "app_nat" {
  domain = "vpc"
}

resource "aws_eip" "inspection_nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "management" {
  allocation_id = aws_eip.management_nat.id
  subnet_id     = aws_subnet.management_public.id
}

resource "aws_nat_gateway" "app" {
  allocation_id = aws_eip.app_nat.id
  subnet_id     = aws_subnet.management_public.id
}

resource "aws_nat_gateway" "inspection" {
  allocation_id = aws_eip.inspection_nat.id
  subnet_id     = aws_subnet.management_public.id
}

########################################
# ROUTING (simplified, clean, TGW enabled)
########################################

resource "aws_route_table" "inspection_private" {
  vpc_id = aws_vpc.inspection.id
}

resource "aws_route_table_association" "inspection_private_assoc" {
  subnet_id      = aws_subnet.inspection_private.id
  route_table_id = aws_route_table.inspection_private.id
}

resource "aws_route_table_association" "inspection_mgmt_assoc" {
  subnet_id      = aws_subnet.inspection_mgmt.id
  route_table_id = aws_route_table.inspection_private.id
}

########################################
# TGW
########################################

resource "aws_ec2_transit_gateway" "tgw" {
  tags = { Name = "Main-TGW" }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "inspection_attach" {
  transit_gateway_id = aws_ec2_transit_gateway.tgw.id
  vpc_id             = aws_vpc.inspection.id
  subnet_ids         = [aws_subnet.inspection_private.id]
}

resource "aws_ec2_transit_gateway_route_table" "main" {
  transit_gateway_id = aws_ec2_transit_gateway.tgw.id
}

resource "aws_ec2_transit_gateway_route_table_association" "inspection_assoc" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.inspection_attach.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.main.id
}

########################################
# IAM / SSM
########################################

data "aws_iam_policy" "ssm_core" {
  arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role" "ssm_role" {
  name = "SSMInstanceRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_attach" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = data.aws_iam_policy.ssm_core.arn
}

resource "aws_iam_instance_profile" "ssm_profile" {
  name = "SSMInstanceProfile"
  role = aws_iam_role.ssm_role.name
}

########################################
# SECURITY GROUPS (CLEAN, NO INLINE RULES)
########################################

resource "aws_security_group" "palo_mgmt_sg" {
  name        = "palo-mgmt-sg"
  description = "Mgmt interface firewall SG"
  vpc_id      = aws_vpc.inspection.id
}

resource "aws_security_group_rule" "palo_tls_mgmt" {
  type              = "ingress"
  security_group_id = aws_security_group.palo_mgmt_sg.id
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = [local.bastion_subnet_cidr]
}

resource "aws_security_group_rule" "palo_ssh_mgmt" {
  type              = "ingress"
  security_group_id = aws_security_group.palo_mgmt_sg.id
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [local.bastion_subnet_cidr]
}

resource "aws_security_group_rule" "palo_egress_all" {
  type              = "egress"
  security_group_id = aws_security_group.palo_mgmt_sg.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

########################################
# INSTANCES (SSM-ENABLED)
########################################

resource "aws_instance" "bastion" {
  ami                   = "ami-0c5204531f799e0c6"
  instance_type         = "t3.micro"
  subnet_id             = aws_subnet.management_private.id
  vpc_security_group_ids = []
  iam_instance_profile  = aws_iam_instance_profile.ssm_profile.name
  key_name              = var.key_pair

  tags = { Name = "Management-Bastion" }
}

resource "aws_instance" "nginx" {
  ami                   = "ami-0c5204531f799e0c6"
  instance_type         = "t3.micro"
  subnet_id             = aws_subnet.app_private.id
  vpc_security_group_ids = []
  iam_instance_profile  = aws_iam_instance_profile.ssm_profile.name
  key_name              = var.key_pair
  tags = { Name = "App-NGINX" }
}
