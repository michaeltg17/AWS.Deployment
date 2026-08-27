variable "name" {
  description = "DB instance identifier (lowercase, hyphens ok)"
  type        = string
}

variable "engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "18.6"
}

variable "instance_class" {
  description = "DB instance class. db.t4g.micro is the cheapest PostgreSQL class and supports Multi-AZ"
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage_gb" {
  description = "Initial GP3 storage"
  type        = number
  default     = 20
}

variable "max_allocated_storage_gb" {
  description = "Storage auto-scaling ceiling (free until actually used)"
  type        = number
  default     = 100
}

variable "db_name" {
  description = "Initial database name"
  type        = string
  # "Database" is a reserved word in PostgreSQL 18+
  default = "appdb"
}

variable "master_username" {
  description = "Master username (dev: the app connects as the master user)"
  type        = string
  default     = "app"
}

variable "master_password" {
  description = "Master password. Must match DB_PASSWORD in k8s/environments/<env>.secrets.env and the CD secret"
  type        = string
  sensitive   = true
}

variable "multi_az" {
  description = "Multi-AZ standby (handles infrastructure failure, roughly doubles DB cost)"
  type        = bool
  default     = true
}

variable "vpc_id" {
  description = "VPC id"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets for the DB subnet group (must span >= 2 AZs)"
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "Security groups allowed to connect (EKS node SG)"
  type        = list(string)
  default     = []
}

variable "vpc_cidr" {
  description = "VPC CIDR block. EKS managed node groups attach EKS-managed SGs to node ENIs (not the node SG), so allow the whole VPC for reliable DB access"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to every resource in this module"
  type        = map(string)
  default     = {}
}
