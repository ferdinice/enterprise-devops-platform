output "sonarqube_instance_id" {
  description = "EC2 instance ID of the SonarQube server"
  value       = aws_instance.sonarqube.id
}

output "sonarqube_public_ip" {
  description = "Public IPv4 address of the SonarQube server"
  value       = aws_instance.sonarqube.public_ip
}

output "sonarqube_url" {
  description = "URL of the SonarQube web interface"
  value       = "http://${aws_instance.sonarqube.public_ip}:9000"
}

output "sonarqube_security_group_id" {
  description = "Security group ID attached to the SonarQube server"
  value       = aws_security_group.sonarqube.id
}