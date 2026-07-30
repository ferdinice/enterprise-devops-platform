#!/bin/bash
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update -y

apt-get install -y \
  ca-certificates \
  curl \
  unzip \
  gnupg \
  fontconfig \
  openjdk-21-jre \
  docker.io

systemctl enable docker
systemctl start docker

install -m 0755 -d /etc/apt/keyrings

wget -O /etc/apt/keyrings/jenkins-keyring.asc \
  https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key

echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
  > /etc/apt/sources.list.d/jenkins.list

apt-get update -y
apt-get install -y jenkins

usermod -aG docker jenkins

systemctl enable jenkins
systemctl restart jenkins

curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
  -o "/tmp/awscliv2.zip"

unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install

rm -rf /tmp/aws /tmp/awscliv2.zip