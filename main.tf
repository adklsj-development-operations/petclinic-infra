terraform {
  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
  required_version = ">= 1.5.0"
}

resource "tls_private_key" "petclinic" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "petclinic" {
  key_name   = "petclinic-key"
  public_key = tls_private_key.petclinic.public_key_openssh
}

provider "aws" {
  region = var.region
}

resource "aws_security_group" "petclinic" {
  name        = "petclinic-sg"
  description = "Allow SSH, app, and monitoring"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "App"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Grafana"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Prometheus"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "petclinic" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.petclinic.key_name
  vpc_security_group_ids = [aws_security_group.petclinic.id]

  root_block_device {
    volume_size = 20
  }

  tags = {
    Name = "petclinic"
  }
}