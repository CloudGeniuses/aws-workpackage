############################
# EC2 INSTANCE - BASTION
############################
resource "aws_instance" "bastion" {
  ami               = "ami-0c5204531f799e0c6"
  instance_type     = "t3.micro"
  subnet_id         = aws_subnet.management_public.id
  key_name          = var.key_pair
  security_groups   = [
    aws_security_group.management_sg.name,
  ]
  tags = {
    Name = "Management-Bastion"
  }
}

############################
# EC2 INSTANCE - APP (NGINX)
############################
resource "aws_instance" "nginx" {
  ami               = "ami-0c5204531f799e0c6"
  instance_type     = "t3.micro"
  subnet_id         = aws_subnet.app_private.id
  key_name          = var.key_pair
  security_groups   = [
    aws_security_group.app_sg.name,
  ]
  tags = {
    Name = "App-NGINX"
  }

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              amazon-linux-extras install nginx1 -y
              systemctl enable nginx
              systemctl start nginx
              EOF
}

############################
# SECURITY GROUP - INSPECTION (SSM Port Forward)
############################
resource "aws_security_group" "inspection_sg" {
  name        = "inspection-sg"
  description = "Allow SSM port forwarding and inspection"
  vpc_id      = aws_vpc.inspection.id

  # Allow SSM port-forwarding (SSH & HTTPS)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [
      var.office_ip,
    ]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [
      var.office_ip,
    ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [
      "0.0.0.0/0",
    ]
  }
}

############################
# ROUTING PREPARED FOR NVA
############################
# These routes point to NVA manually deployed in Inspection VPC
resource "aws_route" "app_to_inspection" {
  route_table_id = aws_route_table.app_private.id
  destination_cidr_block = aws_vpc.inspection.cidr_block
  # Replace `instance_id` manually after Palo Alto is deployed
  # instance_id = "<PA-NVA-Instance-ID>"
}

resource "aws_route" "management_to_inspection" {
  route_table_id = aws_route_table.management_private.id
  destination_cidr_block = aws_vpc.inspection.cidr_block
  # Replace `instance_id` manually after Palo Alto is deployed
  # instance_id = "<PA-NVA-Instance-ID>"
}
