variable "name" {
  description = "Cluster name (also the resource name prefix)"
  type        = string
}

variable "region" {
  description = "AWS region (used by the aws-auth bootstrap provisioner)"
  type        = string
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version (major.minor)"
  type        = string
  default     = "1.35"
}

variable "vpc_id" {
  description = "VPC id the cluster lives in"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block (in-VPC traffic allowed to the nodes)"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets for the managed node group (one per AZ)"
  type        = list(string)
}

variable "worker_instance_types" {
  description = "Node group instance types. t3.medium is the smallest EKS-supported type and runs this app comfortably"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "worker_disk_size_gb" {
  description = "GP3 root volume size per node"
  type        = number
  default     = 20
}

variable "worker_min_size" {
  description = "Node group minimum size (use >= number of AZs for real HA)"
  type        = number
  default     = 1
}

variable "worker_max_size" {
  description = "Node group maximum size"
  type        = number
  default     = 3
}

variable "worker_desired_size" {
  description = "Node group desired size"
  type        = number
  default     = 3
}

variable "github_repo" {
  description = "GitHub repo (owner/name) allowed to assume the CD (deploy) role via OIDC"
  type        = string
  default     = "michaeltg17/AWS.Deployment"
}

variable "tags" {
  description = "Tags applied to every resource in this module"
  type        = map(string)
  default     = {}
}
