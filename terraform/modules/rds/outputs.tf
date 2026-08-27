output "id" {
  description = "DB instance identifier"
  value       = aws_db_instance.this.id
}

output "arn" {
  description = "DB instance ARN"
  value       = aws_db_instance.this.arn
}

output "address" {
  description = "Private endpoint address (put in k8s/environments/<env>.env as RDS_ENDPOINT)"
  value       = aws_db_instance.this.address
}

output "port" {
  description = "DB port"
  value       = aws_db_instance.this.port
}

output "username" {
  description = "Master username (put in k8s/environments/<env>.env as DB_USER)"
  value       = aws_db_instance.this.username
}
