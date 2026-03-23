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
  default     = "seressa.bijadillo.com"
}

variable "ssh_public_key" {
  description = "Public key for SSH access"
  type        = string
  default     = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDGXqHPikxU124iMAr8ZWLviMOU9+gD0n9MhTXw9+3M7fMXWj8GGFzEbX6Ck+/WN2WHJqXRcvIYmus1G4JLFPZ0H3/JhOvvBteMd58W05fsYVhLXEzu7E9zJKKY0w1ZOC5v4+5/HW4p5UWueetWgeungqkiCLtRDqrk9Y3WTHpsYuwx3shFKZcSPd1CyC26oMSKXdEV/9ojkaXDNhciFXCd0ymyylULPeduQQs49ecL0RGgAYJJmKGlIgnXB2DD8K7rkAZepgLw7KJKzOoQ9xp2fIvYVyo7yJdqudgvIVwb4O1wAcQ4l7Y2g5CaIHLfheBJReTSDnzMdM4OFXEyXQdBe5fR7ebfZ5Q+wVaqwxew5wbn0tGKIBbWUR8Q3BCQVQnc4g4zAFvBrauv5TvnEWZC5YQGuflWTb7MylcER+2Q3kgTDc5VnGWGGnX2AMl6Zfm+5oxB83aQL4fErs4LdNTEw0fKG1E4h2+ONvJuFY8c9ewZqeKkIKXBdZ0/pUxjBEjXJZcgQfzevI4qUCc7KsKgn0XcWFd0XaKr1Nk7kJrplksloKYJIf0nRxeuig2dzg+dJ+N3y10rI3rxlLk3Vbzx1XDldsoY0+QD1YMsOcFCd6GDlQDBKgW7tlLVKMnYdXstgOwyWHsmp2ogNeuHD5xUrQkdOZCPb9Pcm6r+fH8PXw== sergi@SOCIOSPC"
}
