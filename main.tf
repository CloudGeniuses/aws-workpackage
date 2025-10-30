#############################################
# ACME CORP / ADVANTUS360 Palo Alto NVA POC
# Terraform Infrastructure (AWS)
# Region: us-west-2
#############################################

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

#############################################
# VARIABLES
#############################################

variable "region" {
  description = "AWS region for deployment"
  default     = "us-west-2"
}

variable "azs" {
  description = "Availability Zones"
  default     = ["us-west-2a", "us-west-2b"]
}

#############################################
# MANAGEMENT VPC
#############################################

module "mgmt_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.2"

  name = "mgmt-vpc"
  cidr = "10.10.0.0/16"
  azs  = var.azs

  private_subnets = ["10.10.1.0/24", "10.10.2.0/24"]
  public_subnets  = ["10.10.11.0/24", "10.10.12.0/24"]
  intra_subnets   = ["10.10.21.0/24", "10.10.22.0/24"] # TGW attachment subnets

  enable_nat_gateway = true
  single_nat_gateway = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Environment = "POC", Name = "Mgmt-VPC" }
}

#############################################
# APPLICATION VPC
#############################################

module "app_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.2"

  name = "app-vpc"
  cidr = "10.20.0.0/16"
  azs  = var.azs

  private_subnets = ["10.20.1.0/24", "10.20.2.0/24"]
  public_subnets  = ["10.20.11.0/24", "10.20.12.0/24"]
  intra_subnets   = ["10.20.21.0/24", "10.20.22.0/24"] # TGW attachment subnets

  enable_nat_gateway = true
  single_nat_gateway = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Environment = "POC", Name = "App-VPC" }
}

#############################################
# INSPECTION VPC (for Palo Alto NVAs)
#############################################

module "inspection_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.2"

  name = "inspection-vpc"
  cidr = "10.30.0.0/16"
  azs  = var.azs

  public_subnets     = ["10.30.11.0/24", "10.30.12.0/24"]  # untrust
  private_subnets    = ["10.30.21.0/24", "10.30.22.0/24"]  # trust
  intra_subnets      = ["10.30.31.0/24", "10.30.32.0/24"]  # TGW attachment
  gwlb_subnets       = ["10.30.41.0/24", "10.30.42.0/24"]  # GWLB interface

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Environment = "POC", Name = "Inspection-VPC" }
}

#############################################
# TRANSIT GATEWAY & ROUTING
#############################################

resource "aws_ec2_transit_gateway" "main" {
  description = "Central TGW for inspection routing"
  amazon_side_asn = 64512
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  tags = { Name = "central-tgw" }
}

resource "aws_ec2_transit_gateway_route_table" "spoke" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  tags = { Name = "spoke-rt" }
}

resource "aws_ec2_transit_gateway_route_table" "inspection" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  tags = { Name = "inspection-rt" }
}

# Attachments
resource "aws_ec2_transit_gateway_vpc_attachment" "mgmt" {
  subnet_ids         = module.mgmt_vpc.intra_subnets
  vpc_id             = module.mgmt_vpc.vpc_id
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  tags               = { Name = "mgmt-attachment" }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "app" {
  subnet_ids         = module.app_vpc.intra_subnets
  vpc_id             = module.app_vpc.vpc_id
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  tags               = { Name = "app-attachment" }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "inspection" {
  subnet_ids             = module.inspection_vpc.intra_subnets
  vpc_id                 = module.inspection_vpc.vpc_id
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
  appliance_mode_support = "enable"
  tags                   = { Name = "inspection-attachment" }
}

# Associations
resource "aws_ec2_transit_gateway_route_table_association" "mgmt_assoc" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.mgmt.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke.id
}

resource "aws_ec2_transit_gateway_route_table_association" "app_assoc" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.app.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke.id
}

resource "aws_ec2_transit_gateway_route_table_association" "inspection_assoc" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.inspection.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.inspection.id
}

# Routing between spokes and inspection
resource "aws_ec2_transit_gateway_route" "spoke_to_inspection" {
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.inspection.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke.id
}

resource "aws_ec2_transit_gateway_route" "inspection_to_spokes" {
  destination_cidr_block         = "10.0.0.0/8"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.app.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.inspection.id
}

#############################################
# GATEWAY LOAD BALANCER (for Palo Alto)
#############################################

resource "aws_lb" "gwlb" {
  name               = "inspection-gwlb"
  load_balancer_type = "gateway"
  subnets            = module.inspection_vpc.gwlb_subnets
  tags               = { Name = "inspection-gwlb" }
}

resource "aws_lb_target_group" "gwlb_tg" {
  name     = "inspection-gwlb-tg"
  port     = 6081
  protocol = "GENEVE"
  vpc_id   = module.inspection_vpc.vpc_id

  health_check {
    port     = "80"
    protocol = "TCP"
  }

  tags = { Name = "inspection-gwlb-tg" }
}

resource "aws_vpc_endpoint_service" "gwlb_service" {
  acceptance_required        = false
  gateway_load_balancer_arns = [aws_lb.gwlb.arn]
  tags                       = { Name = "inspection-gwlb-service" }
}

#############################################
# GWLBe ENDPOINTS in APP & MGMT VPCs
#############################################

resource "aws_vpc_endpoint" "mgmt_gwlbe" {
  service_name      = aws_vpc_endpoint_service.gwlb_service.service_name
  vpc_id            = module.mgmt_vpc.vpc_id
  subnet_ids        = module.mgmt_vpc.public_subnets
  vpc_endpoint_type = "GatewayLoadBalancer"
  tags              = { Name = "mgmt-gwlbe" }
}

resource "aws_vpc_endpoint" "app_gwlbe" {
  service_name      = aws_vpc_endpoint_service.gwlb_service.service_name
  vpc_id            = module.app_vpc.vpc_id
  subnet_ids        = module.app_vpc.public_subnets
  vpc_endpoint_type = "GatewayLoadBalancer"
  tags              = { Name = "app-gwlbe" }
}

#############################################
# NLB (Ingress entry point for web traffic)
#############################################

resource "aws_lb" "app_nlb" {
  name               = "app-ingress-nlb"
  load_balancer_type = "network"
  subnets            = module.app_vpc.public_subnets
  tags               = { Name = "app-ingress-nlb" }
}

resource "aws_lb_target_group" "app_nlb_tg" {
  name        = "app-nlb-tg"
  port        = 80
  protocol    = "TCP"
  vpc_id      = module.app_vpc.vpc_id
  target_type = "ip"
  tags        = { Name = "app-nlb-tg" }
}

resource "aws_lb_listener" "app_nlb_listener" {
  load_balancer_arn = aws_lb.app_nlb.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_nlb_tg.arn
  }
}

#############################################
# EC2 INSTANCES: Bastion (Mgmt) & Web (App)
#############################################

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  subnet_id              = element(module.mgmt_vpc.private_subnets, 0)
  iam_instance_profile   = aws_iam_instance_profile.ssm_instance_profile.name
  tags                   = { Name = "bastion-ssm" }
}

resource "aws_instance" "app_server" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"
  subnet_id     = element(module.app_vpc.private_subnets, 0)
  user_data     = <<-EOF
    #!/bin/bash
    dnf install -y nginx
    systemctl enable nginx
    systemctl start nginx
  EOF
  tags = { Name = "app-nginx" }
}

#############################################
# IAM/SSM for Secure Access
#############################################

data "aws_iam_policy_document" "ssm_trust" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "ssm_role" {
  name               = "ssm-instance-role"
  assume_role_policy = data.aws_iam_policy_document.ssm_trust.json
}

resource "aws_iam_role_policy_attachment" "ssm_core_attach" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_instance_profile" {
  name = "ssm-instance-profile"
  role = aws_iam_role.ssm_role.name
}
