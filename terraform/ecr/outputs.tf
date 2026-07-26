output "repository_name" {
  description = "Name of the Pet Adoption ECR repository"
  value       = aws_ecr_repository.pet_adoption.name
}

output "repository_url" {
  description = "URL used to push and pull Pet Adoption container images"
  value       = aws_ecr_repository.pet_adoption.repository_url
}

output "repository_arn" {
  description = "ARN of the Pet Adoption ECR repository"
  value       = aws_ecr_repository.pet_adoption.arn
}