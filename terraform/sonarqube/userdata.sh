#!/bin/bash
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update -y

apt-get install -y \
  ca-certificates \
  curl \
  docker.io

systemctl enable docker
systemctl start docker

# SonarQube uses embedded Elasticsearch and requires these Linux limits.
cat >/etc/sysctl.d/99-sonarqube.conf <<'EOF'
vm.max_map_count=524288
fs.file-max=131072
EOF

sysctl --system

docker volume create sonarqube_data
docker volume create sonarqube_logs
docker volume create sonarqube_extensions

docker pull sonarqube:community

docker run -d \
  --name sonarqube \
  --restart unless-stopped \
  -p 9000:9000 \
  -v sonarqube_data:/opt/sonarqube/data \
  -v sonarqube_logs:/opt/sonarqube/logs \
  -v sonarqube_extensions:/opt/sonarqube/extensions \
  sonarqube:community