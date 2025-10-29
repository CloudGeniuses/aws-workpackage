############################################
# cg-adv — Phase 1: Base Network & Security (SSM-only, no public ingress)
############################################

terraform {
  required_version = ">= 1.6.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"

  default_tags {
    tags = {
      Project     = "Advantus360"
      Owner       = "Isaac"
      Environment = "lab"
      CostCenter  = "CloudGenius"
    }
  }
}

############################################
# Variables
############################################

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "az_1" {
  type    = string
  default = "us-west-2a"
}

variable "mgmt_cidr" {
  type    = string
  default = "10.20.1.0/24"
}

variable "trust_cidr" {
  type    = string
  default = "10.20.11.0/24"
}

variable "untrust_cidr" {
  type    = string
  default = "10.20.21.0/24"
}

variable "bastion_instance_type" {
  type    = string
  default = "t3.micro"
}

############################################
# VPC + Subnets
############################################

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "cg-adv-vpc"
  }
}

resource "aws_subnet" "mgmt_az1" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.mgmt_cidr
  availability_zone       = var.az_1
  map_public_ip_on_launch = false

  tags = { Name = "mgmt-az1" }
}

resource "aws_subnet" "trust_az1" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.trust_cidr
  availability_zone = var.az_1

  tags = { Name = "trust-az1" }
}

resource "aws_subnet" "untrust_az1" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.untrust_cidr
  availability_zone = var.az_1

  tags = { Name = "untrust-az1" }
}

############################################
# Route Tables
############################################

resource "aws_route_table" "rtb_mgmt" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "rtb-mgmt-az1" }
}

resource "aws_route_table_association" "rta_mgmt" {
  subnet_id      = aws_subnet.mgmt_az1.id
  route_table_id = aws_route_table.rtb_mgmt.id
}

resource "aws_route_table" "rtb_trust" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "rtb-trust-az1" }
}

resource "aws_route_table_association" "rta_trust" {
  subnet_id      = aws_subnet.trust_az1.id
  route_table_id = aws_route_table.rtb_trust.id
}

resource "aws_route_table" "rtb_untrust" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "rtb-untrust-az1" }
}

resource "aws_route_table_association" "rta_untrust" {
  subnet_id      = aws_subnet.untrust_az1.id
  route_table_id = aws_route_table.rtb_untrust.id
}

############################################
# Security Groups (Fixed Name Attribute)
############################################

resource "aws_security_group" "mgmt_sg" {
  name        = "adv-mgmt"             # ✅ FIXED (cannot start with sg-)
  description = "No inbound (SSM-only)"
  vpc_id      = aws_vpc.this.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "sg-mgmt" }          # ✅ Tag is fine
}

resource "aws_security_group" "endpoints_sg" {
  name        = "adv-vpce"             # ✅ FIXED
  description = "Allow HTTPS inside VPC to Interface Endpoints"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "sg-vpce" }
}

resource "aws_security_group" "default_deny" {
  name        = "adv-default-deny"     # ✅ FIXED
  description = "Deny inbound, allow outbound"
  vpc_id      = aws_vpc.this.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "sg-default-deny" }
}

############################################
# SSM VPC Endpoints
############################################

data "aws_region" "current" {}

locals {
  ssm_services = [
    "com.amazonaws.${data.aws_region.current.name}.ssm",
    "com.amazonaws.${data.aws_region.current.name}.ssmmessages",
    "com.amazonaws.${data.aws_region.current.name}.ec2messages"
  ]
}

resource "aws_vpc_endpoint" "ssm_ifaces" {
  for_each            = toset(local.ssm_services)
  vpc_id              = aws_vpc.this.id
  service_name        = each.value
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  security_group_ids  = [aws_security_group.endpoints_sg.id]
  subnet_ids          = [aws_subnet.mgmt_az1.id]

  tags = { Name = "vpce-${replace(each.value, ".", "-")}" }
}

############################################
# SSM Bastion (No Public IP)
############################################

data "aws_ami" "al2023" {
  owners      = ["137112412989"]
  most_recent = true

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

data "aws_iam_policy" "ssm_core" {
  arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "bastion_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "bastion_role" {
  name               = "cg-adv-ssm-bastion-role"
  assume_role_policy = data.aws_iam_policy_document.bastion_trust.json
}

resource "aws_iam_role_policy_attachment" "bastion_attach" {
  role       = aws_iam_role.bastion_role.name
  policy_arn = data.aws_iam_policy.ssm_core.arn
}

resource "aws_iam_instance_profile" "bastion_profile" {
  name = "cg-adv-ssm-bastion-profile"
  role = aws_iam_role.bastion_role.name
}

resource "aws_instance" "ssm_bastion" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.bastion_instance_type
  subnet_id              = aws_subnet.mgmt_az1.id
  iam_instance_profile   = aws_iam_instance_profile.bastion_profile.name
  vpc_security_group_ids = [aws_security_group.mgmt_sg.id]
  associate_public_ip_address = false

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = { Name = "cg-adv-ssm-bastion" }
}

############################################
# VPC Flow Logs → CloudWatch
############################################

resource "aws_cloudwatch_log_group" "vpc_flow" {
  name              = "/aws/vpc/flow-logs/${aws_vpc.this.id}"
  retention_in_days = 14
}

data "aws_iam_policy_document" "flowlog_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flowlog_role" {
  name               = "cg-adv-vpc-flow-logs-role"
  assume_role_policy = data.aws_iam_policy_document.flowlog_assume.json
}

data "aws_iam_policy_document" "flowlog_cwl_policy" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["${aws_cloudwatch_log_group.vpc_flow.arn}:*"]
  }
}

resource "aws_iam_role_policy" "flowlog_inline" {
  name   = "cg-adv-vpc-flow-logs-to-cwl"
  role   = aws_iam_role.flowlog_role.id
  policy = data.aws_iam_policy_document.flowlog_cwl_policy.json
}

resource "aws_flow_log" "vpc" {
  vpc_id               = aws_vpc.this.id
  traffic_type         = "ALL"
  log_destination      = aws_cloudwatch_log_group.vpc_flow.arn
  log_destination_type = "cloud-watch-logs"
  iam_role_arn         = aws_iam_role.flowlog_role.arn

  tags = { Name = "cg-adv-vpc-flow-logs" }
}

############################################
# Outputs
############################################

output "ssm_bastion_instance_id" {
  value = aws_instance.ssm_bastion.id
}
