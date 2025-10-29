############################################
# cg-adv — Phase 1: Base Network & Security (SSM-only, no public ingress)
# - VPC + mgmt/trust/untrust subnets (1 AZ for Phase 1)
# - Separate route tables
# - SSM bastion (no public IP)
# - VPC Interface Endpoints: ssm, ssmmessages, ec2messages
# - VPC Flow Logs -> CloudWatch
# - Security: NO inbound rules (SSM-only)
############################################

terraform {
  required_version = ">= 1.6.0, < 2.0.0"

  # Uncomment if using Terraform Cloud
  # cloud {
  #   organization = "cloudgenius_global"
  #   workspaces {
  #     name = "aws-workpackage"
  #   }
  # }

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
  description = "Primary VPC CIDR"
  type        = string
  default     = "10.20.0.0/16"
}

variable "az_1" {
  description = "Primary AZ"
  type        = string
  default     = "us-west-2a"
}

variable "mgmt_cidr" {
  description = "CIDR for mgmt subnet"
  type        = string
  default     = "10.20.1.0/24"
}

variable "trust_cidr" {
  description = "CIDR for trust subnet"
  type        = string
  default     = "10.20.11.0/24"
}

variable "untrust_cidr" {
  description = "CIDR for untrust subnet"
  type        = string
  default     = "10.20.21.0/24"
}

variable "bastion_instance_type" {
  description = "Instance type for SSM bastion"
  type        = string
  default     = "t3.micro"
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

  tags = {
    Name = "mgmt-az1"
  }
}

resource "aws_subnet" "trust_az1" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.trust_cidr
  availability_zone = var.az_1

  tags = {
    Name = "trust-az1"
  }
}

resource "aws_subnet" "untrust_az1" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.untrust_cidr
  availability_zone = var.az_1

  tags = {
    Name = "untrust-az1"
  }
}

############################################
# Route Tables (separated; no IGW/NAT in Phase 1)
############################################
resource "aws_route_table" "rtb_mgmt" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "rtb-mgmt-az1"
  }
}

resource "aws_route_table_association" "rta_mgmt" {
  route_table_id = aws_route_table.rtb_mgmt.id
  subnet_id      = aws_subnet.mgmt_az1.id
}

resource "aws_route_table" "rtb_trust" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "rtb-trust-az1"
  }
}

resource "aws_route_table_association" "rta_trust" {
  route_table_id = aws_route_table.rtb_trust.id
  subnet_id      = aws_subnet.trust_az1.id
}

resource "aws_route_table" "rtb_untrust" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "rtb-untrust-az1"
  }
}

resource "aws_route_table_association" "rta_untrust" {
  route_table_id = aws_route_table.rtb_untrust.id
  subnet_id      = aws_subnet.untrust_az1.id
}

############################################
# Security Groups
############################################

# Management SG (no inbound; SSM-only)
resource "aws_security_group" "mgmt_sg" {
  name        = "sg-mgmt"
  description = "No inbound (SSM-only). All egress."
  vpc_id      = aws_vpc.this.id

  # No ingress blocks = default deny
  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sg-mgmt"
  }
}

# Interface Endpoints SG (allow 443 from inside VPC)
resource "aws_security_group" "endpoints_sg" {
  name        = "sg-vpce"
  description = "Allow HTTPS from VPC to interface endpoints"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sg-vpce"
  }
}

# Default-deny SG for trust/untrust (no ingress)
resource "aws_security_group" "default_deny" {
  name        = "sg-default-deny"
  description = "No inbound; all egress"
  vpc_id      = aws_vpc.this.id

  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sg-default-deny"
  }
}

############################################
# VPC Interface Endpoints for SSM
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

  tags = {
    Name = "vpce-${replace(each.value, ".", "-")}"
  }
}

############################################
# SSM Bastion (no public IP, SSM-only)
############################################
# AMI: Amazon Linux 2023 (has SSM agent)
data "aws_ami" "al2023" {
  owners      = ["137112412989"]
  most_recent = true

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# IAM for SSM
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
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.bastion_instance_type
  subnet_id                   = aws_subnet.mgmt_az1.id
  iam_instance_profile        = aws_iam_instance_profile.bastion_profile.name
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.mgmt_sg.id]

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = {
    Name = "cg-adv-ssm-bastion"
  }
}

############################################
# VPC Flow Logs -> CloudWatch
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
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents"
    ]
    resources = [
      aws_cloudwatch_log_group.vpc_flow.arn,
      "${aws_cloudwatch_log_group.vpc_flow.arn}:*"
    ]
  }
}

resource "aws_iam_role_policy" "flowlog_inline" {
  name   = "cg-adv-vpc-flow-logs-to-cwl"
  role   = aws_iam_role.flowlog_role.id
  policy = data.aws_iam_policy_document.flowlog_cwl_policy.json
}

resource "aws_flow_log" "vpc" {
  log_destination      = aws_cloudwatch_log_group.vpc_flow.arn
  log_destination_type = "cloud-watch-logs"
  traffic_type         = "ALL"
  vpc_id               = aws_vpc.this.id
  iam_role_arn         = aws_iam_role.flowlog_role.arn

  tags = {
    Name = "cg-adv-vpc-flow-logs"
  }
}

############################################
# Outputs
############################################
output "vpc_id" {
  value = aws_vpc.this.id
}

output "subnets" {
  value = {
    mgmt_az1   = aws_subnet.mgmt_az1.id
    trust_az1  = aws_subnet.trust_az1.id
    untrust_az1= aws_subnet.untrust_az1.id
  }
}

output "ssm_bastion_instance_id" {
  value = aws_instance.ssm_bastion.id
}

output "vpce_ids" {
  value = { for k, v in aws_vpc_endpoint.ssm_ifaces : k => v.id }
}

output "how_to_port_forward_https_from_bastion" {
  value = "aws ssm start-session --target ${aws_instance.ssm_bastion.id} --document-name AWS-StartPortForwardingSessionToRemoteHost --parameters '{\"host\":[\"<FIREWALL_MGMT_IP>\"],\"portNumber\":[\"443\"],\"localPortNumber\":[\"8443\"]}'"
}
