# Jenkins Compute Module

## Overview

This Terraform module provisions the Jenkins Continuous Integration server for the Enterprise DevOps Platform.

The module creates:

- A Jenkins security group
- An Ubuntu EC2 instance
- An encrypted 30 GB gp3 root volume
- Automatic Jenkins installation through user data
- Docker installation
- AWS CLI installation
- Java 21 installation
- Integration with the existing Jenkins IAM instance profile
- Integration with the previously created network module

The Jenkins server will later build the Pet Adoption application, create Docker images and push versioned images to Amazon ECR.

---

## Architecture

```text
Internet
   |
   v
Public Route Table
   |
   v
Public Subnet
   |
   v
Jenkins Security Group
   |
   v
Jenkins EC2 Instance
   |
   +--> Java 21
   +--> Jenkins
   +--> Docker
   +--> AWS CLI
   |
   v
IAM Instance Profile
   |
   v
Temporary AWS Credentials
   |
   v
Amazon ECR
```

---

## Why Jenkins Was Created After the Other Modules

Jenkins depends on resources that were created earlier in the project.

These dependencies include:

- The VPC and public subnet from the network module
- The Jenkins IAM role and instance profile from the IAM module
- The ECR repository that will receive Docker images
- The S3 remote backend used to store Terraform state

The infrastructure was therefore created in layers:

```text
Backend
   |
Network
   |
IAM
   |
ECR
   |
Compute
```

This ensures that Jenkins has the networking, permissions and image repository it requires as soon as the instance is launched.

---

## Terraform Remote State

The compute module reads outputs from the network and IAM Terraform state files stored in S3.

The network state provides:

- VPC ID
- Public subnet IDs

The IAM state provides:

- Jenkins instance profile name

This allows the compute module to use resources created by other modules without hardcoding generated resource IDs.

Example dependency flow:

```text
network/terraform.tfstate
        |
        +--> VPC ID
        +--> Public subnet IDs
                     |
                     v
              Compute Module

iam/terraform.tfstate
        |
        +--> Jenkins instance profile
                     |
                     v
              Compute Module
```

---

## Jenkins Security Group

The security group controls network access to the Jenkins EC2 instance.

Jenkins uses TCP port:

```text
8080
```

For this temporary learning environment, port 8080 is currently allowed from:

```text
0.0.0.0/0
```

This was selected because the internet provider assigns a frequently changing public IPv4 address, which repeatedly caused a `/32` rule to block access.

This configuration is not suitable for production.

A production environment should use one or more of the following:

- A restricted trusted IP range
- AWS Systems Manager port forwarding
- A corporate VPN
- An Application Load Balancer
- HTTPS with AWS Certificate Manager
- Private subnet placement
- Authentication in front of Jenkins

SSH port 22 is not opened.

---

## EC2 Instance Configuration

The Jenkins server is configured with:

| Setting | Value |
|---|---|
| Operating system | Ubuntu 24.04 LTS |
| Instance type | `t3.medium` |
| Root volume | 30 GB gp3 |
| Volume encryption | Enabled |
| Public IP | Enabled |
| Subnet | Public subnet in Availability Zone A |
| SSH access | Disabled |
| Administration | AWS Systems Manager |
| Instance metadata | IMDSv2 required |

The EC2 instance uses the latest matching Ubuntu AMI returned by an AWS AMI data source instead of relying on a manually hardcoded AMI ID.

---

## IAM Instance Profile

The EC2 instance attaches the existing instance profile:

```text
enterprise-devops-platform-jenkins-instance-profile
```

The instance profile connects the EC2 instance to the Jenkins IAM role.

The role currently provides:

- AWS Systems Manager permissions
- Least-privilege access to the Pet Adoption ECR repository

AWS supplies temporary credentials through the EC2 Instance Metadata Service.

This means Jenkins does not require permanent AWS access keys to be stored on the server.

```text
Jenkins EC2
    |
    v
Instance Profile
    |
    v
IAM Role
    |
    v
Temporary Credentials
    |
    v
Amazon ECR
```

---

## User Data Bootstrap

The file:

```text
userdata.sh
```

runs automatically during the first boot of the EC2 instance.

It installs and configures:

- Java 21
- Docker
- Jenkins
- AWS CLI version 2

It also:

- Enables and starts Docker
- Enables and starts Jenkins
- Adds the Jenkins operating-system user to the Docker group
- Adds the official Jenkins package repository
- Installs the Jenkins repository signing key

The bootstrap process allows Terraform to create a ready-to-use Jenkins server without manually logging into the instance.

---

## Jenkins as an Orchestrator

Jenkins does not perform every CI task by itself.

It orchestrates tools installed on the server.

For example:

```text
Jenkins
   |
   +--> Git clones the application repository
   +--> Maven compiles and packages the Java application
   +--> Docker builds the container image
   +--> AWS CLI authenticates with Amazon ECR
   +--> Docker pushes the image to ECR
```

Jenkins executes the pipeline commands in the required order and stops the pipeline when a stage fails.

---

## Systems Manager Instead of SSH

AWS Systems Manager is used to administer and troubleshoot the Jenkins EC2 instance.

This avoids:

- Opening TCP port 22
- Managing SSH key pairs
- Distributing private key files
- Directly exposing administrative access to the internet

The EC2 instance registers with Systems Manager through:

```text
SSM Agent
   |
IAM Instance Profile
   |
AmazonSSMManagedInstanceCore
```

Systems Manager was used to:

- Verify the instance was online
- Inspect cloud-init logs
- Check the Jenkins service
- Check the Docker service
- Verify Java and AWS CLI installation
- Retrieve the initial Jenkins administrator password

---

## Bootstrap Failure and Troubleshooting

The first EC2 bootstrap did not complete successfully.

The observed symptoms were:

- Cloud-init reported an error
- Docker was active
- Java was installed
- Jenkins was inactive
- AWS CLI was not installed

The cloud-init output log was inspected at:

```text
/var/log/cloud-init-output.log
```

The log reported:

```text
NO_PUBKEY 7198F4B714ABFC68
The Jenkins repository is not signed
```

The original user-data script used an outdated Jenkins signing key.

Because the script contained:

```bash
set -euxo pipefail
```

the script stopped immediately when the package repository verification failed.

The failure happened after Docker and Java were installed but before Jenkins and AWS CLI were installed.

---

## Resolution

The bootstrap script was corrected by:

- Replacing the outdated Jenkins signing key with the current key
- Updating the Java runtime to Java 21
- Removing the full operating-system upgrade from initial boot
- Retaining strict failure handling
- Recreating the instance through Terraform

The EC2 resource contains:

```hcl
user_data_replace_on_change = true
```

When the user-data file changes, Terraform replaces the EC2 instance and runs the corrected script on a clean server.

This avoids undocumented manual repairs and configuration drift.

---

## Verification

The following checks were performed after deployment:

```bash
cloud-init status --long
systemctl is-active jenkins
systemctl is-active docker
java -version
aws --version
docker --version
```

Successful verification showed:

- Cloud-init status: `done`
- Cloud-init errors: none
- Jenkins: active
- Docker: active
- Java 21 installed
- AWS CLI installed
- Docker installed
- Jenkins listening on TCP port 8080

The Systems Manager registration was checked using:

```bash
aws ssm describe-instance-information \
  --profile personal-devops \
  --region eu-west-3
```

The initial Jenkins administrator password was retrieved through Systems Manager rather than SSH.

---

## Jenkins Persistence Limitation

The current design stores Jenkins application data on the EC2 root volume under:

```text
/var/lib/jenkins
```

This includes:

- Jenkins users
- Installed plugins
- Jobs
- Pipelines
- Credentials
- Build history
- Workspaces
- Global Jenkins configuration

The root volume uses:

```hcl
delete_on_termination = true
```

Therefore, when the compute module is destroyed, Jenkins application data is also deleted.

When the server is recreated, Jenkins must currently be unlocked and configured again.

This is acceptable during the temporary learning phase, but it is not a production-ready persistence design.

Future improvements may include:

- A separate persistent EBS volume for `/var/lib/jenkins`
- Automated Jenkins configuration as code
- Automated plugin installation
- Jenkins Configuration as Code
- External backup of Jenkins data
- Distributed Jenkins agents

---

## Cost Control

The Jenkins EC2 instance and its EBS volume generate ongoing charges while running.

At the end of a learning session, the compute resources can be removed with:

```bash
terraform destroy
```

The destroy operation removes:

- Jenkins EC2 instance
- Jenkins security group
- Root EBS volume
- Public IPv4 assignment

It does not remove:

- Network module resources
- IAM module resources
- ECR repository
- S3 remote state bucket

The module can be recreated later using:

```bash
terraform apply
```

---

## Terraform Workflow

```bash
terraform init
terraform fmt
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

To inspect outputs:

```bash
terraform output
```

To remove the temporary compute resources:

```bash
terraform destroy
```

---

## Outputs

The module returns:

- Jenkins EC2 instance ID
- Jenkins public IP address
- Jenkins URL

Example:

```text
jenkins_instance_id
jenkins_public_ip
jenkins_url
```

The public IP changes when the EC2 instance is destroyed and recreated.

---

## Production Improvements

The following changes would be required before using this architecture in production:

- Place Jenkins in a private subnet
- Use an Application Load Balancer
- Configure HTTPS using AWS Certificate Manager
- Point a domain such as `jenkins.ferdeve.online` to the load balancer
- Remove public access to port 8080
- Use SSM, VPN or private connectivity for administration
- Persist `/var/lib/jenkins`
- Configure backups
- Use Jenkins agents instead of running all builds on the controller
- Add monitoring and alerting
- Use Jenkins Configuration as Code
- Add automated secrets management
- Restrict outbound and inbound security-group rules
- Add high-availability and disaster-recovery planning

---

## Domain Name Integration

The domain name will not be attached directly to the temporary EC2 public IP during the current learning stage because the public IP changes whenever the instance is recreated.

The planned production-style flow is:

```text
jenkins.ferdeve.online
        |
        v
DNS Record
        |
        v
Application Load Balancer
        |
        v
HTTPS Certificate
        |
        v
Jenkins EC2
```

The domain will be introduced after the Jenkins CI pipeline is working and before the platform is presented as a completed production-style architecture.