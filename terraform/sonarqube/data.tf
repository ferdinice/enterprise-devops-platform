data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket       = "ferdinand-enterprise-devops-tfstate-740994137090"
    key          = "network/terraform.tfstate"
    region       = "eu-west-3"
    profile      = "personal-devops"
    encrypt      = true
    use_lockfile = true
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true

  owners = ["099720109477"]

  filter {
    name = "name"

    values = [
      "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"
    ]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}