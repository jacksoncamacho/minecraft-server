output "instance_public_ip" {
  value = aws_spot_instance_request.server.public_ip
}

output "s3_bucket_name" {
  value = aws_s3_bucket.backups.id
}
