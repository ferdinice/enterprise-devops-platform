provider "aws" {
  profile = "personal-devops"
  region  = var.aws_region

  default_tags {
    tags = {
      Project     = "enterprise-devops-platform"
      Environment = "dev"
      ManagedBy   = "Terraform"
      Owner       = "Ferdinand Ngaobiwu"
      Module      = "network"
    }
  }
}