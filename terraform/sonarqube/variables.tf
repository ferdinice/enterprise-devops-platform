variable "aws_region" {
  description = "AWS region used for the SonarQube infrastructure"
  type        = string
  default     = "eu-west-3"
}

variable "aws_profile" {
  description = "AWS CLI profile used by Terraform"
  type        = string
  default     = "personal-devops"
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "enterprise-devops-platform"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "owner" {
  description = "Resource owner"
  type        = string
  default     = "Ferdinand Ngaobiwu"
}

variable "sonarqube_instance_type" {
  description = "EC2 instance type for the SonarQube server"
  type        = string
  default     = "t3.medium"
}

variable "allowed_admin_cidr" {
  description = "CIDR allowed to access the SonarQube web interface"
  type        = string
  default     = "0.0.0.0/0"
}