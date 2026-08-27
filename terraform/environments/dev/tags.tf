variable "project_name" {
  description = "Resource name prefix and Project tag (AWS resource-group equivalent)"
  type        = string
  default     = "aws-deployment"
}

variable "environment" {
  description = "Environment name (suffix of every resource name + Environment tag)"
  type        = string
  default     = "dev"
}

locals {
  name = "${var.project_name}-${var.environment}"

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
