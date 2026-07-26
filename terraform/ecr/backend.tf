terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket       = "ferdinand-enterprise-devops-tfstate-740994137090"
    key          = "ecr/terraform.tfstate"
    region       = "eu-west-3"
    profile      = "personal-devops"
    encrypt      = true
    use_lockfile = true
  }
}