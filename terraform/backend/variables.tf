variable "aws_region" {
  description = "AWS region where the Terraform state bucket will be created"
  type        = string
  default     = "eu-west-3"
}

variable "state_bucket_name" {
  description = "Globally unique S3 bucket name used to store Terraform state"
  type        = string
}