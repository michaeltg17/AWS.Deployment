output "control_public_ip" {
  description = "Public IP of the k3s control node (app entrypoint: http://<ip>/ and rancher: http://<ip>:3080)"
  value       = aws_instance.control.public_ip
}

output "worker_public_ips" {
  description = "Public IPs of the k3s worker nodes"
  value       = aws_instance.worker[*].public_ip
}

output "ssh_user" {
  description = "SSH user"
  value       = var.ssh_user
}

output "ssh_command" {
  description = "Copy-paste SSH command for the control node (pass your own -i key)"
  value       = "ssh ${var.ssh_user}@${aws_instance.control.public_ip} -i <path-to-key.pem>"
}

output "destroy_command" {
  description = "Destroys everything this config created"
  value       = "terraform destroy (run from this directory)"
}
