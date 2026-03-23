provider "aws" {
  region = var.aws_region
}

# --- VPC & Networking ---
resource "aws_vpc" "minecraft" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = { Name = "minecraft-vpc" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.minecraft.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"
  tags = { Name = "minecraft-subnet" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.minecraft.id
  tags   = { Name = "minecraft-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.minecraft.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# --- Security Group ---
resource "aws_security_group" "minecraft" {
  name        = "minecraft-sg"
  description = "Allow Minecraft and SSH"
  vpc_id      = aws_vpc.minecraft.id

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
  name = "minecraft-server-role"

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
  name = "minecraft-instance-profile"
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

resource "aws_spot_instance_request" "server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
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
