############################################
# Advantus360 – Centralized Inspection POC
# TGW + GWLB + 3 VPCs (Mgmt / App / Inspection)
# - Meets POC asks: HA, VPC-to-VPC (east/west) via Palo, egress control
# - Ready for manual Palo Alto VM-Series deploy in Inspection VPC
# - Ingress service-chaining (Internet -> NLB -> GWLB) can be added as Phase 2
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
# Variables (multi-line, one argument per line)
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

# Mgmt subnets
variable "mgmt_priv_az1" {
  type    = string
  default = "10.10.1.0/24"
}

variable "mgmt_priv_az2" {
  type    = string
  default = "10.10.2.0/24"
}

# Attach subnets for TGW in Mgmt VPC
variable "mgmt_tgw_az1" {
  type    = string
  default = "10.10.10.0/24"
}

variable "mgmt_tgw_az2" {
  type    = string
  default = "10.10.11.0/24"
}

# App subnets
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

# Attach subnets for TGW in App VPC
variable "app_tgw_az1" {
  type    = string
  default = "10.20.10.0/24"
}

variable "app_tgw_az2" {
  type    = string
  default = "10.20.11.0/24"
}

# Inspection subnets
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

# GWLB subnets
variable "ins_gwlb_az1" {
  type    = string
  default = "10.30.31.0/24"
}

variable "ins_gwlb_az2" {
  type    = string
  default = "10.30.32.0/24"
}

# Attach subnets for TGW in Inspection VPC (used to intercept via GWLBe)
variable "ins_tgw_az1" {
  type    = string
  default = "10.30.41.0/24"
}

variable "ins_tgw_az2" {
  type    = string
  default = "10.30.42.0/24"
}

# Feature flags
variable "enable_phase2_ingress_chain" {
  description = "Future: Internet ingress chaining (NLB -> GWLB). Keep false for Phase 1."
  type        = bool
  default     = false
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

resource "aws_eip" "mgmt_nat_eip_az1" {
  domain = "vpc"

  tags = {
    Name = "mgmt-nat-eip-az1"
  }
}

resource "aws_eip" "mgmt_nat_eip_az2" {
  domain = "vpc"

  tags = {
    Name = "mgmt-nat-eip-az2"
  }
}

resource "aws_nat_gateway" "mgmt_nat_az1" {
  allocation_id = aws_eip.mgmt_nat_eip_az1.id
  subnet_id     = aws_subnet.mgmt_tgw_az1.id
  depends_on    = [aws_internet_gateway.mgmt_igw]

  tags = {
    Name = "mgmt-nat-az1"
  }
}

resource "aws_nat_gateway" "mgmt_nat_az2" {
  allocation_id = aws_eip.mgmt_nat_eip_az2.id
  subnet_id     = aws_subnet.mgmt_tgw_az2.id
  depends_on    = [aws_internet_gateway.mgmt_igw]

  tags = {
    Name = "mgmt-nat-az2"
  }
}

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

resource "aws_route_table_association" "a_mgmt_priv_az1" {
  subnet_id      = aws_subnet.mgmt_priv_az1.id
  route_table_id = aws_route_table.mgmt_priv_rt_az1.id
}

resource "aws_route_table_association" "a_mgmt_priv_az2" {
  subnet_id      = aws_subnet.mgmt_priv_az2.id
  route_table_id = aws_route_table.mgmt_priv_rt_az2.id
}

resource "aws_route" "mgmt_priv_az1_egress" {
  route_table_id         = aws_route_table.mgmt_priv_rt_az1.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.mgmt_nat_az1.id
}

resource "aws_route" "mgmt_priv_az2_egress" {
  route_table_id         = aws_route_table.mgmt_priv_rt_az2.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.mgmt_nat_az2.id
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

resource "aws_eip" "app_nat_eip_az1" {
  domain = "vpc"

  tags = {
    Name = "app-nat-eip-az1"
  }
}

resource "aws_eip" "app_nat_eip_az2" {
  domain = "vpc"

  tags = {
    Name = "app-nat-eip-az2"
  }
}

resource "aws_nat_gateway" "app_nat_az1" {
  allocation_id = aws_eip.app_nat_eip_az1.id
  subnet_id     = aws_subnet.app_pub_az1.id
  depends_on    = [aws_internet_gateway.app_igw]

  tags = {
    Name = "app-nat-az1"
  }
}

resource "aws_nat_gateway" "app_nat_az2" {
  allocation_id = aws_eip.app_nat_eip_az2.id
  subnet_id     = aws_subnet.app_pub_az2.id
  depends_on    = [aws_internet_gateway.app_igw]

  tags = {
    Name = "app-nat-az2"
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

resource "aws_route" "app_priv_az1_nat" {
  route_table_id         = aws_route_table.app_priv_rt_az1.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.app_nat_az1.id
}

resource "aws_route" "app_priv_az2_nat" {
  route_table_id         = aws_route_table.app_priv_rt_az2.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.app_nat_az2.id
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

resource "aws_route_table" "ins_mgmt_rt_az1" {
  vpc_id = aws_vpc.ins.id

  tags = {
    Name = "rt-ins-mgmt-az1"
  }
}

resource "aws_route_table" "ins_mgmt_rt_az2" {
  vpc_id = aws_vpc.ins.id

  tags = {
    Name = "rt-ins-mgmt-az2"
  }
}

resource "aws_route_table_association" "a_ins_mgmt_az1" {
  subnet_id      = aws_subnet.ins_mgmt_az1.id
  route_table_id = aws_route_table.ins_mgmt_rt_az1.id
}

resource "aws_route_table_association" "a_ins_mgmt_az2" {
  subnet_id      = aws_subnet.ins_mgmt_az2.id
  route_table_id = aws_route_table.ins_mgmt_rt_az2.id
}

############################################
# Security Groups
############################################

resource "aws_security_group" "mgmt_default" {
  name        = "mgmt-default"
  description = "SSM-only outbound"
  vpc_id      = aws_vpc.mgmt.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sg-mgmt-default"
  }
}

resource "aws_security_group" "palo_mgmt_sg" {
  name        = "palo-mgmt"
  description = "Bastion -> Palo mgmt HTTPS/SSH"
  vpc_id      = aws_vpc.ins.id

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.mgmt_default.id]
  }

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.mgmt_default.id]
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

resource "aws_security_group" "vpce_mgmt" {
  name   = "vpce-mgmt"
  vpc_id = aws_vpc.mgmt.id

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
}

resource "aws_security_group" "vpce_app" {
  name   = "vpce-app"
  vpc_id = aws_vpc.app.id

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
}

resource "aws_security_group" "vpce_ins" {
  name   = "vpce-ins"
  vpc_id = aws_vpc.ins.id

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
}

############################################
# SSM (Interface) + S3 (Gateway) Endpoints – Mgmt/App/Inspection
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

resource "aws_vpc_endpoint" "mgmt_s3" {
  vpc_id            = aws_vpc.mgmt.id
  vpc_endpoint_type = "Gateway"
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  route_table_ids   = [aws_route_table.mgmt_priv_rt_az1.id, aws_route_table.mgmt_priv_rt_az2.id]

  tags = {
    Name = "mgmt-s3-gateway"
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

resource "aws_vpc_endpoint" "app_s3" {
  vpc_id            = aws_vpc.app.id
  vpc_endpoint_type = "Gateway"
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  route_table_ids   = [aws_route_table.app_priv_rt_az1.id, aws_route_table.app_priv_rt_az2.id]

  tags = {
    Name = "app-s3-gateway"
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
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.bastion_instance_type
  subnet_id              = aws_subnet.mgmt_priv_az1.id
  iam_instance_profile   = aws_iam_instance_profile.bastion_profile.name
  vpc_security_group_ids = [aws_security_group.mgmt_default.id]
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
  ami               = data.aws_ami.al2023.id
  instance_type     = var.web_instance_type
  subnet_id         = aws_subnet.app_priv_az1.id
  vpc_security_group_ids = [aws_security_group.vpce_app.id]

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
  subnet_ids                = [aws_subnet.mgmt_tgw_az1.id, aws_subnet.mgmt_tgw_az2.id]
  transit_gateway_id        = aws_ec2_transit_gateway.tgw.id
  vpc_id                    = aws_vpc.mgmt.id
  appliance_mode_support    = "disable"
  dns_support               = "enable"
  ipv6_support              = "disable"

  tags = {
    Name = "att-mgmt"
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "att_app" {
  subnet_ids                = [aws_subnet.app_tgw_az1.id, aws_subnet.app_tgw_az2.id]
  transit_gateway_id        = aws_ec2_transit_gateway.tgw.id
  vpc_id                    = aws_vpc.app.id
  appliance_mode_support    = "disable"
  dns_support               = "enable"
  ipv6_support              = "disable"

  tags = {
    Name = "att-app"
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "att_ins" {
  subnet_ids                = [aws_subnet.ins_tgw_az1.id, aws_subnet.ins_tgw_az2.id]
  transit_gateway_id        = aws_ec2_transit_gateway.tgw.id
  vpc_id                    = aws_vpc.ins.id
  appliance_mode_support    = "enable" # REQUIRED for inspection VPC
  dns_support               = "enable"
  ipv6_support              = "disable"

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

resource "aws_ec2_transit_gateway_route" "spoke_default_to_inspect" {
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.att_ins.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke_rt.id
}

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

############################################
# GWLB in Inspection VPC + Endpoint Service
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
# Register Palo dataplane IPs (manual step)
############################################
# Example (uncomment and fill when ready):
# resource "aws_lb_target_group_attachment" "pan_az1" {
#   target_group_arn = aws_lb_target_group.gwlb_tg.arn
#   target_id        = "10.30.11.10" # Palo trust ENI AZ1
# }
# resource "aws_lb_target_group_attachment" "pan_az2" {
#   target_group_arn = aws_lb_target_group.gwlb_tg.arn
#   target_id        = "10.30.12.10" # Palo trust ENI AZ2
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

output "att_mgmt_id" {
  value = aws_ec2_transit_gateway_vpc_attachment.att_mgmt.id
}

output "att_app_id" {
  value = aws_ec2_transit_gateway_vpc_attachment.att_app.id
}

output "att_inspection_id" {
  value = aws_ec2_transit_gateway_vpc_attachment.att_ins.id
}

output "inspection_gwlb_arn" {
  value = aws_lb.gwlb.arn
}

output "inspection_gwlb_tg_arn" {
  value = aws_lb_target_group.gwlb_tg.arn
}

output "inspection_gwlbe_ids" {
  value = [
    aws_vpc_endpoint.ins_gwlbe_az1.id,
    aws_vpc_endpoint.ins_gwlbe_az2.id
  ]
}

output "mgmt_bastion_instance_id" {
  value = aws_instance.ssm_bastion.id
}

output "app_web_instance_id" {
  value = aws_instance.app_web.id
}

output "palo_mgmt_sg_id" {
  value = aws_security_group.palo_mgmt_sg.id
}

output "inspection_subnets" {
  value = {
    mgmt   = [aws_subnet.ins_mgmt_az1.id, aws_subnet.ins_mgmt_az2.id]
    trust  = [aws_subnet.ins_trust_az1.id, aws_subnet.ins_trust_az2.id]
    untrust = [aws_subnet.ins_untr_az1.id, aws_subnet.ins_untr_az2.id]
    gwlb   = [aws_subnet.ins_gwlb_az1.id, aws_subnet.ins_gwlb_az2.id]
    tgw    = [aws_subnet.ins_tgw_az1.id, aws_subnet.ins_tgw_az2.id]
  }
}
