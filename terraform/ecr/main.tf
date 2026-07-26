resource "aws_ecr_repository" "pet_adoption" {

  name = "${var.project_name}/${var.repository_name}"

  image_tag_mutability = "IMMUTABLE"

  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name = "${var.project_name}-${var.repository_name}"
  }
}

resource "aws_ecr_lifecycle_policy" "pet_adoption" {
  repository = aws_ecr_repository.pet_adoption.name
  policy     = file("${path.module}/lifecycle-policy.json")
}