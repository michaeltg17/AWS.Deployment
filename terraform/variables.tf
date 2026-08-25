variable "aws_region" {
  description = "AWS region to deploy in"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Optional AWS CLI profile name (empty = default credentials chain)"
  type        = string
  default     = ""
}

variable "environment" {
  description = "Environment tag, e.g. dev / qa / prod"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "Public subnet CIDR (k3s nodes live here and get public IPs)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "worker_instance_count" {
  description = "Number of k3s worker nodes (1 = control+1 worker, 2 = control+2 workers)"
  type        = number
  default     = 1
}

variable "instance_type" {
  description = "EC2 instance type for all nodes. t3.small (2GB) is the minimum that runs rancher + workloads"
  type        = string
  default     = "t3.small"
}

variable "root_volume_size_gb" {
  description = "GP3 root volume size per node (free tier: keep at or under 30GB total per account)"
  type        = number
  default     = 20
}

variable "ssh_allowed_cidrs" {
  description = "CIDRs allowed to SSH (port 22). Default is the internet - lock this down after validation"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "app_allowed_cidrs" {
  description = "CIDRs allowed to reach the app on ports 80/443"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ssh_user" {
  description = "SSH user for the Amazon Linux 2 AMI"
  type        = string
  default     = "ec2-user"
}

variable "ssh_key_name" {
  description = "Name of an EC2 key pair in this account to attach to the instances (import your local public key: aws ec2 import-key-pair)"
  type        = string
  default     = "aws-deployment-dev"
}
