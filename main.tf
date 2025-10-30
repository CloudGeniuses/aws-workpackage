provider "aws" {
  region = "us-west-2"
}

# -------------------------------
# VPC Modules
# -------------------------------
module "management_vpc" {
  source       = "terraform-aws-modules/vpc/aws"
  version      = "4.0.2"
  name         = "management-vpc"
  cidr         = "10.10.0.0/16"
  azs          = ["us-west-2a", "us-west-2b"]
  public_subnets  = ["10.10.1.0/24", "10.10.2.0/24"]
  private_subnets = ["10.10.11.0/24", "10.10.12.0/24"]
  enable_nat_gateway = true
}

module "app_vpc" {
  source       = "terraform-aws-modules/vpc/aws"
  version      = "4.0.2"
  name         = "app-vpc"
  cidr         = "10.20.0.0/16"
  azs          = ["us-west-2a", "us-west-2b"]
  public_subnets  = ["10.20.1.0/24", "10.20.2.0/24"]
  private_subnets = ["10.20.11.0/24", "10.20.12.0/24"]
  enable_nat_gateway = true
}

module "inspection_vpc" {
  source       = "terraform-aws-modules/vpc/aws"
  version      = "4.0.2"
  name         = "inspection-vpc"
  cidr         = "10.30.0.0/16"
  azs          = ["us-west-2a", "us-west-2b"]
  public_subnets  = ["10.30.1.0/24", "10.30.2.0/24"]
  private_subnets = ["10.30.11.0/24", "10.30.12.0/24"]
  enable_nat_gateway = true
}

# -------------------------------
# Security Groups
# -------------------------------
# Bastion Host SG (SSM only)
resource "aws_security_group" "bastion_sg" {
  name        = "bastion_sg"
  description = "Bastion SG for SSM only"
  vpc_id      = module.management_vpc.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Application SG (HTTP/HTTPS from NVA)
resource "aws_security_group" "app_sg" {
  name        = "app_sg"
  description = "App SG for NGINX server"
  vpc_id      = module.app_vpc.vpc_id

  ingress {
    description = "HTTP from inspection VPC / NVA"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.30.0.0/16"]  # Inspection VPC CIDR
  }

  ingress {
    description = "HTTPS from inspection VPC / NVA"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.30.0.0/16"]  # Inspection VPC CIDR
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# -------------------------------
# IAM Role for SSM
# -------------------------------
resource "aws_iam_role" "ssm_role" {
  name = "ssm_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_attach" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_profile" {
  name = "ssm_profile"
  role = aws_iam_role.ssm_role.name
}

# -------------------------------
# Bastion Host (Private, SSM-enabled)
# -------------------------------
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  subnet_id              = module.management_vpc.private_subnets[0]
  security_groups        = [aws_security_group.bastion_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ssm_profile.name
  tags = { Name = "Bastion-SSM" }
}

# -------------------------------
# NAT EIPs (no vpc argument)
# -------------------------------
resource "aws_eip" "nat_management" {
  depends_on = [module.management_vpc.internet_gateway_id]
}

resource "aws_eip" "nat_app" {
  depends_on = [module.app_vpc.internet_gateway_id]
}

resource "aws_eip" "nat_inspection" {
  depends_on = [module.inspection_vpc.internet_gateway_id]
}

# -------------------------------
# Private Route Tables (ready for manual Palo)
# -------------------------------
resource "aws_route_table" "management_private" {
  vpc_id = module.management_vpc.vpc_id
}

resource "aws_route" "management_private_to_nva" {
  route_table_id         = aws_route_table.management_private.id
  destination_cidr_block = "0.0.0.0/0"
  # Target: add NVA ENI manually
}

resource "aws_route_table" "app_private" {
  vpc_id = module.app_vpc.vpc_id
}

resource "aws_route" "app_private_to_nva" {
  route_table_id         = aws_route_table.app_private.id
  destination_cidr_block = "0.0.0.0/0"
  # Target: add NVA ENI manually
}

resource "aws_route_table" "inspection_private" {
  vpc_id = module.inspection_vpc.vpc_id
}

resource "aws_route" "inspection_private_to_nva" {
  route_table_id         = aws_route_table.inspection_private.id
  destination_cidr_block = "0.0.0.0/0"
  # Target: add NVA ENI manually
}

# -------------------------------
# Example EC2 for Application (NGINX)
# -------------------------------
resource "aws_instance" "app_server" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.small"
  subnet_id              = module.app_vpc.private_subnets[0]
  security_groups        = [aws_security_group.app_sg.id]
  tags = { Name = "NGINX-App-Server" }
}
