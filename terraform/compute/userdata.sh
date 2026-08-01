#!/bin/bash
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update -y

apt-get install -y \
  ca-certificates \
  curl \
  wget \
  unzip \
  gnupg \
  apt-transport-https \
  fontconfig \
  openjdk-21-jre \
  openjdk-17-jdk \
  docker.io

systemctl enable docker
systemctl start docker

cat <<'EOF' >/etc/profile.d/java17-build.sh
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export PATH=$JAVA_HOME/bin:$PATH
EOF

chmod 644 /etc/profile.d/java17-build.sh

install -m 0755 -d /etc/apt/keyrings

wget -O /etc/apt/keyrings/jenkins-keyring.asc \
  https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key

echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
  > /etc/apt/sources.list.d/jenkins.list

apt-get update -y
apt-get install -y jenkins

usermod -aG docker jenkins

# Install Trivy from the official Aqua Security repository.
wget -qO - https://get.trivy.dev/deb/public.key \
  | gpg --dearmor \
  | tee /usr/share/keyrings/trivy.gpg >/dev/null

echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://get.trivy.dev/deb generic main" \
  > /etc/apt/sources.list.d/trivy.list

apt-get update -y
apt-get install -y trivy

systemctl enable jenkins
systemctl restart jenkins

curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
  -o "/tmp/awscliv2.zip"

unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install

rm -rf /tmp/aws /tmp/awscliv2.zip

# Verify required build tools.
/usr/lib/jvm/java-17-openjdk-amd64/bin/java -version
/usr/lib/jvm/java-17-openjdk-amd64/bin/javac -version
docker --version
trivy --version
aws --version