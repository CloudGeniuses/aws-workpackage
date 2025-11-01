############################################
# Terraform Cloud + Provider (us-west-2)
############################################
terraform {
  required_version = ">= 1.6.0, < 2.0.0"

  cloud {
    organization = "YOUR_TFC_ORG"
  # ──> Create workspace named "advantus360-acme-palo-poc" in TFC
    workspaces {
      name = "advantus360-acme-palo-poc"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

provider "aws" {
  region = "us-west-2"

  default_tags {
    tags = {
      Project     = "Acme-Palo-POC"
      Owner       = "Advantus360-CloudGenius"
      Environment = "poc"
    }
  }
}

############################################
# Variables (you will fill after PAN is launched)
############################################
variable "pan_dataplane_ips" {
  description = "PAN dataplane IPs to register in the GWLB target group (trust-side dataplane IPs that terminate GENEVE)."
  type        = list(string)
  default     = []   # e.g., ["10.10.21.10","10.10.22.10"]
}

variable "pan_untrust_ips" {
  description = "PAN Untrust ENI private IPs to register behind the edge NLB (ingress demo, TCP/80/443/22)."
  type        = list(string)
  default     = []   # e.g., ["10.10.11.10","10.10.12.10"]
}

############################################
# Locals (AZs, CIDRs)
############################################
locals {
  az1 = "us-west-2a"
  az2 = "us-west-2b"

  cidr = {
    inspection = "10.10.0.0/16"
    mgmt       = "10.20.0.0/16"
    app        = "10.30.0.0/16"

    ins_mgmt_az1    = "10.10.1.0/24"
    ins_mgmt_az2    = "10.10.2.0/24"
    ins_untrust_az1 = "10.10.11.0/24"
    ins_untrust_az2 = "10.10.12.0/24"
    ins_trust_az1   = "10.10.21.0/24"
    ins_trust_az2   = "10.10.22.0/24"
    ins_tgwatt_az1  = "10.10.31.0/24"
    ins_tgwatt_az2  = "10.10.32.0/24"

    mgmt_az1 = "10.20.11.0/24"
    mgmt_az2 = "10.20.12.0/24"
    app_az1  = "10.30.11.0/24"
    app_az2  = "10.30.12.0/24"
  }
}

############################################
# VPCs
############################################
resource "aws_vpc" "inspection" {
  cidr_block           = local.cidr.inspection
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "vpc-inspection" }
}

resource "aws_vpc" "mgmt" {
  cidr_block           = local.cidr.mgmt
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "vpc-mgmt" }
}

resource "aws_vpc" "app" {
  cidr_block           = local.cidr.app
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "vpc-app" }
}

############################################
# Subnets - Inspection VPC
############################################
# Mgmt
resource "aws_subnet" "ins_mgmt_az1" {
  vpc_id                  = aws_vpc.inspection.id
  cidr_block              = local.cidr.ins_mgmt_az1
  availability_zone       = local.az1
  map_public_ip_on_launch = false
  tags = { Name = "ins-mgmt-az1" }
}
resource "aws_subnet" "ins_mgmt_az2" {
  vpc_id                  = aws_vpc.inspection.id
  cidr_block              = local.cidr.ins_mgmt_az2
  availability_zone       = local.az2
  map_public_ip_on_launch = false
  tags = { Name = "ins-mgmt-az2" }
}

# Untrust (public)
resource "aws_subnet" "ins_untrust_az1" {
  vpc_id                  = aws_vpc.inspection.id
  cidr_block              = local.cidr.ins_untrust_az1
  availability_zone       = local.az1
  map_public_ip_on_launch = true
  tags = { Name = "ins-untrust-az1" }
}
resource "aws_subnet" "ins_untrust_az2" {
  vpc_id                  = aws_vpc.inspection.id
  cidr_block              = local.cidr.ins_untrust_az2
  availability_zone       = local.az2
  map_public_ip_on_launch = true
  tags = { Name = "ins-untrust-az2" }
}

# Trust
resource "aws_subnet" "ins_trust_az1" {
  vpc_id                  = aws_vpc.inspection.id
  cidr_block              = local.cidr.ins_trust_az1
  availability_zone       = local.az1
  map_public_ip_on_launch = false
  tags = { Name = "ins-trust-az1" }
}
resource "aws_subnet" "ins_trust_az2" {
  vpc_id                  = aws_vpc.inspection.id
  cidr_block              = local.cidr.ins_trust_az2
  availability_zone       = local.az2
  map_public_ip_on_launch = false
  tags = { Name = "ins-trust-az2" }
}

# TGW Attach (host GWLBe)
resource "aws_subnet" "ins_tgwatt_az1" {
  vpc_id                  = aws_vpc.inspection.id
  cidr_block              = local.cidr.ins_tgwatt_az1
  availability_zone       = local.az1
  map_public_ip_on_launch = false
  tags = { Name = "ins-tgwatt-az1" }
}
resource "aws_subnet" "ins_tgwatt_az2" {
  vpc_id                  = aws_vpc.inspection.id
  cidr_block              = local.cidr.ins_tgwatt_az2
  availability_zone       = local.az2
  map_public_ip_on_launch = false
  tags = { Name = "ins-tgwatt-az2" }
}

############################################
# Subnets - Spoke VPCs
############################################
# Mgmt
resource "aws_subnet" "mgmt_az1" {
  vpc_id                  = aws_vpc.mgmt.id
  cidr_block              = local.cidr.mgmt_az1
  availability_zone       = local.az1
  map_public_ip_on_launch = false
  tags = { Name = "mgmt-az1" }
}
resource "aws_subnet" "mgmt_az2" {
  vpc_id                  = aws_vpc.mgmt.id
  cidr_block              = local.cidr.mgmt_az2
  availability_zone       = local.az2
  map_public_ip_on_launch = false
  tags = { Name = "mgmt-az2" }
}

# App
resource "aws_subnet" "app_az1" {
  vpc_id                  = aws_vpc.app.id
  cidr_block              = local.cidr.app_az1
  availability_zone       = local.az1
  map_public_ip_on_launch = false
  tags = { Name = "app-az1" }
}
resource "aws_subnet" "app_az2" {
  vpc_id                  = aws_vpc.app.id
  cidr_block              = local.cidr.app_az2
  availability_zone       = local.az2
  map_public_ip_on_launch = false
  tags = { Name = "app-az2" }
}

############################################
# Internet Gateway (Inspection) + NAT (Mgmt only)
############################################
resource "aws_internet_gateway" "ins" {
  vpc_id = aws_vpc.inspection.id
  tags   = { Name = "igw-inspection" }
}

resource "aws_eip" "nat_ins" {
  vpc  = true
  tags = { Name = "eip-nat-ins" }
}

resource "aws_nat_gateway" "ins_mgmt" {
  allocation_id = aws_eip.nat_ins.id
  subnet_id     = aws_subnet.ins_untrust_az1.id
  tags          = { Name = "natgw-inspection-mgmt" }
  depends_on    = [aws_internet_gateway.ins]
}

############################################
# Transit Gateway (+ Appliance Mode)
############################################
resource "aws_ec2_transit_gateway" "tgw" {
  description                     = "acme-palo-poc-tgw"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  tags = { Name = "tgw-acme-palo-poc" }
}

# Attachments
resource "aws_ec2_transit_gateway_vpc_attachment" "att_inspection" {
  subnet_ids             = [aws_subnet.ins_tgwatt_az1.id, aws_subnet.ins_tgwatt_az2.id]
  transit_gateway_id     = aws_ec2_transit_gateway.tgw.id
  vpc_id                 = aws_vpc.inspection.id
  appliance_mode_support = "enable"   # REQUIRED
  tags                   = { Name = "tgw-attach-inspection" }
}
resource "aws_ec2_transit_gateway_vpc_attachment" "att_mgmt" {
  subnet_ids         = [aws_subnet.mgmt_az1.id, aws_subnet.mgmt_az2.id]
  transit_gateway_id = aws_ec2_transit_gateway.tgw.id
  vpc_id             = aws_vpc.mgmt.id
  tags               = { Name = "tgw-attach-mgmt" }
}
resource "aws_ec2_transit_gateway_vpc_attachment" "att_app" {
  subnet_ids         = [aws_subnet.app_az1.id, aws_subnet.app_az2.id]
  transit_gateway_id = aws_ec2_transit_gateway.tgw.id
  vpc_id             = aws_vpc.app.id
  tags               = { Name = "tgw-attach-app" }
}

# TGW Route Tables
resource "aws_ec2_transit_gateway_route_table" "rt_spokes" {
  transit_gateway_id = aws_ec2_transit_gateway.tgw.id
  tags               = { Name = "tgw-rt-spokes" }
}
resource "aws_ec2_transit_gateway_route_table" "rt_inspection" {
  transit_gateway_id = aws_ec2_transit_gateway.tgw.id
  tags               = { Name = "tgw-rt-inspection" }
}

# Associations
resource "aws_ec2_transit_gateway_route_table_association" "assoc_mgmt" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.att_mgmt.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.rt_spokes.id
}
resource "aws_ec2_transit_gateway_route_table_association" "assoc_app" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.att_app.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.rt_spokes.id
}
resource "aws_ec2_transit_gateway_route_table_association" "assoc_inspection" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.att_inspection.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.rt_inspection.id
}

# Propagations
resource "aws_ec2_transit_gateway_route_table_propagation" "prop_mgmt_to_spokes" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.att_mgmt.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.rt_spokes.id
}
resource "aws_ec2_transit_gateway_route_table_propagation" "prop_app_to_spokes" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.att_app.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.rt_spokes.id
}
resource "aws_ec2_transit_gateway_route_table_propagation" "prop_inspection_to_inspection" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.att_inspection.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.rt_inspection.id
}

# TGW Routes
resource "aws_ec2_transit_gateway_route" "rt_spokes_default_to_inspection" {
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.att_inspection.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.rt_spokes.id
}
resource "aws_ec2_transit_gateway_route" "rt_spokes_ins_to_inspection" {
  destination_cidr_block         = aws_vpc.inspection.cidr_block
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.att_inspection.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.rt_spokes.id
}
resource "aws_ec2_transit_gateway_route" "rt_inspection_to_mgmt" {
  destination_cidr_block         = aws_vpc.mgmt.cidr_block
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.att_mgmt.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.rt_inspection.id
}
resource "aws_ec2_transit_gateway_route" "rt_inspection_to_app" {
  destination_cidr_block         = aws_vpc.app.cidr_block
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.att_app.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.rt_inspection.id
}

############################################
# Route Tables - Inspection VPC
############################################
# Mgmt RT
resource "aws_route_table" "ins_mgmt" {
  vpc_id = aws_vpc.inspection.id
  tags   = { Name = "rt-ins-mgmt" }
}
resource "aws_route_table_association" "ins_mgmt_a1" {
  route_table_id = aws_route_table.ins_mgmt.id
  subnet_id      = aws_subnet.ins_mgmt_az1.id
}
resource "aws_route_table_association" "ins_mgmt_a2" {
  route_table_id = aws_route_table.ins_mgmt.id
  subnet_id      = aws_subnet.ins_mgmt_az2.id
}
resource "aws_route" "ins_mgmt_to_tgw_mgmt" {
  route_table_id         = aws_route_table.ins_mgmt.id
  destination_cidr_block = aws_vpc.mgmt.cidr_block
  transit_gateway_id     = aws_ec2_transit_gateway.tgw.id
}
resource "aws_route" "ins_mgmt_to_tgw_app" {
  route_table_id         = aws_route_table.ins_mgmt.id
  destination_cidr_block = aws_vpc.app.cidr_block
  transit_gateway_id     = aws_ec2_transit_gateway.tgw.id
}
resource "aws_route" "ins_mgmt_default_nat" {
  route_table_id         = aws_route_table.ins_mgmt.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.ins_mgmt.id
}

# Untrust RT (public)
resource "aws_route_table" "ins_untrust" {
  vpc_id = aws_vpc.inspection.id
  tags   = { Name = "rt-ins-untrust" }
}
resource "aws_route_table_association" "ins_untrust_a1" {
  route_table_id = aws_route_table.ins_untrust.id
  subnet_id      = aws_subnet.ins_untrust_az1.id
}
resource "aws_route_table_association" "ins_untrust_a2" {
  route_table_id = aws_route_table.ins_untrust.id
  subnet_id      = aws_subnet.ins_untrust_az2.id
}
resource "aws_route" "ins_untrust_default_igw" {
  route_table_id         = aws_route_table.ins_untrust.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.ins.id
}

# Trust RT (to TGW)
resource "aws_route_table" "ins_trust" {
  vpc_id = aws_vpc.inspection.id
  tags   = { Name = "rt-ins-trust" }
}
resource "aws_route_table_association" "ins_trust_a1" {
  route_table_id = aws_route_table.ins_trust.id
  subnet_id      = aws_subnet.ins_trust_az1.id
}
resource "aws_route_table_association" "ins_trust_a2" {
  route_table_id = aws_route_table.ins_trust.id
  subnet_id      = aws_subnet.ins_trust_az2.id
}
resource "aws_route" "ins_trust_to_tgw_mgmt" {
  route_table_id         = aws_route_table.ins_trust.id
  destination_cidr_block = aws_vpc.mgmt.cidr_block
  transit_gateway_id     = aws_ec2_transit_gateway.tgw.id
}
resource "aws_route" "ins_trust_to_tgw_app" {
  route_table_id         = aws_route_table.ins_trust.id
  destination_cidr_block = aws_vpc.app.cidr_block
  transit_gateway_id     = aws_ec2_transit_gateway.tgw.id
}
resource "aws_route" "ins_trust_default_tgw" {
  route_table_id         = aws_route_table.ins_trust.id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = aws_ec2_transit_gateway.tgw.id
}

# TGW-attach RTs (per AZ → local GWLBe)
resource "aws_route_table" "ins_tgwatt_az1_rt" {
  vpc_id = aws_vpc.inspection.id
  tags   = { Name = "rt-ins-tgwattach-az1" }
}
resource "aws_route_table" "ins_tgwatt_az2_rt" {
  vpc_id = aws_vpc.inspection.id
  tags   = { Name = "rt-ins-tgwattach-az2" }
}
resource "aws_route_table_association" "ins_tgwatt_rt_assoc_az1" {
  route_table_id = aws_route_table.ins_tgwatt_az1_rt.id
  subnet_id      = aws_subnet.ins_tgwatt_az1.id
}
resource "aws_route_table_association" "ins_tgwatt_rt_assoc_az2" {
  route_table_id = aws_route_table.ins_tgwatt_az2_rt.id
  subnet_id      = aws_subnet.ins_tgwatt_az2.id
}

############################################
# SSM Interface Endpoints (with dedicated SGs)
############################################
resource "aws_security_group" "vpce_mgmt_sg" {
  name        = "sg-vpce-mgmt"
  description = "Allow HTTPS from Mgmt VPC to Interface Endpoints"
  vpc_id      = aws_vpc.mgmt.id

  ingress {
    description = "HTTPS from Mgmt VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.mgmt.cidr_block]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "sg-vpce-mgmt" }
}

resource "aws_security_group" "vpce_app_sg" {
  name        = "sg-vpce-app"
  description = "Allow HTTPS from App VPC to Interface Endpoints"
  vpc_id      = aws_vpc.app.id

  ingress {
    description = "HTTPS from App VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.app.cidr_block]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "sg-vpce-app" }
}

# Mgmt endpoints
resource "aws_vpc_endpoint" "mgmt_ssm" {
  vpc_id              = aws_vpc.mgmt.id
  service_name        = "com.amazonaws.us-west-2.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.mgmt_az1.id, aws_subnet.mgmt_az2.id]
  private_dns_enabled = true
  security_group_ids  = [aws_security_group.vpce_mgmt_sg.id]
  tags = { Name = "vpce-mgmt-ssm" }
}
resource "aws_vpc_endpoint" "mgmt_ec2msg" {
  vpc_id              = aws_vpc.mgmt.id
  service_name        = "com.amazonaws.us-west-2.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.mgmt_az1.id, aws_subnet.mgmt_az2.id]
  private_dns_enabled = true
  security_group_ids  = [aws_security_group.vpce_mgmt_sg.id]
  tags = { Name = "vpce-mgmt-ec2messages" }
}
resource "aws_vpc_endpoint" "mgmt_ssmmsg" {
  vpc_id              = aws_vpc.mgmt.id
  service_name        = "com.amazonaws.us-west-2.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.mgmt_az1.id, aws_subnet.mgmt_az2.id]
  private_dns_enabled = true
  security_group_ids  = [aws_security_group.vpce_mgmt_sg.id]
  tags = { Name = "vpce-mgmt-ssmmessages" }
}

# App endpoints
resource "aws_vpc_endpoint" "app_ssm" {
  vpc_id              = aws_vpc.app.id
  service_name        = "com.amazonaws.us-west-2.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.app_az1.id, aws_subnet.app_az2.id]
  private_dns_enabled = true
  security_group_ids  = [aws_security_group.vpce_app_sg.id]
  tags = { Name = "vpce-app-ssm" }
}
resource "aws_vpc_endpoint" "app_ec2msg" {
  vpc_id              = aws_vpc.app.id
  service_name        = "com.amazonaws.us-west-2.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.app_az1.id, aws_subnet.app_az2.id]
  private_dns_enabled = true
  security_group_ids  = [aws_security_group.vpce_app_sg.id]
  tags = { Name = "vpce-app-ec2messages" }
}
resource "aws_vpc_endpoint" "app_ssmmsg" {
  vpc_id              = aws_vpc.app.id
  service_name        = "com.amazonaws.us-west-2.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.app_az1.id, aws_subnet.app_az2.id]
  private_dns_enabled = true
  security_group_ids  = [aws_security_group.vpce_app_sg.id]
  tags = { Name = "vpce-app-ssmmessages" }
}

############################################
# Gateway Load Balancer + Endpoint Service + GWLBe
############################################
resource "aws_lb" "gwlb" {
  name               = "gwlb-inspection"
  load_balancer_type = "gateway"
  subnets            = [aws_subnet.ins_untrust_az1.id, aws_subnet.ins_untrust_az2.id]
  tags               = { Name = "gwlb-inspection" }
}

resource "aws_lb_target_group" "gwlb_tg" {
  name        = "gwlb-tg-pan"
  port        = 6081
  protocol    = "GENEVE"
  vpc_id      = aws_vpc.inspection.id
  target_type = "ip"       # REQUIRED for GWLB

  health_check {
    port     = "443"       # PAN dataplane health-check port
    protocol = "TCP"
  }

  tags = { Name = "gwlb-tg-pan" }
}

# (Targets added later via var.pan_dataplane_ips)

resource "aws_vpc_endpoint_service" "gwlb_svc" {
  acceptance_required        = false
  gateway_load_balancer_arns = [aws_lb.gwlb.arn]
  tags = { Name = "gwlb-endpoint-service" }
}

# GWLBe per AZ (hosted in the TGW-attach subnets)
resource "aws_vpc_endpoint" "gwlbe_az1" {
  vpc_id            = aws_vpc.inspection.id
  vpc_endpoint_type = "GatewayLoadBalancer"
  service_name      = aws_vpc_endpoint_service.gwlb_svc.service_name
  subnet_ids        = [aws_subnet.ins_tgwatt_az1.id]
  tags              = { Name = "gwlbe-ins-az1" }
}
resource "aws_vpc_endpoint" "gwlbe_az2" {
  vpc_id            = aws_vpc.inspection.id
  vpc_endpoint_type = "GatewayLoadBalancer"
  service_name      = aws_vpc_endpoint_service.gwlb_svc.service_name
  subnet_ids        = [aws_subnet.ins_tgwatt_az2.id]
  tags              = { Name = "gwlbe-ins-az2" }
}

# TGW-attach RTs → per-AZ GWLBe
resource "aws_route" "ins_tgwatt_az1_rt_default_to_gwlbe" {
  route_table_id         = aws_route_table.ins_tgwatt_az1_rt.id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = aws_vpc_endpoint.gwlbe_az1.id
}
resource "aws_route" "ins_tgwatt_az1_rt_mgmt_to_gwlbe" {
  route_table_id         = aws_route_table.ins_tgwatt_az1_rt.id
  destination_cidr_block = aws_vpc.mgmt.cidr_block
  vpc_endpoint_id        = aws_vpc_endpoint.gwlbe_az1.id
}
resource "aws_route" "ins_tgwatt_az1_rt_app_to_gwlbe" {
  route_table_id         = aws_route_table.ins_tgwatt_az1_rt.id
  destination_cidr_block = aws_vpc.app.cidr_block
  vpc_endpoint_id        = aws_vpc_endpoint.gwlbe_az1.id
}
resource "aws_route" "ins_tgwatt_az2_rt_default_to_gwlbe" {
  route_table_id         = aws_route_table.ins_tgwatt_az2_rt.id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = aws_vpc_endpoint.gwlbe_az2.id
}
resource "aws_route" "ins_tgwatt_az2_rt_mgmt_to_gwlbe" {
  route_table_id         = aws_route_table.ins_tgwatt_az2_rt.id
  destination_cidr_block = aws_vpc.mgmt.cidr_block
  vpc_endpoint_id        = aws_vpc_endpoint.gwlbe_az2.id
}
resource "aws_route" "ins_tgwatt_az2_rt_app_to_gwlbe" {
  route_table_id         = aws_route_table.ins_tgwatt_az2_rt.id
  destination_cidr_block = aws_vpc.app.cidr_block
  vpc_endpoint_id        = aws_vpc_endpoint.gwlbe_az2.id
}

############################################
# Edge NLB (listeners; bind PAN Untrust after launch)
############################################
resource "aws_lb" "nlb_edge" {
  name                             = "nlb-edge"
  load_balancer_type               = "network"
  internal                         = false
  subnets                          = [aws_subnet.ins_untrust_az1.id, aws_subnet.ins_untrust_az2.id]
  enable_cross_zone_load_balancing = true
  tags                             = { Name = "nlb-edge" }
}

resource "aws_lb_target_group" "nlb_tg_tcp80" {
  name        = "nlb-tg-80"
  port        = 80
  protocol    = "TCP"
  vpc_id      = aws_vpc.inspection.id
  target_type = "ip"
}
resource "aws_lb_target_group" "nlb_tg_tcp443" {
  name        = "nlb-tg-443"
  port        = 443
  protocol    = "TCP"
  vpc_id      = aws_vpc.inspection.id
  target_type = "ip"
}
resource "aws_lb_target_group" "nlb_tg_tcp22" {
  name        = "nlb-tg-22"
  port        = 22
  protocol    = "TCP"
  vpc_id      = aws_vpc.inspection.id
  target_type = "ip"
}

resource "aws_lb_listener" "nlb_listener_80" {
  load_balancer_arn = aws_lb.nlb_edge.arn
  port              = 80
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nlb_tg_tcp80.arn
  }
}
resource "aws_lb_listener" "nlb_listener_443" {
  load_balancer_arn = aws_lb.nlb_edge.arn
  port              = 443
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nlb_tg_tcp443.arn
  }
}
resource "aws_lb_listener" "nlb_listener_22" {
  load_balancer_arn = aws_lb.nlb_edge.arn
  port              = 22
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nlb_tg_tcp22.arn
  }
}

############################################
# Bastion Host (Mgmt VPC) - SSM only (no SSH keys)
############################################
data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
}

resource "aws_iam_role" "bastion_role" {
  name               = "bastion-ssm-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "bastion_ssm_core" {
  role       = aws_iam_role.bastion_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "bastion_profile" {
  name = "bastion-ssm-instance-profile"
  role = aws_iam_role.bastion_role.name
}

resource "aws_security_group" "bastion_sg" {
  name        = "sg-bastion-ssm"
  description = "Bastion uses SSM only; no inbound."
  vpc_id      = aws_vpc.mgmt.id

  # No ingress (SSM uses VPC endpoints)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "sg-bastion-ssm" }
}

resource "aws_instance" "bastion" {
  ami                    = data.aws_ssm_parameter.al2023_ami.value
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.mgmt_az1.id
  iam_instance_profile   = aws_iam_instance_profile.bastion_profile.name
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
  tags = { Name = "bastion-ssm" }
}

############################################
# PAN Security Groups (attach to PAN ENIs at launch)
############################################
# Mgmt SG - allow Bastion (or Mgmt VPC) to reach PAN mgmt (HTTPS/SSH)
resource "aws_security_group" "pan_mgmt_sg" {
  name        = "sg-pan-mgmt"
  description = "Allow Bastion/Mgmt VPC to reach PAN mgmt (443/22)."
  vpc_id      = aws_vpc.inspection.id

  ingress {
    description = "HTTPS from Mgmt VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.mgmt.cidr_block]
  }
  ingress {
    description = "SSH from Mgmt VPC (optional)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.mgmt.cidr_block]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "sg-pan-mgmt" }
}

# Dataplane SG - allow GENEVE + health-check from GWLBe subnets
resource "aws_security_group" "pan_dataplane_sg" {
  name        = "sg-pan-dataplane"
  description = "Allow UDP 6081 (GENEVE) + TCP 443 (HC) from TGW-attach (GWLBe) subnets."
  vpc_id      = aws_vpc.inspection.id

  ingress {
    description = "GENEVE from GWLBe (AZ1/AZ2)"
    from_port   = 6081
    to_port     = 6081
    protocol    = "udp"
    cidr_blocks = [local.cidr.ins_tgwatt_az1, local.cidr.ins_tgwatt_az2]
  }
  ingress {
    description = "Health check TCP/443 from GWLBe (AZ1/AZ2)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [local.cidr.ins_tgwatt_az1, local.cidr.ins_tgwatt_az2]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "sg-pan-dataplane" }
}

# Untrust SG - allow Internet ingress to PAN Untrust (NLB preserves client IP)
resource "aws_security_group" "pan_untrust_sg" {
  name        = "sg-pan-untrust"
  description = "Allow ingress 80/443/22 from Internet (tighten with CIDRs as needed)."
  vpc_id      = aws_vpc.inspection.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "SSH demo (restrict to allowlist in production)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "sg-pan-untrust" }
}

############################################
# Register PAN IPs (after launch) to GWLB & NLB
############################################
# GWLB target attachments (dataplane IPs)
resource "aws_lb_target_group_attachment" "gwlb_pan_targets" {
  for_each         = toset(var.pan_dataplane_ips)
  target_group_arn = aws_lb_target_group.gwlb_tg.arn
  target_id        = each.value
  port             = 6081
}

# NLB target attachments (Untrust IPs) - for ingress demo
resource "aws_lb_target_group_attachment" "nlb_pan_80" {
  for_each         = toset(var.pan_untrust_ips)
  target_group_arn = aws_lb_target_group.nlb_tg_tcp80.arn
  target_id        = each.value
  port             = 80
}
resource "aws_lb_target_group_attachment" "nlb_pan_443" {
  for_each         = toset(var.pan_untrust_ips)
  target_group_arn = aws_lb_target_group.nlb_tg_tcp443.arn
  target_id        = each.value
  port             = 443
}
resource "aws_lb_target_group_attachment" "nlb_pan_22" {
  for_each         = toset(var.pan_untrust_ips)
  target_group_arn = aws_lb_target_group.nlb_tg_tcp22.arn
  target_id        = each.value
  port             = 22
}
