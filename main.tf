############################################
# Terraform Cloud + Provider (Option B: Private Bastion + SSM, Zero Public)
############################################
terraform {
  required_version = ">= 1.6.0, < 2.0.0"

  cloud {
    organization = "YOUR_TFC_ORG"

    workspaces {
      name = "cg-adv-option-b-private-bastion-ssm"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "Advantus360"
      Owner       = "Isaac"
      Environment = "lab"
      Purpose     = "OptionB-PrivateBastion-SSM-PaloLogin"
    }
  }
}

############################################
# Variables
############################################
variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "vpc_cidr" {
  description = "CIDR for the VPC"
  type        = string
  default     = "10.30.0.0/16"
}

variable "subnet_cidrs" {
  description = "Private subnets for mgmt and bastion"
  type = object({
    mgmt    : string
    bastion : string
  })
  default = {
    mgmt    = "10.30.10.0/24"
    bastion = "10.30.5.0/24"
  }
}

variable "bastion_instance_type" {
  description = "Bastion instance type"
  type        = string
  default     = "t3.micro"
}

############################################
# VPC + Private Subnets (NO IGW, NO NAT)
############################################
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
}

resource "aws_subnet" "mgmt" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_cidrs.mgmt
  map_public_ip_on_launch = false
}

resource "aws_subnet" "bastion" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_cidrs.bastion
  map_public_ip_on_launch = false
}

# Route tables: VPC-local routes only (no default to IGW/NAT)
resource "aws_route_table" "mgmt" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table_association" "mgmt_assoc" {
  subnet_id      = aws_subnet.mgmt.id
  route_table_id = aws_route_table.mgmt.id
}

resource "aws_route_table" "bastion" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table_association" "bastion_assoc" {
  subnet_id      = aws_subnet.bastion.id
  route_table_id = aws_route_table.bastion.id
}

############################################
# Security Groups (provider v5 rule resources)
############################################
# Bastion SG (SSM-only; no public ingress)
resource "aws_security_group" "sg_bastion" {
  name        = "sg-bastion-ssm"
  description = "Bastion used via SSM (no public ingress)"
  vpc_id      = aws_vpc.main.id
}

resource "aws_vpc_security_group_egress_rule" "bastion_allow_all_egress" {
  security_group_id = aws_security_group.sg_bastion.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "Allow all egress (to VPCEs and VPC)"
}

# Palo MGMT SG (allow 22/443 ONLY from Bastion SG)
resource "aws_security_group" "sg_palo_mgmt" {
  name        = "sg-palo-mgmt"
  description = "Allow SSH/HTTPS from Bastion only"
  vpc_id      = aws_vpc.main.id
}

resource "aws_vpc_security_group_ingress_rule" "palo_allow_ssh_from_bastion" {
  security_group_id            = aws_security_group.sg_palo_mgmt.id
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = aws_security_group.sg_bastion.id
  description                  = "SSH from Bastion"
}

resource "aws_vpc_security_group_ingress_rule" "palo_allow_https_from_bastion" {
  security_group_id            = aws_security_group.sg_palo_mgmt.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.sg_bastion.id
  description                  = "HTTPS from Bastion"
}

resource "aws_vpc_security_group_egress_rule" "palo_allow_all_egress" {
  security_group_id = aws_security_group.sg_palo_mgmt.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "Allow all egress (restrict later as needed)"
}

# VPC Endpoint SG (allow HTTPS from Bastion to SSM endpoints)
resource "aws_security_group" "sg_vpce" {
  name        = "sg-vpce-ssm"
  description = "Allow HTTPS from Bastion to SSM interface endpoints"
  vpc_id      = aws_vpc.main.id
}

resource "aws_vpc_security_group_ingress_rule" "vpce_allow_https_from_bastion" {
  security_group_id            = aws_security_group.sg_vpce.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.sg_bastion.id
  description                  = "HTTPS from Bastion to SSM endpoints"
}

resource "aws_vpc_security_group_egress_rule" "vpce_allow_all_egress" {
  security_group_id = aws_security_group.sg_vpce.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "Allow egress for endpoint responses"
}

############################################
# SSM Interface VPC Endpoints (Private, no Internet)
############################################
data "aws_region" "current" {}

locals {
  ssm_services = [
    "com.amazonaws.${data.aws_region.current.name}.ssm",
    "com.amazonaws.${data.aws_region.current.name}.ssmmessages",
    "com.amazonaws.${data.aws_region.current.name}.ec2messages"
  ]
}

resource "aws_vpc_endpoint" "ssm_endpoints" {
  for_each            = toset(local.ssm_services)
  vpc_id              = aws_vpc.main.id
  service_name        = each.value
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids = [
    aws_subnet.bastion.id,
    aws_subnet.mgmt.id
  ]

  security_group_ids = [
    aws_security_group.sg_vpce.id
  ]
}

############################################
# Bastion IAM (SSM Core) + Instance Profile
############################################
data "aws_iam_policy" "ssm_core" {
  arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role" "bastion_role" {
  name               = "bastion-ssm-core-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "bastion_ssm_attach" {
  role       = aws_iam_role.bastion_role.name
  policy_arn = data.aws_iam_policy.ssm_core.arn
}

resource "aws_iam_instance_profile" "bastion_profile" {
  name = "bastion-ssm-core-profile"
  role = aws_iam_role.bastion_role.name
}

############################################
# Bastion EC2 (NO public IP; SSM-only)
############################################
data "aws_ami" "al2023" {
  owners      = ["amazon"]
  most_recent = true

  filter {
    name   = "name"
    values = [
      "al2023-ami-*-kernel-6.1-*"
    ]
  }

  filter {
    name   = "architecture"
    values = [
      "x86_64"
    ]
  }
}

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.bastion_instance_type
  subnet_id                   = aws_subnet.bastion.id
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.bastion_profile.name

  vpc_security_group_ids = [
    aws_security_group.sg_bastion.id
  ]

  metadata_options {
    http_tokens = "required"
  }
}

############################################
# Outputs
############################################
output "bastion_instance_id" {
  description = "Use this with aws ssm start-session"
  value       = aws_instance.bastion.id
}

output "palo_mgmt_security_group_id" {
  description = "Attach this SG to the Palo MGMT ENI"
  value       = aws_security_group.sg_palo_mgmt.id
}

output "bastion_security_group_id" {
  description = "Bastion host Security Group ID"
  value       = aws_security_group.sg_bastion.id
}

output "ssm_vpc_endpoint_ids" {
  description = "SSM interface endpoint IDs"
  value       = {
    for k, v in aws_vpc_endpoint.ssm_endpoints :
    k => v.id
  }
}

output "how_to_open_palo_https_via_ssm_port_forward" {
  description = "Command to open Palo WebUI via SSM port-forward"
  value       = <<EOT
aws ssm start-session \
  --target ${aws_instance.bastion.id} \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["443"],"localPortNumber":["443"],"host":["10.30.10.34"]}'

Then open: https://localhost:443
(Replace 10.30.10.34 with the actual Palo MGMT IP on its ENI)
EOT
}
