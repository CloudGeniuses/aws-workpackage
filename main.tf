############################################
# Advantus360 – Centralized Inspection POC (Final, S3 optional commented)
# TGW + GWLB + 3 VPCs (Mgmt / App / Inspection)
# - Palo Alto NVA: manual deploy (you add two trust IPs to GWLB TG)
# - HA across 2 AZs
# - East/West via TGW → Inspection
# - Egress control through Palo (spokes default to TGW)
# - Ingress service-chaining (NLB → GWLBe → GWLB → Palo) for:
#     * HTTP/HTTPS to App web
#     * SSH to Mgmt bastion
# - Variables are multi-line; HCL is Terraform Cloud–ready
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

############################################
# Variables (multi-line)
############################################

variable "aws_region" {
  type    = string
  default = "us-west-2"
}

variable "az_1" {
  type    = string
  default = "us-west-2a"
}

variable "az_2" {
  type    = string
  default = "us-west-2b"
}

# VPC CIDRs
variable "mgmt_cidr" {
  type    = string
  default = "10.10.0.0/16"
}

variable "app_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "inspection_cidr" {
  type    = string
  default = "10.30.0.0/16"
}

# Mgmt subnets (private + TGW + public for NLB ingress)
variable "mgmt_priv_az1" {
  type    = string
  default = "10.10.1.0/24"
}

variable "mgmt_priv_az2" {
  type    = string
  default = "10.10.2.0/24"
}

variable "mgmt_tgw_az1" {
  type    = string
  default = "10.10.10.0/24"
}

variable "mgmt_tgw_az2" {
  type    = string
  default = "10.10.11.0/24"
}

variable "mgmt_pub_az1" {
  type    = string
  default = "10.10.101.0/24"
}

variable "mgmt_pub_az2" {
  type    = string
  default = "10.10.102.0/24"
}

# App subnets (private + TGW + public for NLB ingress)
variable "app_priv_az1" {
  type    = string
  default = "10.20.1.0/24"
}

variable "app_priv_az2" {
  type    = string
  default = "10.20.2.0/24"
}

variable "app_pub_az1" {
  type    = string
  default = "10.20.101.0/24"
}

variable "app_pub_az2" {
  type    = string
  default = "10.20.102.0/24"
}

variable "app_tgw_az1" {
  type    = string
  default = "10.20.10.0/24"
}

variable "app_tgw_az2" {
  type    = string
  default = "10.20.11.0/24"
}

# Inspection subnets (mgmt/trust/untrust/gwlb/tgw)
variable "ins_mgmt_az1" {
  type    = string
  default = "10.30.1.0/24"
}

variable "ins_mgmt_az2" {
  type    = string
  default = "10.30.2.0/24"
}

variable "ins_trust_az1" {
  type    = string
  default = "10.30.11.0/24"
}

variable "ins_trust_az2" {
  type    = string
  default = "10.30.12.0/24"
}

variable "ins_untr_az1" {
  type    = string
  default = "10.30.21.0/24"
}

variable "ins_untr_az2" {
  type    = string
  default = "10.30.22.0/24"
}

variable "ins_gwlb_az1" {
  type    = string
  default = "10.30.31.0/24"
}

variable "ins_gwlb_az2" {
  type    = string
  default = "10.30.32.0/24"
}

variable "ins_tgw_az1" {
  type    = string
  default = "10.30.41.0/24"
}

variable "ins_tgw_az2" {
  type    = string
  default = "10.30.42.0/24"
}

variable "bastion_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "web_instance_type" {
  type    = string
  default = "t3.micro"
}

############################################
# Provider & Default Tags
############################################

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "Advantus360"
      Owner       = "Isaac"
      Environment = "lab"
      CostCenter  = "CloudGenius"
    }
  }
}

data "aws_region" "current" {}

############################################
# VPCs: Mgmt, App, Inspection
############################################

# ---- Mgmt VPC ----
resource "aws_vpc" "mgmt" {
  cidr_block           = var.mgmt_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "cg-adv-mgmt"
  }
}

resource "aws_internet_gateway" "mgmt_igw" {
  vpc_id = aws_vpc.mgmt.id

  tags = {
    Name = "cg-adv-mgmt-igw"
  }
}

resource "aws_subnet" "mgmt_priv_az1" {
  vpc_id                  = aws_vpc.mgmt.id
  cidr_block              = var.mgmt_priv_az1
  availability_zone       = var.az_1
  map_public_ip_on_launch = false

  tags = {
    Name = "mgmt-priv-az1"
  }
}

resource "aws_subnet" "mgmt_priv_az2" {
  vpc_id                  = aws_vpc.mgmt.id
  cidr_block              = var.mgmt_priv_az2
  availability_zone       = var.az_2
  map_public_ip_on_launch = false

  tags = {
    Name = "mgmt-priv-az2"
  }
}

resource "aws_subnet" "mgmt_tgw_az1" {
  vpc_id                  = aws_vpc.mgmt.id
  cidr_block              = var.mgmt_tgw_az1
  availability_zone       = var.az_1
  map_public_ip_on_launch = false

  tags = {
    Name = "mgmt-tgw-az1"
  }
}

resource "aws_subnet" "mgmt_tgw_az2" {
  vpc_id                  = aws_vpc.mgmt.id
  cidr_block              = var.mgmt_tgw_az2
  availability_zone       = var.az_2
  map_public_ip_on_launch = false

  tags = {
    Name = "mgmt-tgw-az2"
  }
}

resource "aws_subnet" "mgmt_pub_az1" {
  vpc_id                  = aws_vpc.mgmt.id
  cidr_block              = var.mgmt_pub_az1
  availability_zone       = var.az_1
  map_public_ip_on_launch = true

  tags = {
    Name = "mgmt-pub-az1"
  }
}

resource "aws_subnet" "mgmt_pub_az2" {
  vpc_id                  = aws_vpc.mgmt.id
  cidr_block              = var.mgmt_pub_az2
  availability_zone       = var.az_2
  map_public_ip_on_launch = true

  tags = {
    Name = "mgmt-pub-az2"
  }
}

# Route tables – Mgmt
resource "aws_route_table" "mgmt_priv_rt_az1" {
  vpc_id = aws_vpc.mgmt.id

  tags = {
    Name = "rt-mgmt-priv-az1"
  }
}

resource "aws_route_table" "mgmt_priv_rt_az2" {
  vpc_id = aws_vpc.mgmt.id

  tags = {
    Name = "rt-mgmt-priv-az2"
  }
}

resource "aws_route_table" "mgmt_pub_rt_az1" {
  vpc_id = aws_vpc.mgmt.id

  tags = {
    Name = "rt-mgmt-pub-az1"
  }
}

resource "aws_route_table" "mgmt_pub_rt_az2" {
  vpc_id = aws_vpc.mgmt.id

  tags = {
    Name = "rt-mgmt-pub-az2"
  }
}

resource "aws_route_table_association" "a_mgmt_priv_az1" {
  subnet_id      = aws_subnet.mgmt_priv_az1.id
  route_table_id = aws_route_table.mgmt_priv_rt_az1.id
}

resource "aws_route_table_association" "a_mgmt_priv_az2" {
  subnet_id      = aws_subnet.mgmt_priv_az2.id
  route_table_id = aws_route_table.mgmt_priv_rt_az2.id
}

resource "aws_route_table_association" "a_mgmt_pub_az1" {
  subnet_id      = aws_subnet.mgmt_pub_az1.id
  route_table_id = aws_route_table.mgmt_pub_rt_az1.id
}

resource "aws_route_table_association" "a_mgmt_pub_az2" {
  subnet_id      = aws_subnet.mgmt_pub_az2.id
  route_table_id = aws_route_table.mgmt_pub_rt_az2.id
}

resource "aws_route" "mgmt_pub_az1_igw" {
  route_table_id         = aws_route_table.mgmt_pub_rt_az1.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.mgmt_igw.id
}

resource "aws_route" "mgmt_pub_az2_igw" {
  route_table_id         = aws_route_table.mgmt_pub_rt_az2.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.mgmt_igw.id
}

# ---- App VPC ----
resource "aws_vpc" "app" {
  cidr_block           = var.app_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "cg-adv-app"
  }
}

resource "aws_internet_gateway" "app_igw" {
  vpc_id = aws_vpc.app.id

  tags = {
    Name = "cg-adv-app-igw"
  }
}

resource "aws_subnet" "app_priv_az1" {
  vpc_id                  = aws_vpc.app.id
  cidr_block              = var.app_priv_az1
  availability_zone       = var.az_1
  map_public_ip_on_launch = false

  tags = {
    Name = "app-priv-az1"
  }
}

resource "aws_subnet" "app_priv_az2" {
  vpc_id                  = aws_vpc.app.id
  cidr_block              = var.app_priv_az2
  availability_zone       = var.az_2
  map_public_ip_on_launch = false

  tags = {
    Name = "app-priv-az2"
  }
}

resource "aws_subnet" "app_pub_az1" {
  vpc_id                  = aws_vpc.app.id
  cidr_block              = var.app_pub_az1
  availability_zone       = var.az_1
  map_public_ip_on_launch = true

  tags = {
    Name = "app-pub-az1"
  }
}

resource "aws_subnet" "app_pub_az2" {
  vpc_id                  = aws_vpc.app.id
  cidr_block              = var.app_pub_az2
  availability_zone       = var.az_2
  map_public_ip_on_launch = true

  tags = {
    Name = "app-pub-az2"
  }
}

resource "aws_subnet" "app_tgw_az1" {
  vpc_id                  = aws_vpc.app.id
  cidr_block              = var.app_tgw_az1
  availability_zone       = var.az_1
  map_public_ip_on_launch = false

  tags = {
    Name = "app-tgw-az1"
  }
}

resource "aws_subnet" "app_tgw_az2" {
  vpc_id                  = aws_vpc.app.id
  cidr_block              = var.app_tgw_az2
  availability_zone       = var.az_2
  map_public_ip_on_launch = false

  tags = {
    Name = "app-tgw-az2"
  }
}

resource "aws_route_table" "app_priv_rt_az1" {
  vpc_id = aws_vpc.app.id

  tags = {
    Name = "rt-app-priv-az1"
  }
}

resource "aws_route_table" "app_priv_rt_az2" {
  vpc_id = aws_vpc.app.id

  tags = {
    Name = "rt-app-priv-az2"
  }
}

resource "aws_route_table" "app_pub_rt_az1" {
  vpc_id = aws_vpc.app.id

  tags = {
    Name = "rt-app-pub-az1"
  }
}

resource "aws_route_table" "app_pub_rt_az2" {
  vpc_id = aws_vpc.app.id

  tags = {
    Name = "rt-app-pub-az2"
  }
}

resource "aws_route_table_association" "a_app_priv_az1" {
  subnet_id      = aws_subnet.app_priv_az1.id
  route_table_id = aws_route_table.app_priv_rt_az1.id
}

resource "aws_route_table_association" "a_app_priv_az2" {
  subnet_id      = aws_subnet.app_priv_az2.id
  route_table_id = aws_route_table.app_priv_rt_az2.id
}

resource "aws_route_table_association" "a_app_pub_az1" {
  subnet_id      = aws_subnet.app_pub_az1.id
  route_table_id = aws_route_table.app_pub_rt_az1.id
}

resource "aws_route_table_association" "a_app_pub_az2" {
  subnet_id      = aws_subnet.app_pub_az2.id
  route_table_id = aws_route_table.app_pub_rt_az2.id
}

resource "aws_route" "app_pub_az1_igw" {
  route_table_id         = aws_route_table.app_pub_rt_az1.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.app_igw.id
}

resource "aws_route" "app_pub_az2_igw" {
  route_table_id         = aws_route_table.app_pub_rt_az2.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.app_igw.id
}

# ---- Inspection VPC ----
resource "aws_vpc" "ins" {
  cidr_block           = var.inspection_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "cg-adv-inspection"
  }
}

resource "aws_internet_gateway" "ins_igw" {
  vpc_id = aws_vpc.ins.id

  tags = {
    Name = "cg-adv-ins-igw"
  }
}

resource "aws_subnet" "ins_mgmt_az1" {
  vpc_id                  = aws_vpc.ins.id
  cidr_block              = var.ins_mgmt_az1
  availability_zone       = var.az_1
  map_public_ip_on_launch = false

  tags = {
    Name = "ins-mgmt-az1"
  }
}

resource "aws_subnet" "ins_mgmt_az2" {
  vpc_id                  = aws_vpc.ins.id
  cidr_block              = var.ins_mgmt_az2
  availability_zone       = var.az_2
  map_public_ip_on_launch = false

  tags = {
    Name = "ins-mgmt-az2"
  }
}

resource "aws_subnet" "ins_trust_az1" {
  vpc_id            = aws_vpc.ins.id
  cidr_block        = var.ins_trust_az1
  availability_zone = var.az_1

  tags = {
    Name = "ins-trust-az1"
  }
}

resource "aws_subnet" "ins_trust_az2" {
  vpc_id            = aws_vpc.ins.id
  cidr_block        = var.ins_trust_az2
  availability_zone = var.az_2

  tags = {
    Name = "ins-trust-az2"
  }
}

resource "aws_subnet" "ins_untr_az1" {
  vpc_id            = aws_vpc.ins.id
  cidr_block        = var.ins_untr_az1
  availability_zone = var.az_1

  tags = {
    Name = "ins-untrust-az1"
  }
}

resource "aws_subnet" "ins_untr_az2" {
  vpc_id            = aws_vpc.ins.id
  cidr_block        = var.ins_untr_az2
  availability_zone = var.az_2

  tags = {
    Name = "ins-untrust-az2"
  }
}

resource "aws_subnet" "ins_gwlb_az1" {
  vpc_id            = aws_vpc.ins.id
  cidr_block        = var.ins_gwlb_az1
  availability_zone = var.az_1

  tags = {
    Name = "ins-gwlb-az1"
  }
}

resource "aws_subnet" "ins_gwlb_az2" {
  vpc_id            = aws_vpc.ins.id
  cidr_block        = var.ins_gwlb_az2
  availability_zone = var.az_2

  tags = {
    Name = "ins-gwlb-az2"
  }
}

resource "aws_subnet" "ins_tgw_az1" {
  vpc_id            = aws_vpc.ins.id
  cidr_block        = var.ins_tgw_az1
  availability_zone = var.az_1

  tags = {
    Name = "ins-tgw-az1"
  }
}

resource "aws_subnet" "ins_tgw_az2" {
  vpc_id            = aws_vpc.ins.id
  cidr_block        = var.ins_tgw_az2
  availability_zone = var.az_2

  tags = {
    Name = "ins-tgw-az2"
  }
}

# Route tables – Inspection (TGW subnets default to GWLBe)
resource "aws_route_table" "ins_tgw_rt_az1" {
  vpc_id = aws_vpc.ins.id

  tags = {
    Name = "rt-ins-tgw-az1"
  }
}

resource "aws_route_table" "ins_tgw_rt_az2" {
  vpc_id = aws_vpc.ins.id

  tags = {
    Name = "rt-ins-tgw-az2"
  }
}

resource "aws_route_table_association" "a_ins_tgw_az1" {
  subnet_id      = aws_subnet.ins_tgw_az1.id
  route_table_id = aws_route_table.ins_tgw_rt_az1.id
}

resource "aws_route_table_association" "a_ins_tgw_az2" {
  subnet_id      = aws_subnet.ins_tgw_az2.id
  route_table_id = aws_route_table.ins_tgw_rt_az2.id
}

############################################
# Security Groups (least-privilege)
############################################

# SSM-only outbound (no inbound) – used for general instances if needed
resource "aws_security_group" "mgmt_default_egress" {
  name        = "mgmt-default-egress"
  description = "No inbound; allow all egress"
  vpc_id      = aws_vpc.mgmt.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sg-mgmt-default-egress"
  }
}

# Bastion must accept SSH from inspection trust (after Palo allows)
resource "aws_security_group" "bastion_sg" {
  name        = "bastion-ssh-from-inspection"
  description = "Allow SSH from Palo trust subnets"
  vpc_id      = aws_vpc.mgmt.id

  ingress {
    description = "SSH from Inspection Trust AZ1"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ins_trust_az1]
  }

  ingress {
    description = "SSH from Inspection Trust AZ2"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ins_trust_az2]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sg-bastion-ssh"
  }
}

# App web must accept HTTP from inspection trust (post-inspection)
resource "aws_security_group" "app_web_sg" {
  name        = "app-web-http-from-inspection"
  description = "Allow HTTP from Palo trust subnets"
  vpc_id      = aws_vpc.app.id

  ingress {
    description = "HTTP from Inspection Trust AZ1"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.ins_trust_az1]
  }

  ingress {
    description = "HTTP from Inspection Trust AZ2"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.ins_trust_az2]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sg-app-web"
  }
}

# Palo Mgmt SG – bastion -> Palo mgmt (HTTPS/SSH) over mgmt subnets
resource "aws_security_group" "palo_mgmt_sg" {
  name        = "palo-mgmt"
  description = "Bastion to Palo mgmt (HTTPS/SSH)"
  vpc_id      = aws_vpc.ins.id

  ingress {
    description     = "HTTPS from bastion SG"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  ingress {
    description     = "SSH from bastion SG"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sg-palo-mgmt"
  }
}

# VPC endpoints SGs – allow 443 from within each VPC CIDR
resource "aws_security_group" "vpce_mgmt" {
  name        = "vpce-mgmt"
  description = "Interface Endpoints allow 443 from VPC"
  vpc_id      = aws_vpc.mgmt.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.mgmt_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sg-vpce-mgmt"
  }
}

resource "aws_security_group" "vpce_app" {
  name        = "vpce-app"
  description = "Interface Endpoints allow 443 from VPC"
  vpc_id      = aws_vpc.app.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.app_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sg-vpce-app"
  }
}

resource "aws_security_group" "vpce_ins" {
  name        = "vpce-ins"
  description = "Interface Endpoints allow 443 from VPC"
  vpc_id      = aws_vpc.ins.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.inspection_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sg-vpce-ins"
  }
}

############################################
# SSM (Interface) Endpoints – Mgmt/App/Inspection
# S3 endpoints and bootstrap buckets OPTIONAL → commented below
############################################

locals {
  ssm_services = [
    "com.amazonaws.${data.aws_region.current.name}.ssm",
    "com.amazonaws.${data.aws_region.current.name}.ssmmessages",
    "com.amazonaws.${data.aws_region.current.name}.ec2messages"
  ]
}

# Mgmt
resource "aws_vpc_endpoint" "mgmt_ssm" {
  for_each            = toset(local.ssm_services)
  vpc_id              = aws_vpc.mgmt.id
  service_name        = each.value
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  security_group_ids  = [aws_security_group.vpce_mgmt.id]
  subnet_ids          = [aws_subnet.mgmt_priv_az1.id, aws_subnet.mgmt_priv_az2.id]

  tags = {
    Name = "mgmt-${replace(each.value, ".", "-")}"
  }
}

# App
resource "aws_vpc_endpoint" "app_ssm" {
  for_each            = toset(local.ssm_services)
  vpc_id              = aws_vpc.app.id
  service_name        = each.value
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  security_group_ids  = [aws_security_group.vpce_app.id]
  subnet_ids          = [aws_subnet.app_priv_az1.id, aws_subnet.app_priv_az2.id]

  tags = {
    Name = "app-${replace(each.value, ".", "-")}"
  }
}

# Inspection
resource "aws_vpc_endpoint" "ins_ssm" {
  for_each            = toset(local.ssm_services)
  vpc_id              = aws_vpc.ins.id
  service_name        = each.value
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  security_group_ids  = [aws_security_group.vpce_ins.id]
  subnet_ids          = [aws_subnet.ins_mgmt_az1.id, aws_subnet.ins_mgmt_az2.id]

  tags = {
    Name = "ins-${replace(each.value, ".", "-")}"
  }
}

# OPTIONAL: S3 gateway endpoints + bootstrap buckets (commented out)
# resource "aws_vpc_endpoint" "mgmt_s3" {
#   vpc_id            = aws_vpc.mgmt.id
#   vpc_endpoint_type = "Gateway"
#   service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
#   route_table_ids   = [aws_route_table.mgmt_priv_rt_az1.id, aws_route_table.mgmt_priv_rt_az2.id]
#   tags = { Name = "mgmt-s3-gateway" }
# }
# resource "aws_vpc_endpoint" "app_s3" {
#   vpc_id            = aws_vpc.app.id
#   vpc_endpoint_type = "Gateway"
#   service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
#   route_table_ids   = [aws_route_table.app_priv_rt_az1.id, aws_route_table.app_priv_rt_az2.id]
#   tags = { Name = "app-s3-gateway" }
# }
# variable "bootstrap_bucket_1" {
#   type    = string
#   default = "cloudgeniussaadv360"
# }
# variable "bootstrap_bucket_2" {
#   type    = string
#   default = "cloudgeniussaadv361"
# }
# resource "aws_s3_bucket" "bootstrap_1" {
#   bucket = var.bootstrap_bucket_1
#   force_destroy = false
#   tags = { Name = var.bootstrap_bucket_1 }
# }
# resource "aws_s3_bucket" "bootstrap_2" {
#   bucket = var.bootstrap_bucket_2
#   force_destroy = false
#   tags = { Name = var.bootstrap_bucket_2 }
# }

############################################
# SSM Bastion (Mgmt VPC) + Demo Web (App VPC)
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
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.bastion_instance_type
  subnet_id                   = aws_subnet.mgmt_priv_az1.id
  iam_instance_profile        = aws_iam_instance_profile.bastion_profile.name
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]
  associate_public_ip_address = false

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = {
    Name = "cg-adv-ssm-bastion"
  }
}

resource "aws_instance" "app_web" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.web_instance_type
  subnet_id              = aws_subnet.app_priv_az1.id
  vpc_security_group_ids = [aws_security_group.app_web_sg.id]

  user_data = <<-EOT
              #!/bin/bash
              dnf -y install nginx
              systemctl enable --now nginx
              echo "<h1>Acme Demo NGINX</h1>" > /usr/share/nginx/html/index.html
              EOT

  tags = {
    Name = "cg-adv-web"
  }
}

############################################
# Transit Gateway (TGW) – Centralized Routing
############################################

resource "aws_ec2_transit_gateway" "tgw" {
  description                     = "cg-adv-tgw"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  vpn_ecmp_support                = "enable"
  dns_support                     = "enable"
  multicast_support               = "disable"

  tags = {
    Name = "cg-adv-tgw"
  }
}

resource "aws_ec2_transit_gateway_route_table" "spoke_rt" {
  transit_gateway_id = aws_ec2_transit_gateway.tgw.id

  tags = {
    Name = "tgw-spoke-rt"
  }
}

resource "aws_ec2_transit_gateway_route_table" "inspect_rt" {
  transit_gateway_id = aws_ec2_transit_gateway.tgw.id

  tags = {
    Name = "tgw-inspect-rt"
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "att_mgmt" {
  subnet_ids             = [aws_subnet.mgmt_tgw_az1.id, aws_subnet.mgmt_tgw_az2.id]
  transit_gateway_id     = aws_ec2_transit_gateway.tgw.id
  vpc_id                 = aws_vpc.mgmt.id
  appliance_mode_support = "disable"
  dns_support            = "enable"
  ipv6_support           = "disable"

  tags = {
    Name = "att-mgmt"
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "att_app" {
  subnet_ids             = [aws_subnet.app_tgw_az1.id, aws_subnet.app_tgw_az2.id]
  transit_gateway_id     = aws_ec2_transit_gateway.tgw.id
  vpc_id                 = aws_vpc.app.id
  appliance_mode_support = "disable"
  dns_support            = "enable"
  ipv6_support           = "disable"

  tags = {
    Name = "att-app"
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "att_ins" {
  subnet_ids             = [aws_subnet.ins_tgw_az1.id, aws_subnet.ins_tgw_az2.id]
  transit_gateway_id     = aws_ec2_transit_gateway.tgw.id
  vpc_id                 = aws_vpc.ins.id
  appliance_mode_support = "enable"
  dns_support            = "enable"
  ipv6_support           = "disable"

  tags = {
    Name = "att-inspection"
  }
}

resource "aws_ec2_transit_gateway_route_table_association" "assoc_mgmt" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.att_mgmt.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke_rt.id
}

resource "aws_ec2_transit_gateway_route_table_association" "assoc_app" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.att_app.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke_rt.id
}

resource "aws_ec2_transit_gateway_route_table_association" "assoc_inspect" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.att_ins.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.inspect_rt.id
}

# Spokes send 0/0 to Inspection (egress control)
resource "aws_ec2_transit_gateway_route" "spoke_default_to_inspect" {
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.att_ins.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke_rt.id
}

# Return paths (Inspection back to spokes)
resource "aws_ec2_transit_gateway_route" "inspect_to_mgmt" {
  destination_cidr_block         = var.mgmt_cidr
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.att_mgmt.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.inspect_rt.id
}

resource "aws_ec2_transit_gateway_route" "inspect_to_app" {
  destination_cidr_block         = var.app_cidr
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.att_app.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.inspect_rt.id
}

# Spoke RTBs: explicit east/west routes via TGW
resource "aws_route" "mgmt_rt_to_app_az1" {
  route_table_id         = aws_route_table.mgmt_priv_rt_az1.id
  destination_cidr_block = var.app_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.tgw.id
}

resource "aws_route" "mgmt_rt_to_app_az2" {
  route_table_id         = aws_route_table.mgmt_priv_rt_az2.id
  destination_cidr_block = var.app_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.tgw.id
}

resource "aws_route" "app_rt_to_mgmt_az1" {
  route_table_id         = aws_route_table.app_priv_rt_az1.id
  destination_cidr_block = var.mgmt_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.tgw.id
}

resource "aws_route" "app_rt_to_mgmt_az2" {
  route_table_id         = aws_route_table.app_priv_rt_az2.id
  destination_cidr_block = var.mgmt_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.tgw.id
}

# Spoke RTBs: default route to TGW (egress → inspection)
resource "aws_route" "mgmt_priv_az1_default_to_tgw" {
  route_table_id         = aws_route_table.mgmt_priv_rt_az1.id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = aws_ec2_transit_gateway.tgw.id
}

resource "aws_route" "mgmt_priv_az2_default_to_tgw" {
  route_table_id         = aws_route_table.mgmt_priv_rt_az2.id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = aws_ec2_transit_gateway.tgw.id
}

resource "aws_route" "app_priv_az1_default_to_tgw" {
  route_table_id         = aws_route_table.app_priv_rt_az1.id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = aws_ec2_transit_gateway.tgw.id
}

resource "aws_route" "app_priv_az2_default_to_tgw" {
  route_table_id         = aws_route_table.app_priv_rt_az2.id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = aws_ec2_transit_gateway.tgw.id
}

############################################
# GWLB in Inspection + Endpoint Service + GWLBe (Inspection TGW subnets)
############################################

resource "aws_lb" "gwlb" {
  name               = "cg-adv-gwlb"
  load_balancer_type = "gateway"

  subnet_mapping {
    subnet_id = aws_subnet.ins_gwlb_az1.id
  }

  subnet_mapping {
    subnet_id = aws_subnet.ins_gwlb_az2.id
  }

  tags = {
    Name = "cg-adv-gwlb"
  }
}

resource "aws_lb_target_group" "gwlb_tg" {
  name        = "cg-adv-gwlb-tg"
  port        = 6081
  protocol    = "GENEVE"
  vpc_id      = aws_vpc.ins.id
  target_type = "ip"

  # Health check port/proto used for NVA dataplane reachability (adjust if desired)
  health_check {
    protocol = "TCP"
    port     = "80"
  }

  tags = {
    Name = "cg-adv-gwlb-tg"
  }
}

resource "aws_lb_listener" "gwlb_listener" {
  load_balancer_arn = aws_lb.gwlb.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gwlb_tg.arn
  }
}

resource "aws_vpc_endpoint_service" "gwlb_svc" {
  acceptance_required        = false
  gateway_load_balancer_arns = [aws_lb.gwlb.arn]

  tags = {
    Name = "cg-adv-gwlb-svc"
  }
}

# GWLBe for TGW interception in Inspection
resource "aws_vpc_endpoint" "ins_gwlbe_az1" {
  vpc_id            = aws_vpc.ins.id
  vpc_endpoint_type = "GatewayLoadBalancer"
  service_name      = aws_vpc_endpoint_service.gwlb_svc.service_name
  subnet_ids        = [aws_subnet.ins_tgw_az1.id]
  depends_on        = [aws_vpc_endpoint_service.gwlb_svc]

  tags = {
    Name = "ins-gwlbe-az1"
  }
}

resource "aws_vpc_endpoint" "ins_gwlbe_az2" {
  vpc_id            = aws_vpc.ins.id
  vpc_endpoint_type = "GatewayLoadBalancer"
  service_name      = aws_vpc_endpoint_service.gwlb_svc.service_name
  subnet_ids        = [aws_subnet.ins_tgw_az2.id]
  depends_on        = [aws_vpc_endpoint_service.gwlb_svc]

  tags = {
    Name = "ins-gwlbe-az2"
  }
}

# Route TGW-subnet defaults to GWLBe (to firewalls)
resource "aws_route" "ins_tgw_az1_to_gwlbe" {
  route_table_id         = aws_route_table.ins_tgw_rt_az1.id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = aws_vpc_endpoint.ins_gwlbe_az1.id
}

resource "aws_route" "ins_tgw_az2_to_gwlbe" {
  route_table_id         = aws_route_table.ins_tgw_rt_az2.id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = aws_vpc_endpoint.ins_gwlbe_az2.id
}

############################################
# Ingress service-chaining (NLB → GWLBe in spokes)
# - HTTP/HTTPS to App web
# - SSH to Mgmt bastion
############################################

# GWLBe endpoints in SPOKE public subnets (pair with public NLBs)
resource "aws_vpc_endpoint" "app_gwlbe_az1" {
  vpc_id            = aws_vpc.app.id
  vpc_endpoint_type = "GatewayLoadBalancer"
  service_name      = aws_vpc_endpoint_service.gwlb_svc.service_name
  subnet_ids        = [aws_subnet.app_pub_az1.id]
  depends_on        = [aws_vpc_endpoint_service.gwlb_svc]

  tags = {
    Name = "app-gwlbe-az1"
  }
}

resource "aws_vpc_endpoint" "app_gwlbe_az2" {
  vpc_id            = aws_vpc.app.id
  vpc_endpoint_type = "GatewayLoadBalancer"
  service_name      = aws_vpc_endpoint_service.gwlb_svc.service_name
  subnet_ids        = [aws_subnet.app_pub_az2.id]
  depends_on        = [aws_vpc_endpoint_service.gwlb_svc]

  tags = {
    Name = "app-gwlbe-az2"
  }
}

resource "aws_vpc_endpoint" "mgmt_gwlbe_az1" {
  vpc_id            = aws_vpc.mgmt.id
  vpc_endpoint_type = "GatewayLoadBalancer"
  service_name      = aws_vpc_endpoint_service.gwlb_svc.service_name
  subnet_ids        = [aws_subnet.mgmt_pub_az1.id]
  depends_on        = [aws_vpc_endpoint_service.gwlb_svc]

  tags = {
    Name = "mgmt-gwlbe-az1"
  }
}

resource "aws_vpc_endpoint" "mgmt_gwlbe_az2" {
  vpc_id            = aws_vpc.mgmt.id
  vpc_endpoint_type = "GatewayLoadBalancer"
  service_name      = aws_vpc_endpoint_service.gwlb_svc.service_name
  subnet_ids        = [aws_subnet.mgmt_pub_az2.id]
  depends_on        = [aws_vpc_endpoint_service.gwlb_svc]

  tags = {
    Name = "mgmt-gwlbe-az2"
  }
}

# Resolve the private IPs of the GWLBe ENIs for NLB target registration
data "aws_network_interface" "app_gwlbe_eni_az1" {
  id = aws_vpc_endpoint.app_gwlbe_az1.network_interface_ids[0]
}

data "aws_network_interface" "app_gwlbe_eni_az2" {
  id = aws_vpc_endpoint.app_gwlbe_az2.network_interface_ids[0]
}

data "aws_network_interface" "mgmt_gwlbe_eni_az1" {
  id = aws_vpc_endpoint.mgmt_gwlbe_az1.network_interface_ids[0]
}

data "aws_network_interface" "mgmt_gwlbe_eni_az2" {
  id = aws_vpc_endpoint.mgmt_gwlbe_az2.network_interface_ids[0]
}

# --- App Ingress NLB (80/443) → GWLBe (App VPC) ---
resource "aws_lb" "app_ingress_nlb" {
  name               = "app-ingress-nlb"
  load_balancer_type = "network"
  internal           = false
  subnets            = [aws_subnet.app_pub_az1.id, aws_subnet.app_pub_az2.id]

  tags = {
    Name = "app-ingress-nlb"
  }
}

resource "aws_lb_target_group" "app_ingress_tg" {
  name        = "app-ingress-gwlbe-tg"
  port        = 6081
  protocol    = "TCP"
  vpc_id      = aws_vpc.app.id
  target_type = "ip"

  health_check {
    protocol = "TCP"
    port     = "6081"
  }

  tags = {
    Name = "app-ingress-gwlbe-tg"
  }
}

resource "aws_lb_listener" "app_ingress_http" {
  load_balancer_arn = aws_lb.app_ingress_nlb.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_ingress_tg.arn
  }
}

resource "aws_lb_listener" "app_ingress_https" {
  load_balancer_arn = aws_lb.app_ingress_nlb.arn
  port              = 443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_ingress_tg.arn
  }
}

resource "aws_lb_target_group_attachment" "app_gwlbe_target_az1" {
  target_group_arn = aws_lb_target_group.app_ingress_tg.arn
  target_id        = data.aws_network_interface.app_gwlbe_eni_az1.private_ip
  port             = 6081
}

resource "aws_lb_target_group_attachment" "app_gwlbe_target_az2" {
  target_group_arn = aws_lb_target_group.app_ingress_tg.arn
  target_id        = data.aws_network_interface.app_gwlbe_eni_az2.private_ip
  port             = 6081
}

# --- Mgmt SSH Ingress NLB (22) → GWLBe (Mgmt VPC) ---
resource "aws_lb" "mgmt_ssh_nlb" {
  name               = "mgmt-ssh-nlb"
  load_balancer_type = "network"
  internal           = false
  subnets            = [aws_subnet.mgmt_pub_az1.id, aws_subnet.mgmt_pub_az2.id]

  tags = {
    Name = "mgmt-ssh-nlb"
  }
}

resource "aws_lb_target_group" "mgmt_ssh_tg" {
  name        = "mgmt-ssh-gwlbe-tg"
  port        = 6081
  protocol    = "TCP"
  vpc_id      = aws_vpc.mgmt.id
  target_type = "ip"

  health_check {
    protocol = "TCP"
    port     = "6081"
  }

  tags = {
    Name = "mgmt-ssh-gwlbe-tg"
  }
}

resource "aws_lb_listener" "mgmt_ssh_listener" {
  load_balancer_arn = aws_lb.mgmt_ssh_nlb.arn
  port              = 22
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.mgmt_ssh_tg.arn
  }
}

resource "aws_lb_target_group_attachment" "mgmt_gwlbe_target_az1" {
  target_group_arn = aws_lb_target_group.mgmt_ssh_tg.arn
  target_id        = data.aws_network_interface.mgmt_gwlbe_eni_az1.private_ip
  port             = 6081
}

resource "aws_lb_target_group_attachment" "mgmt_gwlbe_target_az2" {
  target_group_arn = aws_lb_target_group.mgmt_ssh_tg.arn
  target_id        = data.aws_network_interface.mgmt_gwlbe_eni_az2.private_ip
  port             = 6081
}

############################################
# Register Palo dataplane IPs (manual step after deploy)
############################################
# resource "aws_lb_target_group_attachment" "pan_az1" {
#   target_group_arn = aws_lb_target_group.gwlb_tg.arn
#   target_id        = "10.30.11.10"  # Palo trust ENI in AZ1
#   port             = 6081
# }
# resource "aws_lb_target_group_attachment" "pan_az2" {
#   target_group_arn = aws_lb_target_group.gwlb_tg.arn
#   target_id        = "10.30.12.10"  # Palo trust ENI in AZ2
#   port             = 6081
# }

############################################
# Outputs
############################################

output "tgw_id" {
  value = aws_ec2_transit_gateway.tgw.id
}

output "tgw_spoke_rt_id" {
  value = aws_ec2_transit_gateway_route_table.spoke_rt.id
}

output "tgw_inspect_rt_id" {
  value = aws_ec2_transit_gateway_route_table.inspect_rt.id
}

output "attachments" {
  value = {
    mgmt = aws_ec2_transit_gateway_vpc_attachment.att_mgmt.id
    app  = aws_ec2_transit_gateway_vpc_attachment.att_app.id
    ins  = aws_ec2_transit_gateway_vpc_attachment.att_ins.id
  }
}

output "gwlb" {
  value = {
    arn      = aws_lb.gwlb.arn
    tg_arn   = aws_lb_target_group.gwlb_tg.arn
    svc_name = aws_vpc_endpoint_service.gwlb_svc.service_name
  }
}

output "inspection_gwlbe_ids" {
  value = [
    aws_vpc_endpoint.ins_gwlbe_az1.id,
    aws_vpc_endpoint.ins_gwlbe_az2.id
  ]
}

output "spoke_gwlbe_ids" {
  value = {
    app  = [aws_vpc_endpoint.app_gwlbe_az1.id, aws_vpc_endpoint.app_gwlbe_az2.id]
    mgmt = [aws_vpc_endpoint.mgmt_gwlbe_az1.id, aws_vpc_endpoint.mgmt_gwlbe_az2.id]
  }
}

output "nlb_dns" {
  value = {
    app_ingress = aws_lb.app_ingress_nlb.dns_name
    mgmt_ssh    = aws_lb.mgmt_ssh_nlb.dns_name
  }
}

output "instances" {
  value = {
    bastion = aws_instance.ssm_bastion.id
    web     = aws_instance.app_web.id
  }
}
