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

# -----------------------
# VARIABLES
# -----------------------
variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "us-west-2"
}

variable "management_vpc_cidr" {
  description = "CIDR block for Management VPC"
  type        = string
  default     = "10.10.0.0/16"
}

variable "app_vpc_cidr" {
  description = "CIDR block for App VPC"
  type        = string
  default     = "10.20.0.0/16"
}

variable "inspection_vpc_cidr" {
  description = "CIDR block for Inspection VPC"
  type        = string
  default     = "10.30.0.0/16"
}

variable "azs" {
  description = "List of AZs for HA"
  type        = list(string)
  default     = [
    "us-west-2a",
    "us-west-2b"
  ]
}

variable "admin_ip" {
  description = "Your public IP for SSH access to bastion"
  type        = string
  default     = "YOUR_PUBLIC_IP/32"
}

variable "key_name" {
  description = "SSH key name for EC2 instances"
  type        = string
  default     = "your-key"
}

# -----------------------
# VPCs
# -----------------------
resource "aws_vpc" "management" {
  cidr_block           = var.management_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "management-vpc"
  }
}

resource "aws_vpc" "app" {
  cidr_block           = var.app_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "app-vpc"
  }
}

resource "aws_vpc" "inspection" {
  cidr_block           = var.inspection_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "inspection-vpc"
  }
}

# -----------------------
# SUBNETS
# -----------------------
# Management VPC
resource "aws_subnet" "management_public" {
  for_each = toset(var.azs)

  vpc_id                   = aws_vpc.management.id
  cidr_block               = cidrsubnet(var.management_vpc_cidr, 8, index(var.azs, each.key))
  map_public_ip_on_launch  = true
  availability_zone        = each.key

  tags = {
    Name = "management-public-${each.key}"
  }
}

resource "aws_subnet" "management_private" {
  for_each = toset(var.azs)

  vpc_id            = aws_vpc.management.id
  cidr_block        = cidrsubnet(var.management_vpc_cidr, 8, index(var.azs, each.key) + 100)
  availability_zone = each.key

  tags = {
    Name = "management-private-${each.key}"
  }
}

# App VPC
resource "aws_subnet" "app_public" {
  for_each = toset(var.azs)

  vpc_id                  = aws_vpc.app.id
  cidr_block              = cidrsubnet(var.app_vpc_cidr, 8, index(var.azs, each.key))
  map_public_ip_on_launch = true
  availability_zone       = each.key

  tags = {
    Name = "app-public-${each.key}"
  }
}

resource "aws_subnet" "app_private" {
  for_each = toset(var.azs)

  vpc_id            = aws_vpc.app.id
  cidr_block        = cidrsubnet(var.app_vpc_cidr, 8, index(var.azs, each.key) + 100)
  availability_zone = each.key

  tags = {
    Name = "app-private-${each.key}"
  }
}

# Inspection VPC
resource "aws_subnet" "inspection_public" {
  for_each = toset(var.azs)

  vpc_id                  = aws_vpc.inspection.id
  cidr_block              = cidrsubnet(var.inspection_vpc_cidr, 8, index(var.azs, each.key))
  map_public_ip_on_launch = true
  availability_zone       = each.key

  tags = {
    Name = "inspection-public-${each.key}"
  }
}

resource "aws_subnet" "inspection_private" {
  for_each = toset(var.azs)

  vpc_id            = aws_vpc.inspection.id
  cidr_block        = cidrsubnet(var.inspection_vpc_cidr, 8, index(var.azs, each.key) + 100)
  availability_zone = each.key

  tags = {
    Name = "inspection-private-${each.key}"
  }
}

# -----------------------
# INTERNET GATEWAYS
# -----------------------
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

# -----------------------
# NAT GATEWAYS
# -----------------------
resource "aws_eip" "management_nat" {
  for_each = toset(var.azs)

  vpc = true

  tags = {
    Name = "management-nat-${each.key}"
  }
}

resource "aws_nat_gateway" "management" {
  for_each      = toset(var.azs)
  allocation_id = aws_eip.management_nat[each.key].id
  subnet_id     = aws_subnet.management_public[each.key].id

  tags = {
    Name = "management-nat-${each.key}"
  }
}

resource "aws_eip" "app_nat" {
  for_each = toset(var.azs)

  vpc = true

  tags = {
    Name = "app-nat-${each.key}"
  }
}

resource "aws_nat_gateway" "app" {
  for_each      = toset(var.azs)
  allocation_id = aws_eip.app_nat[each.key].id
  subnet_id     = aws_subnet.app_public[each.key].id

  tags = {
    Name = "app-nat-${each.key}"
  }
}

resource "aws_eip" "inspection_nat" {
  for_each = toset(var.azs)

  vpc = true

  tags = {
    Name = "inspection-nat-${each.key}"
  }
}

resource "aws_nat_gateway" "inspection" {
  for_each      = toset(var.azs)
  allocation_id = aws_eip.inspection_nat[each.key].id
  subnet_id     = aws_subnet.inspection_public[each.key].id

  tags = {
    Name = "inspection-nat-${each.key}"
  }
}

# -----------------------
# ROUTE TABLES
# -----------------------
resource "aws_route_table" "management_public" {
  vpc_id = aws_vpc.management.id

  tags = {
    Name = "management-public-rt"
  }
}

resource "aws_route_table" "management_private" {
  vpc_id = aws_vpc.management.id

  tags = {
    Name = "management-private-rt"
  }
}

resource "aws_route_table" "app_public" {
  vpc_id = aws_vpc.app.id

  tags = {
    Name = "app-public-rt"
  }
}

resource "aws_route_table" "app_private" {
  vpc_id = aws_vpc.app.id

  tags = {
    Name = "app-private-rt"
  }
}

resource "aws_route_table" "inspection_public" {
  vpc_id = aws_vpc.inspection.id

  tags = {
    Name = "inspection-public-rt"
  }
}

resource "aws_route_table" "inspection_private" {
  vpc_id = aws_vpc.inspection.id

  tags = {
    Name = "inspection-private-rt"
  }
}

# -----------------------
# ROUTES
# -----------------------
# Public subnets
resource "aws_route" "management_public_internet" {
  route_table_id         = aws_route_table.management_public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.management.id
}

resource "aws_route" "app_public_internet" {
  route_table_id         = aws_route_table.app_public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.app.id
}

resource "aws_route" "inspection_public_internet" {
  route_table_id         = aws_route_table.inspection_public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.inspection.id
}

# Private subnets to NAT (first AZ only for POC)
resource "aws_route" "management_private_nat" {
  route_table_id         = aws_route_table.management_private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.management[var.azs[0]].id
}

resource "aws_route" "app_private_nat" {
  route_table_id         = aws_route_table.app_private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.app[var.azs[0]].id
}

resource "aws_route" "inspection_private_nat" {
  route_table_id         = aws_route_table.inspection_private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.inspection[var.azs[0]].id
}

# -----------------------
# ROUTE TABLE ASSOCIATIONS
# -----------------------
resource "aws_route_table_association" "management_public_assoc" {
  for_each      = aws_subnet.management_public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.management_public.id
}

resource "aws_route_table_association" "management_private_assoc" {
  for_each      = aws_subnet.management_private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.management_private.id
}

resource "aws_route_table_association" "app_public_assoc" {
  for_each      = aws_subnet.app_public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.app_public.id
}

resource "aws_route_table_association" "app_private_assoc" {
  for_each      = aws_subnet.app_private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.app_private.id
}

resource "aws_route_table_association" "inspection_public_assoc" {
  for_each      = aws_subnet.inspection_public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.inspection_public.id
}

resource "aws_route_table_association" "inspection_private_assoc" {
  for_each      = aws_subnet.inspection_private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.inspection_private.id
}

# -----------------------
# PALO ALTO PLACEHOLDER ROUTES (to be updated with actual NVA IPs)
# -----------------------
# Example: route all private traffic through Palo Alto NVA
# Replace <PALO_INSPECTION_NVA_IP> and <PALO_MANAGEMENT_NVA_IP> manually
resource "aws_route" "management_private_nva" {
  route_table_id         = aws_route_table.management_private.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = "<PALO_MANAGEMENT_NVA_ENI>"
}

resource "aws_route" "app_private_nva" {
  route_table_id         = aws_route_table.app_private.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = "<PALO_APP_NVA_ENI>"
}

resource "aws_route" "inspection_private_nva" {
  route_table_id         = aws_route_table.inspection_private.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = "<PALO_INSPECTION_NVA_ENI>"
}
