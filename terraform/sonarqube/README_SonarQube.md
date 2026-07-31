
# SonarQube Infrastructure Module

## Overview

This Terraform module provisions a dedicated SonarQube server for the Enterprise DevOps Platform. It introduces automated static code analysis into the CI pipeline so that source code quality and security are verified before Docker images are built.

The module provides:

- Dedicated SonarQube EC2 instance
- Dedicated Security Group
- Ubuntu 24.04 LTS
- Docker installation through `userdata.sh`
- SonarQube Community Edition container
- Persistent Docker volumes
- Remote Terraform state
- Jenkins integration
- SonarQube Global Analysis Token authentication
- Foundation for future Quality Gate enforcement

---

## Architecture

```text
Developer
    |
    v
GitHub
    |
    v
Jenkins
    |
    +--> Checkout
    |
    +--> Maven Build & Test
    |
    +--> SonarQube Analysis
    |         |
    |         v
    |   SonarQube Server
    |         |
    |         +--> Bugs
    |         +--> Vulnerabilities
    |         +--> Code Smells
    |         +--> Security Hotspots
    |         +--> Duplicated Code
    |         +--> Maintainability
    |
    +--> Verify Artifact
    |
    +--> Archive Artifact
    |
    +--> Build Docker Image
```

## Why SonarQube Was Added

Before SonarQube, Jenkins could only determine whether the application could be built successfully.

Maven verifies compilation, dependency resolution, testing and packaging.

It does **not** determine whether the application is secure, maintainable or free from common coding issues.

SonarQube fills this gap by performing static code analysis.

## Why SonarQube Runs Before Docker

The pipeline performs analysis before Docker image creation.

```text
Checkout
   ↓
Build & Test
   ↓
SonarQube Analysis
   ↓
Verify Artifact
   ↓
Archive Artifact
   ↓
Build Docker Image
```

This follows the **Fail Fast** principle.

## Why a Separate EC2 Instance

SonarQube runs independently from Jenkins to provide:

- Resource isolation
- Failure isolation
- Independent scaling
- Easier maintenance
- Production-style architecture

## Folder Structure

```text
terraform/
└── sonarqube/
    ├── backend.tf
    ├── provider.tf
    ├── variables.tf
    ├── data.tf
    ├── main.tf
    ├── outputs.tf
    ├── userdata.sh
    └── README.md
```

## backend.tf

Stores Terraform state independently using:

```text
sonarqube/terraform.tfstate
```

This allows the module to be managed separately from network, IAM, ECR and compute.

## provider.tf

Defines:

- AWS Region
- AWS Profile
- Default Tags

Current deployment:

- Region: eu-west-3
- Profile: personal-devops

## variables.tf

Defines configurable values including:

- Instance type
- Region
- Profile
- Project name
- Environment
- Allowed CIDR

## data.tf

Reads remote Terraform state from the network module.

Retrieves:

- VPC ID
- Public Subnet IDs

Also discovers the latest Ubuntu 24.04 AMI.

## main.tf

Creates:

- Security Group
- SonarQube EC2 instance

The instance uses:

- t3.medium
- 30 GB encrypted gp3 volume
- IMDSv2
- Public IP
- user_data bootstrap

## userdata.sh

Automatically:

1. Updates Ubuntu
2. Installs Docker
3. Enables Docker
4. Configures Linux kernel parameters
5. Creates Docker volumes
6. Pulls SonarQube Community image
7. Starts SonarQube

Kernel settings:

```text
vm.max_map_count=524288
fs.file-max=131072
```

## outputs.tf

Returns:

- sonarqube_instance_id
- sonarqube_public_ip
- sonarqube_security_group_id
- sonarqube_url

## Jenkins Integration

Installed:

- SonarQube Scanner for Jenkins Plugin

Configured:

- SonarQube Server
- Global Analysis Token
- Jenkins Credentials

Credentials are stored securely instead of inside the Jenkinsfile.

## SonarQube Pipeline Stage

```groovy
stage('SonarQube Analysis') {
    steps {
        withSonarQubeEnv('SonarQube') {
            sh '''
            ./mvnw org.sonarsource.scanner.maven:sonar-maven-plugin:sonar             -Dsonar.projectKey=pet-adoption             -Dsonar.projectName="Pet Adoption"
            '''
        }
    }
}
```

## First Pipeline Failure

The original command:

```bash
./mvnw sonar:sonar
```

failed because Maven could not resolve the plugin prefix.

It was corrected by using the fully qualified Maven plugin coordinates.

## Current Pipeline Flow

```text
Checkout
    ↓
Build & Test
    ↓
SonarQube Analysis
    ↓
Verify Artifact
    ↓
Archive Artifact
    ↓
Build Docker Image
    ↓
Verify Docker Image
```

## Production Improvements

- Private subnet
- HTTPS
- Reverse proxy / ALB
- External PostgreSQL
- Persistent storage
- Monitoring
- Token rotation
- Quality Gates
- Automated backups
- Disaster recovery

## Cost Control

Destroy when not required:

```bash
terraform destroy
```

Only the SonarQube module is removed.

## Key DevOps Lessons

- Jenkins orchestrates.
- Maven builds.
- SonarQube analyses.
- Docker packages.
- Secrets belong in Jenkins Credentials.
- Fail fast.
- Keep Terraform modules independent.
- Use remote state rather than hardcoding IDs.

## Conclusion

This module transforms the Enterprise DevOps Platform from a simple build pipeline into a quality-driven CI platform. Every application is now analysed before packaging, bringing the workflow closer to enterprise DevOps practices.
