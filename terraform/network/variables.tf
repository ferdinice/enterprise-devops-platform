variable "aws_region" {
  description = "AWS region used for the network infrastructure"
  type        = string
  default     = "eu-west-3"
}

variable "vpc_cidr" {
  description = "CIDR block assigned to the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "project_name" {
  description = "Name used to identify project resources"
  type        = string
  default     = "enterprise-devops-platform"
}

variable "availability_zones" {
  description = "Availability Zones used by the network"
  type        = list(string)
  default     = ["eu-west-3a", "eu-west-3b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}