data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket  = "ferdinand-enterprise-devops-tfstate-740994137090"
    key     = "network/terraform.tfstate"
    region  = "eu-west-3"
    profile = "personal-devops"
  }
}

data "terraform_remote_state" "iam" {
  backend = "s3"

  config = {
    bucket  = "ferdinand-enterprise-devops-tfstate-740994137090"
    key     = "iam/terraform.tfstate"
    region  = "eu-west-3"
    profile = "personal-devops"
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}