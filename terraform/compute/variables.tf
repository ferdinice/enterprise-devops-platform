variable "aws_region" {
  description = "AWS region used for Jenkins infrastructure"
  type        = string
  default     = "eu-west-3"
}

variable "project_name" {
  description = "Project name used when naming resources"
  type        = string
  default     = "enterprise-devops-platform"
}

variable "instance_type" {
  description = "EC2 instance type used by Jenkins"
  type        = string
  default     = "t3.medium"
}

variable "jenkins_port" {
  description = "Port used by the Jenkins web interface"
  type        = number
  default     = 8080
}

variable "allowed_admin_cidr" {
  description = "Public IPv4 CIDR allowed to access the Jenkins web interface"
  type        = string
}