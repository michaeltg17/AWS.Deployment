terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }

  # This stack's state lives in the bucket it creates (chicken and egg: the
  # bucket must exist first - one-time `aws s3api create-bucket` +
  # `terraform import`, see ARCH.md). Every environment stores its state under
  # its own key in the same bucket.
  backend "s3" {
    bucket       = "michaeltg17-template-terraform-state"
    key          = "bootstrap/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = "us-east-1"
}
