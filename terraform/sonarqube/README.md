
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


# addition
---

## SonarQube Webhook and Quality Gate Enforcement

After the initial SonarQube analysis integration was completed, the Jenkins pipeline could submit source code for analysis and display the results in SonarQube. However, Jenkins initially continued through the remaining stages regardless of whether the SonarQube result passed or failed.

This behaviour was not sufficient for a production-style CI pipeline because static analysis should act as a release control rather than an informational report.

The pipeline was therefore extended with a SonarQube webhook and a Jenkins Quality Gate stage.

---

## Why a Webhook Is Required

SonarQube processes analysis reports asynchronously.

The Maven Sonar plugin uploads the analysis report to SonarQube, but the report upload can finish before SonarQube has completed:

- Processing the analysis
- Applying quality rules
- Calculating metrics
- Evaluating the assigned Quality Gate
- Producing the final pass or fail result

Jenkins therefore cannot reliably assume that the Quality Gate result is available immediately after the analysis command finishes.

The webhook provides a feedback channel from SonarQube to Jenkins.

```text
Jenkins
   |
   +--> Runs SonarQube analysis
   |
   +--> Uploads analysis report
               |
               v
          SonarQube
               |
               +--> Processes report
               +--> Evaluates Quality Gate
               |
               v
        Sends webhook result
               |
               v
            Jenkins
            
## webhook configuration

Administration
    |
    v
Webhooks
    |
    v
Create

SonarQube Quality Gate & Webhook Integration Documentation


OVERVIEW

After integrating SonarQube into Jenkins, Jenkins could upload code for analysis but could not determine whether the analysis passed or failed because SonarQube processes reports asynchronously.

To solve this, a SonarQube Webhook and Jenkins Quality Gate stage were implemented.

ARCHITECTURE FLOW

Developer
  ↓
Checkout
  ↓
Build & Test
  ↓
SonarQube Analysis
  ↓
SonarQube Processes Report
  ↓
Quality Gate Evaluation
  ↓
Webhook Notification
  ↓
Jenkins waitForQualityGate()
  ↓
PASS → Continue
FAIL → Abort Pipeline

WHY THE WEBHOOK IS REQUIRED

The SonarScanner uploads analysis results but does not notify Jenkins when processing finishes.

The webhook provides that feedback. After SonarQube evaluates the Quality Gate, it sends the final result to:

http://<jenkins-ip>:8080/sonarqube-webhook/

This allows Jenkins to continue or abort the pipeline.

QUALITY GATE

The Jenkins pipeline uses:

timeout(time: 5, unit: 'MINUTES') {
    waitForQualityGate abortPipeline: true
}

waitForQualityGate pauses the pipeline until SonarQube returns the final Quality Gate result.

The timeout prevents Jenkins from waiting forever if the webhook never arrives.

CONTROLLED FAILURE TEST

A temporary Quality Gate called 'Portfolio Failure Test' was created instead of modifying the developer's Java source code.

The project initially passed because the rule checked New Code coverage.

The gate was then changed to evaluate Overall Code coverage at 100%.

Since the project coverage was approximately 89.8%, the Quality Gate returned ERROR.

JENKINS RESULT

Checkout                PASSED
Build & Test            PASSED
SonarQube Analysis      PASSED
Quality Gate            FAILED
Verify Artifact         SKIPPED
Archive Artifact        SKIPPED
Build Docker Image      SKIPPED
Verify Docker Image     SKIPPED
Post Actions            EXECUTED

This proved that Jenkins successfully received the webhook response and aborted the pipeline before packaging.

KEY LESSONS

• SonarQube analysis is asynchronous.
• Webhooks provide the feedback channel.
• waitForQualityGate blocks until the result arrives.
• timeout prevents infinite waiting.
• abortPipeline protects the delivery pipeline.
• Failed Quality Gates stop packaging and deployment.
• Post Actions still execute for reporting and cleanup.