variable "project_name" {
  description = "Tag applied to every resource (AWS resource-group equivalent)"
  type        = string
  default     = "aws-deployment"
}

locals {
  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
