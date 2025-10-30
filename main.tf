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

############################
# VARIABLES
############################

variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-1"
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
  description = "List of Availability Zones to use"
  type        = list(string)
  default     = ["a", "b"]
}

############################
# VPCS
############################

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

############################
# PUBLIC SUBNETS
############################

resource "aws_subnet" "management_public" {
  vpc_id                  = aws_vpc.management.id
  cidr_block              = "10.10.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}${var.azs[0]}"

  tags = {
    Name = "management-public"
  }
}

resource "aws_subnet" "app_public" {
  vpc_id                  = aws_vpc.app.id
  cidr_block              = "10.20.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}${var.azs[0]}"

  tags = {
    Name = "app-public"
  }
}

resource "aws_subnet" "inspection_public" {
  vpc_id                  = aws_vpc.inspection.id
  cidr_block              = "10.30.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}${var.azs[0]}"

  tags = {
    Name = "inspection-public"
  }
}

############################
# PRIVATE SUBNETS
############################

resource "aws_subnet" "management_private" {
  vpc_id            = aws_vpc.management.id
  cidr_block        = "10.10.2.0/24"
  availability_zone = "${var.aws_region}${var.azs[0]}"

  tags = {
    Name = "management-private"
  }
}

resource "aws_subnet" "app_private" {
  vpc_id            = aws_vpc.app.id
  cidr_block        = "10.20.2.0/24"
  availability_zone = "${var.aws_region}${var.azs[0]}"

  tags = {
    Name = "app-private"
  }
}

resource "aws_subnet" "inspection_private" {
  vpc_id            = aws_vpc.inspection.id
  cidr_block        = "10.30.2.0/24"
  availability_zone = "${var.aws_region}${var.azs[0]}"

  tags = {
    Name = "inspection-private"
  }
}

############################
# INTERNET GATEWAYS
############################

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

############################
# NAT GATEWAYS
############################

resource "aws_eip" "management_nat" {
  tags = {
    Name = "management-nat-eip"
  }
}

resource "aws_nat_gateway" "management" {
  allocation_id = aws_eip.management_nat.id
  subnet_id     = aws_subnet.management_public.id

  tags = {
    Name = "management-nat"
  }
}

resource "aws_eip" "app_nat" {
  tags = {
    Name = "app-nat-eip"
  }
}

resource "aws_nat_gateway" "app" {
  allocation_id = aws_eip.app_nat.id
  subnet_id     = aws_subnet.app_public.id

  tags = {
    Name = "app-nat"
  }
}

resource "aws_eip" "inspection_nat" {
  tags = {
    Name = "inspection-nat-eip"
  }
}

resource "aws_nat_gateway" "inspection" {
  allocation_id = aws_eip.inspection_nat.id
  subnet_id     = aws_subnet.inspection_public.id

  tags = {
    Name = "inspection-nat"
  }
}

############################
# PRIVATE ROUTE TABLES
############################

resource "aws_route_table" "management_private" {
  vpc_id = aws_vpc.management.id

  tags = {
    Name = "management-private-rt"
  }
}

resource "aws_route_table" "app_private" {
  vpc_id = aws_vpc.app.id

  tags = {
    Name = "app-private-rt"
  }
}

resource "aws_route_table" "inspection_private" {
  vpc_id = aws_vpc.inspection.id

  tags = {
    Name = "inspection-private-rt"
  }
}

############################
# ROUTES TO NAT
############################

resource "aws_route" "management_private_nat" {
  route_table_id         = aws_route_table.management_private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.management.id
}

resource "aws_route" "app_private_nat" {
  route_table_id         = aws_route_table.app_private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.app.id
}

resource "aws_route" "inspection_private_nat" {
  route_table_id         = aws_route_table.inspection_private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.inspection.id
}

############################
# ROUTE TABLE ASSOCIATIONS
############################

resource "aws_route_table_association" "management_private_assoc" {
  subnet_id      = aws_subnet.management_private.id
  route_table_id = aws_route_table.management_private.id
}

resource "aws_route_table_association" "app_private_assoc" {
  subnet_id      = aws_subnet.app_private.id
  route_table_id = aws_route_table.app_private.id
}

resource "aws_route_table_association" "inspection_private_assoc" {
  subnet_id      = aws_subnet.inspection_private.id
  route_table_id = aws_route_table.inspection_private.id
}

############################
# PLACEHOLDER FOR PALO ALTO NVAs
# Note: You will manually deploy 2 Palo Alto instances
# Attach their ENIs to management and app subnets, update
# route tables to point to NVA for east-west and north-south traffic
############################
