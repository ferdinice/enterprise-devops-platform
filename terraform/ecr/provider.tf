provider "aws" {
  profile = "personal-devops"
  region  = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = "dev"
      ManagedBy   = "Terraform"
      Owner       = "Ferdinand Ngaobiwu"
      Module      = "ecr"
    }
  }
}