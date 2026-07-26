variable "aws_region" {
  description = "AWS region used by the project"
  type        = string
  default     = "eu-west-3"
}

variable "project_name" {
  description = "Project name used when naming AWS resources"
  type        = string
  default     = "enterprise-devops-platform"
}