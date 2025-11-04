############################################
# App VM (private) + SSM + simple web server
############################################

# (Reuses data.aws_ssm_parameter.al2023_ami already defined above)

# IAM assume role policy for EC2
data "aws_iam_policy_document" "app_ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app_ssm_role" {
  name               = "app-ssm-role"
  assume_role_policy = data.aws_iam_policy_document.app_ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "app_ssm_core" {
  role       = aws_iam_role.app_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "app_ssm_profile" {
  name = "app-ssm-instance-profile"
  role = aws_iam_role.app_ssm_role.name
}

# Security Group for the App VM
# Allows HTTP/HTTPS from:
#  - PAN trust subnets (10.10.21.0/24, 10.10.22.0/24)
#  - Mgmt VPC (10.20.0.0/16) for bastion-based tests through the firewall path
resource "aws_security_group" "app_web_sg" {
  name        = "app-web-sg"
  description = "Allow web from PAN trust and Mgmt CIDRs; egress all"
  vpc_id      = aws_vpc.app.id

  # HTTP/HTTPS from PAN trust subnets
  ingress {
    description = "HTTP from PAN trust subnets"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [local.cidr.ins_trust_az1, local.cidr.ins_trust_az2]
  }
  ingress {
    description = "HTTPS from PAN trust subnets"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [local.cidr.ins_trust_az1, local.cidr.ins_trust_az2]
  }

  # Optional: allow web from Mgmt VPC for bastion tests (source preserved)
  ingress {
    description = "HTTP from Mgmt VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.mgmt.cidr_block]
  }
  ingress {
    description = "HTTPS from Mgmt VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.mgmt.cidr_block]
  }

  # (Optional) ICMP from Mgmt for ping tests
  ingress {
    description = "ICMP echo from Mgmt VPC"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [aws_vpc.mgmt.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "sg-app-web" }
}

# App VM user-data (simple Apache site)
locals {
  app_user_data = <<-EOF
    #!/bin/bash
    set -eux
    # Amazon Linux 2023 uses dnf
    dnf -y install httpd
    systemctl enable httpd
    systemctl start httpd
    echo "Hello from the App VM (vpc-app) via TGW → GWLBe → PAN" > /var/www/html/index.html
  EOF
}

resource "aws_instance" "app_vm" {
  ami                    = data.aws_ssm_parameter.al2023_ami.value
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.app_az1.id         # you can switch to app_az2 if you prefer
  vpc_security_group_ids = [aws_security_group.app_web_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.app_ssm_profile.name
  associate_public_ip_address = false

  user_data = local.app_user_data

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = { Name = "app-vm-az1" }
}

############################################
# Helpful outputs
############################################
output "app_vm_private_ip" {
  value = aws_instance.app_vm.private_ip
}

output "app_vm_id" {
  value = aws_instance.app_vm.id
}
