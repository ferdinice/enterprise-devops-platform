resource "aws_security_group" "sonarqube" {
  name        = "${var.project_name}-sonarqube-sg"
  description = "Allow SonarQube web access"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id

  ingress {
    description = "SonarQube web interface"
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = [var.allowed_admin_cidr]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sonarqube-sg"
  }
}

resource "aws_instance" "sonarqube" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.sonarqube_instance_type
  subnet_id                   = data.terraform_remote_state.network.outputs.public_subnet_ids[0]
  associate_public_ip_address = true

  vpc_security_group_ids = [
    aws_security_group.sonarqube.id
  ]

  user_data                   = file("${path.module}/userdata.sh")
  user_data_replace_on_change = true

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name = "${var.project_name}-sonarqube-server"
  }
}