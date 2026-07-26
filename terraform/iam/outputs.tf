output "jenkins_role_name" {
  description = "Name of the IAM role used by the Jenkins EC2 instance"
  value       = aws_iam_role.jenkins.name
}

output "jenkins_role_arn" {
  description = "ARN of the IAM role used by Jenkins"
  value       = aws_iam_role.jenkins.arn
}

output "jenkins_instance_profile_name" {
  description = "Name of the Jenkins EC2 instance profile"
  value       = aws_iam_instance_profile.jenkins.name
}