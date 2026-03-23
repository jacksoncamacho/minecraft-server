provider "aws" {
  region = var.aws_region
}

terraform {
  backend "s3" {
    bucket = "bijadillo-terraform-state-city"
    key    = "minecraft/terraform.tfstate"
    region = "us-east-1"
  }
}

# --- VPC & Networking ---
data "aws_vpc" "bijadillo" {
  filter {
    name   = "tag:Name"
    values = ["*bijadillo*"]
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.bijadillo.id]
  }
}

# --- Security Group ---
resource "aws_security_group" "minecraft" {
  name        = "minecraft-sg-final"
  description = "Allow Minecraft and SSH"
  vpc_id      = data.aws_vpc.bijadillo.id

  ingress {
    from_port   = 25565
    to_port     = 25565
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Recommendation: restrict to user IP
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- IAM Role for S3 Access ---
resource "aws_iam_role" "minecraft_role" {
  name = "minecraft-server-role-final"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "s3_access" {
  name = "minecraft-s3-policy"
  role = aws_iam_role.minecraft_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
      Effect   = "Allow"
      Resource = [
        aws_s3_bucket.backups.arn,
        "${aws_s3_bucket.backups.arn}/*"
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_managed" {
  role       = aws_iam_role.minecraft_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "minecraft_profile" {
  name = "minecraft-instance-profile-final"
  role = aws_iam_role.minecraft_role.name
}

# --- S3 Bucket for Backups ---
resource "aws_s3_bucket" "backups" {
  bucket_prefix = "minecraft-backups-"
  force_destroy = true
}

# --- EC2 Spot Instance ---
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

resource "aws_key_pair" "minecraft_key" {
  count      = var.ssh_public_key != "" ? 1 : 0
  key_name   = "minecraft-key-final"
  public_key = var.ssh_public_key
}

resource "aws_spot_instance_request" "server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = var.ssh_public_key != "" ? aws_key_pair.minecraft_key[0].key_name : null
  subnet_id              = data.aws_subnets.public.ids[0]
  vpc_security_group_ids = [aws_security_group.minecraft.id]
  iam_instance_profile   = aws_iam_instance_profile.minecraft_profile.name
  
  spot_type            = "one-time" # One-time for simplicity in this setup
  wait_for_fulfillment = true
  
  user_data = templatefile("${path.module}/../scripts/setup-server.sh", {
    s3_bucket = aws_s3_bucket.backups.id
  })

  root_block_device {
    volume_size = 10
    volume_type = "gp3"
  }

  tags = { Name = "minecraft-server" }
}

# --- Elastic IP (Static IP) ---
resource "aws_eip" "minecraft_eip" {
  domain = "vpc"
  tags   = { Name = "minecraft-eip" }
}

resource "aws_eip_association" "minecraft_eip_assoc" {
  instance_id   = aws_spot_instance_request.server.spot_instance_id
  allocation_id = aws_eip.minecraft_eip.id
}

# --- DNS (Optional) ---
resource "aws_route53_record" "minecraft" {
  count   = var.route53_zone_id != "" ? 1 : 0
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"
  ttl     = "300"
  records = [aws_eip.minecraft_eip.public_ip]
}
