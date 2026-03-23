variable "aws_region" {
  description = "AWS region to deploy to"
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type"
  default     = "t3.small"
}

variable "route53_zone_id" {
  description = "Route53 Hosted Zone ID for your domain (bijadillo.com)"
  default     = "" # Empty means DNS won't be created
}

variable "domain_name" {
  description = "Domain name for the server"
  default     = "mc.bijadillo.com"
}
