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

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs, one per AZ (ALB + NAT)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs, one per AZ (EKS nodes + RDS)"
  type        = list(string)
  default     = ["10.0.10.0/23", "10.0.12.0/23", "10.0.14.0/23"]
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version (major.minor)"
  type        = string
  default     = "1.35"
}

variable "worker_instance_types" {
  description = "Node group instance types. This account is Free Tier-restricted and only permits t3.micro, t3.small, t4g.micro, t4g.small, c7i-flex.large, m7i-flex.large; m7i-flex.large (2 vCPU/8 GB) is the smallest that meets EKS's ~2 vCPU/4 GB node minimum"
  type        = list(string)
  default     = ["m7i-flex.large"]
}

variable "worker_disk_size_gb" {
  description = "GP3 root volume per node"
  type        = number
  default     = 20
}

variable "worker_min_size" {
  description = "Node group min size (use 3 = one per AZ for real HA)"
  type        = number
  default     = 1
}

variable "worker_max_size" {
  description = "Node group max size (1 keeps the node bill inside the 750 free-tier hours/month)"
  type        = number
  default     = 1
}

variable "worker_desired_size" {
  description = "Node group desired size (1 node is enough for this app and stays within free tier)"
  type        = number
  default     = 1
}

variable "db_engine_version" {
  description = "RDS PostgreSQL engine version"
  type        = string
  default     = "18.6"
}

variable "db_instance_class" {
  description = "RDS instance class (db.t4g.micro = cheapest, Multi-AZ capable)"
  type        = string
  default     = "db.t4g.micro"
}

variable "db_master_password" {
  description = "RDS master password. MUST equal DB_PASSWORD in k8s/environments/<env>.secrets.env and the DB_PASSWORD_<ENV> GitHub secret"
  type        = string
  sensitive   = true
}

variable "db_multi_az" {
  description = "RDS Multi-AZ standby (survives AZ failure; roughly doubles the DB cost)"
  type        = bool
  default     = true
}
