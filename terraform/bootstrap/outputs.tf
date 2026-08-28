output "state_bucket" {
  description = "S3 bucket holding the Terraform state of all environments"
  value       = aws_s3_bucket.state.id
}


