############################################
# cg-adv — Phase 1 (HA-Ready): Base Network & Security
# - SSM-only mgmt (no public ingress)
# - IGW + NAT GW per AZ (egress only)
# - GWLB across 2 AZs + optional GWLBe routing (feature-flag)
# - Palo mgmt SG (bastion -> 443/22)
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
# Variables
############################################

variable "aws_region" {
  type        = string
  description = "AWS region for all resources"
  default     = "us-west-2"
}

variable "az_1" {
  type        = string
  description = "Primary AZ"
  default     = "us-west-2a"
}

variable "az_2" {
  type        = string
  description = "Secondary AZ"
  default     = "us-west-2b"
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

# Private subnets (per AZ)
variable "mgmt_cidr_az1" {
  type    = string
  default = "10.20.1.0/24"
}

variable "mgmt_cidr_az2" {
  type    = string
  default = "10.20.2.0/24"
}

variable "trust_cidr_az1" {
  type    = string
  default = "10.20.11.0/24"
}

variable "trust_cidr_az2" {
  type    = string
  default = "10.20.12.0/24"
}

variable "untrust_cidr_az1" {
  type    = string
  default = "10.20.21.0/24"
}

variable "untrust_cidr_az2" {
  type    = string
  default = "10.20.22.0/24"
}

# GWLB subnets (per AZ)
variable "gwlb_cidr_az1" {
  type    = string
  default = "10.20.31.0/24"
}

variable "gwlb_cidr_az2" {
  type    = string
  default = "10.20.32.0/24"
}

# Public subnets for NAT (one per AZ)
variable "public_cidr_az1" {
  type    = string
  default = "10.20.101.0/24"
}

variable "public_cidr_az2" {
  type    = string
  default = "10.20.102.0/24"
}

# Flag to steer trust/untrust traffic through GWLBe once Palo is ready
variable "enable_gwlb_routing" {
  type        = bool
  default     = false
  description = "If true, route trust/untrust via GWLBe. Keep false until Palo targets are registered and healthy."
}

variable "bastion_instance_type" {
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

############################################
# VPC + IGW + Subnets (2 AZs)
############################################

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "cg-adv-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "cg-adv-igw"
  }
}

# Public subnets (for NAT GW)
resource "aws_subnet" "public_az1" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_cidr_az1
  availability_zone       = var.az_1
  map_public_ip_on_launch = true

  tags = {
    Name = "public-az1"
  }
}

resource "aws_subnet" "public_az2" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_cidr_az2
  availability_zone       = var.az_2
  map_public_ip_on_launch = true

  tags = {
    Name = "public-az2"
  }
}

# Private subnets
resource "aws_subnet" "mgmt_az1" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.mgmt_cidr_az1
  availability_zone       = var.az_1
  map_public_ip_on_launch = false

  tags = {
    Name = "mgmt-az1"
  }
}

resource "aws_subnet" "mgmt_az2" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.mgmt_cidr_az2
  availability_zone       = var.az_2
  map_public_ip_on_launch = false

  tags = {
    Name = "mgmt-az2"
  }
}

resource "aws_subnet" "trust_az1" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.trust_cidr_az1
  availability_zone = var.az_1

  tags = {
    Name = "trust-az1"
  }
}

resource "aws_subnet" "trust_az2" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.trust_cidr_az2
  availability_zone = var.az_2

  tags = {
    Name = "trust-az2"
  }
}

resource "aws_subnet" "untrust_az1" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.untrust_cidr_az1
  availability_zone = var.az_1

  tags = {
    Name = "untrust-az1"
  }
}

resource "aws_subnet" "untrust_az2" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.untrust_cidr_az2
  availability_zone = var.az_2

  tags = {
    Name = "untrust-az2"
  }
}

# GWLB subnets
resource "aws_subnet" "gwlb_az1" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.gwlb_cidr_az1
  availability_zone = var.az_1

  tags = {
    Name = "gwlb-az1"
  }
}

resource "aws_subnet" "gwlb_az2" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.gwlb_cidr_az2
  availability_zone = var.az_2

  tags = {
    Name = "gwlb-az2"
  }
}

############################################
# NAT Gateways (per AZ) + EIPs
############################################

resource "aws_eip" "nat_eip_az1" {
  domain = "vpc"

  tags = {
    Name = "cg-adv-nat-eip-az1"
  }
}

resource "aws_eip" "nat_eip_az2" {
  domain = "vpc"

  tags = {
    Name = "cg-adv-nat-eip-az2"
  }
}

resource "aws_nat_gateway" "nat_az1" {
  allocation_id = aws_eip.nat_eip_az1.id
  subnet_id     = aws_subnet.public_az1.id
  depends_on    = [aws_internet_gateway.igw]

  tags = {
    Name = "cg-adv-nat-az1"
  }
}

resource "aws_nat_gateway" "nat_az2" {
  allocation_id = aws_eip.nat_eip_az2.id
  subnet_id     = aws_subnet.public_az2.id
  depends_on    = [aws_internet_gateway.igw]

  tags = {
    Name = "cg-adv-nat-az2"
  }
}

############################################
# Route Tables
############################################

# Public RTBs -> IGW
resource "aws_route_table" "rtb_public_az1" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "rtb-public-az1"
  }
}

resource "aws_route" "public_az1_default" {
  route_table_id         = aws_route_table.rtb_public_az1.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "rta_public_az1" {
  subnet_id      = aws_subnet.public_az1.id
  route_table_id = aws_route_table.rtb_public_az1.id
}

resource "aws_route_table" "rtb_public_az2" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "rtb-public-az2"
  }
}

resource "aws_route" "public_az2_default" {
  route_table_id         = aws_route_table.rtb_public_az2.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "rta_public_az2" {
  subnet_id      = aws_subnet.public_az2.id
  route_table_id = aws_route_table.rtb_public_az2.id
}

# Private RTBs (egress -> NAT)
resource "aws_route_table" "rtb_mgmt_az1" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "rtb-mgmt-az1"
  }
}

resource "aws_route" "rt_mgmt_az1_default" {
  route_table_id         = aws_route_table.rtb_mgmt_az1.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_az1.id
}

resource "aws_route_table_association" "rta_mgmt_az1" {
  subnet_id      = aws_subnet.mgmt_az1.id
  route_table_id = aws_route_table.rtb_mgmt_az1.id
}

resource "aws_route_table" "rtb_mgmt_az2" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "rtb-mgmt-az2"
  }
}

resource "aws_route" "rt_mgmt_az2_default" {
  route_table_id         = aws_route_table.rtb_mgmt_az2.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_az2.id
}

resource "aws_route_table_association" "rta_mgmt_az2" {
  subnet_id      = aws_subnet.mgmt_az2.id
  route_table_id = aws_route_table.rtb_mgmt_az2.id
}

resource "aws_route_table" "rtb_trust_az1" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "rtb-trust-az1"
  }
}

resource "aws_route_table_association" "rta_trust_az1" {
  subnet_id      = aws_subnet.trust_az1.id
  route_table_id = aws_route_table.rtb_trust_az1.id
}

resource "aws_route_table" "rtb_trust_az2" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "rtb-trust-az2"
  }
}

resource "aws_route_table_association" "rta_trust_az2" {
  subnet_id      = aws_subnet.trust_az2.id
  route_table_id = aws_route_table.rtb_trust_az2.id
}

resource "aws_route_table" "rtb_untrust_az1" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "rtb-untrust-az1"
  }
}

resource "aws_route_table_association" "rta_untrust_az1" {
  subnet_id      = aws_subnet.untrust_az1.id
  route_table_id = aws_route_table.rtb_untrust_az1.id
}

resource "aws_route_table" "rtb_untrust_az2" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "rtb-untrust-az2"
  }
}

resource "aws_route_table_association" "rta_untrust_az2" {
  subnet_id      = aws_subnet.untrust_az2.id
  route_table_id = aws_route_table.rtb_untrust_az2.id
}

# GWLB RTBs (kept empty)
resource "aws_route_table" "rtb_gwlb_az1" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "rtb-gwlb-az1"
  }
}

resource "aws_route_table_association" "rta_gwlb_az1" {
  subnet_id      = aws_subnet.gwlb_az1.id
  route_table_id = aws_route_table.rtb_gwlb_az1.id
}

resource "aws_route_table" "rtb_gwlb_az2" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "rtb-gwlb-az2"
  }
}

resource "aws_route_table_association" "rta_gwlb_az2" {
  subnet_id      = aws_subnet.gwlb_az2.id
  route_table_id = aws_route_table.rtb_gwlb_az2.id
}

############################################
# Security Groups
############################################

# SSM-only mgmt SG (no inbound)
resource "aws_security_group" "mgmt_sg" {
  name        = "adv-mgmt"
  description = "No inbound (SSM-only)"
  vpc_id      = aws_vpc.this.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sg-mgmt"
  }
}

# VPC endpoints SG (allow 443 from VPC)
resource "aws_security_group" "endpoints_sg" {
  name        = "adv-vpce"
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

  tags = {
    Name = "sg-vpce"
  }
}

# Default-deny for data-plane (no inbound)
resource "aws_security_group" "default_deny" {
  name        = "adv-default-deny"
  description = "Deny inbound, allow outbound"
  vpc_id      = aws_vpc.this.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sg-default-deny"
  }
}

# Palo mgmt SG — allows bastion -> Palo mgmt (HTTPS/SSH)
resource "aws_security_group" "fw_mgmt_sg" {
  name        = "adv-fw-mgmt"
  description = "Allow bastion to Palo mgmt (HTTPS/SSH)"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "HTTPS from bastion"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.mgmt_sg.id]
  }

  ingress {
    description     = "SSH from bastion (optional)"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.mgmt_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "fw-mgmt-sg"
  }
}

# (Optional) FW HA SG for peer sync (self-reference)
resource "aws_security_group" "fw_ha_sg" {
  name        = "adv-fw-ha"
  description = "FW-to-FW HA/control sync only"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
    description = "FW peer traffic"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "fw-ha-sg"
  }
}

############################################
# Interface Endpoints (SSM) in BOTH AZs
############################################

data "aws_region" "current" {}

locals {
  ssm_services = [
    "com.amazonaws.${data.aws_region.current.name}.ssm",
    "com.amazonaws.${data.aws_region.current.name}.ssmmessages",
    "com.amazonaws.${data.aws_region.current.name}.ec2messages"
  ]

  gwlb_subnet_ids = [
    aws_subnet.gwlb_az1.id,
    aws_subnet.gwlb_az2.id
  ]
}

resource "aws_vpc_endpoint" "ssm_ifaces" {
  for_each            = toset(local.ssm_services)
  vpc_id              = aws_vpc.this.id
  service_name        = each.value
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  security_group_ids  = [aws_security_group.endpoints_sg.id]
  subnet_ids          = [aws_subnet.mgmt_az1.id, aws_subnet.mgmt_az2.id]

  tags = {
    Name = "vpce-${replace(each.value, ".", "-")}"
  }
}

# S3 Gateway endpoint for private bootstrap/artifacts (all private RTBs)
resource "aws_vpc_endpoint" "s3_gateway" {
  vpc_id            = aws_vpc.this.id
  vpc_endpoint_type = "Gateway"
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  route_table_ids   = [
    aws_route_table.rtb_mgmt_az1.id,
    aws_route_table.rtb_mgmt_az2.id,
    aws_route_table.rtb_trust_az1.id,
    aws_route_table.rtb_trust_az2.id,
    aws_route_table.rtb_untrust_az1.id,
    aws_route_table.rtb_untrust_az2.id
  ]

  tags = {
    Name = "vpce-s3-gateway"
  }
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
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.bastion_instance_type
  subnet_id                   = aws_subnet.mgmt_az1.id
  iam_instance_profile        = aws_iam_instance_profile.bastion_profile.name
  vpc_security_group_ids      = [aws_security_group.mgmt_sg.id]
  associate_public_ip_address = false

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = {
    Name = "cg-adv-ssm-bastion"
  }
}

############################################
# VPC Flow Logs → CloudWatch (basic; can KMS in Phase-2)
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

  tags = {
    Name = "cg-adv-vpc-flow-logs"
  }
}

############################################
# GWLB (2 AZs) + TG + Listener (no targets yet)
############################################

resource "aws_lb" "gwlb" {
  name               = "cg-adv-gwlb"
  load_balancer_type = "gateway"

  dynamic "subnet_mapping" {
    for_each = toset(local.gwlb_subnet_ids)
    content {
      subnet_id = subnet_mapping.value
    }
  }

  tags = {
    Name = "cg-adv-gwlb"
  }
}

resource "aws_lb_target_group" "gwlb_tg" {
  name        = "cg-adv-gwlb-tg"
  port        = 6081
  protocol    = "GENEVE"
  vpc_id      = aws_vpc.this.id
  target_type = "ip"

  # Update to a port Palo will accept on the data plane when you register targets (e.g., TCP 443)
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

############################################
# GWLB Endpoints (GWLBe) in trust/untrust (both AZs)
# Routing to these endpoints is gated by enable_gwlb_routing (default false)
############################################

resource "aws_vpc_endpoint" "gwlbe_trust_az1" {
  vpc_id            = aws_vpc.this.id
  service_name      = aws_lb.gwlb.arn
  vpc_endpoint_type = "GatewayLoadBalancer"
  subnet_ids        = [aws_subnet.trust_az1.id]

  tags = {
    Name = "gwlbe-trust-az1"
  }
}

resource "aws_vpc_endpoint" "gwlbe_trust_az2" {
  vpc_id            = aws_vpc.this.id
  service_name      = aws_lb.gwlb.arn
  vpc_endpoint_type = "GatewayLoadBalancer"
  subnet_ids        = [aws_subnet.trust_az2.id]

  tags = {
    Name = "gwlbe-trust-az2"
  }
}

resource "aws_vpc_endpoint" "gwlbe_untrust_az1" {
  vpc_id            = aws_vpc.this.id
  service_name      = aws_lb.gwlb.arn
  vpc_endpoint_type = "GatewayLoadBalancer"
  subnet_ids        = [aws_subnet.untrust_az1.id]

  tags = {
    Name = "gwlbe-untrust-az1"
  }
}

resource "aws_vpc_endpoint" "gwlbe_untrust_az2" {
  vpc_id            = aws_vpc.this.id
  service_name      = aws_lb.gwlb.arn
  vpc_endpoint_type = "GatewayLoadBalancer"
  subnet_ids        = [aws_subnet.untrust_az2.id]

  tags = {
    Name = "gwlbe-untrust-az2"
  }
}

# Conditionally steer trust/untrust via GWLBe (SAFE: off by default)
resource "aws_route" "rt_trust_az1_gwlbe" {
  count                  = var.enable_gwlb_routing ? 1 : 0
  route_table_id         = aws_route_table.rtb_trust_az1.id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = aws_vpc_endpoint.gwlbe_trust_az1.id
}

resource "aws_route" "rt_trust_az2_gwlbe" {
  count                  = var.enable_gwlb_routing ? 1 : 0
  route_table_id         = aws_route_table.rtb_trust_az2.id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = aws_vpc_endpoint.gwlbe_trust_az2.id
}

resource "aws_route" "rt_untrust_az1_gwlbe" {
  count                  = var.enable_gwlb_routing ? 1 : 0
  route_table_id         = aws_route_table.rtb_untrust_az1.id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = aws_vpc_endpoint.gwlbe_untrust_az1.id
}

resource "aws_route" "rt_untrust_az2_gwlbe" {
  count                  = var.enable_gwlb_routing ? 1 : 0
  route_table_id         = aws_route_table.rtb_untrust_az2.id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = aws_vpc_endpoint.gwlbe_untrust_az2.id
}

############################################
# Outputs (handy for next steps)
############################################

output "ssm_bastion_instance_id" {
  value = aws_instance.ssm_bastion.id
}

output "gwlb_arn" {
  value = aws_lb.gwlb.arn
}

output "gwlb_target_group_arn" {
  value = aws_lb_target_group.gwlb_tg.arn
}

output "fw_mgmt_sg_id" {
  value = aws_security_group.fw_mgmt_sg.id
}

output "subnets_mgmt" {
  value = [aws_subnet.mgmt_az1.id, aws_subnet.mgmt_az2.id]
}

output "subnets_trust" {
  value = [aws_subnet.trust_az1.id, aws_subnet.trust_az2.id]
}

output "subnets_untrust" {
  value = [aws_subnet.untrust_az1.id, aws_subnet.untrust_az2.id]
}

output "subnets_gwlb" {
  value = [aws_subnet.gwlb_az1.id, aws_subnet.gwlb_az2.id]
}
