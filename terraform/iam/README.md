# Jenkins IAM Module

## Overview

This module creates the AWS IAM resources required by the future Jenkins EC2 server in the Enterprise DevOps Platform.

Instead of storing permanent AWS access keys on the Jenkins server, the EC2 instance will assume an IAM role and receive temporary AWS credentials automatically.

This improves security and follows the AWS principle of least privilege.

---

## Resources Created

This module creates:

- One Jenkins IAM role
- One AWS-managed policy attachment
- One Jenkins EC2 instance profile

---

## Jenkins IAM Role

The role is named:

```text
enterprise-devops-platform-jenkins-role
```

Its trust policy allows the EC2 service to assume the role:

```text
ec2.amazonaws.com
```

This means the role can be used by an EC2 instance but cannot be assumed automatically by unrelated AWS services.

---

## Systems Manager Permission

The role currently has the AWS-managed policy:

```text
AmazonSSMManagedInstanceCore
```

This allows the future Jenkins EC2 instance to communicate with AWS Systems Manager.

Systems Manager will help us:

- manage the server without exposing SSH broadly,
- run commands remotely,
- inspect the instance,
- and improve administrative security.

---

## Instance Profile

The instance profile is named:

```text
enterprise-devops-platform-jenkins-instance-profile
```

An IAM role cannot be attached directly to an EC2 instance.

The instance profile acts as the container through which the Jenkins IAM role is attached to EC2.

```text
IAM Role
    ↓
Instance Profile
    ↓
Jenkins EC2 Instance
```

---

## Security Design

This module avoids storing long-lived AWS credentials on Jenkins.

The EC2 instance will receive temporary credentials through the AWS Instance Metadata Service.

Benefits include:

- No hard-coded AWS access keys
- Automatic credential rotation
- Reduced credential leakage risk
- Centralised permission management
- Easier permission revocation

---

## Least-Privilege Approach

The Jenkins role currently has only Systems Manager permissions.

Permissions for services such as Amazon ECR and Kubernetes will be added later when those integrations are implemented.

This avoids granting unnecessary access before it is required.

---

## Remote Terraform State

The IAM module stores its Terraform state in the remote S3 backend at:

```text
iam/terraform.tfstate
```

This keeps IAM state separate from the network and backend modules.

---

## Deployment

```bash
terraform init
terraform fmt
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

---

## Verification

Verify the Jenkins IAM role:

```bash
aws iam get-role \
  --role-name enterprise-devops-platform-jenkins-role \
  --profile personal-devops
```

Verify the attached policy:

```bash
aws iam list-attached-role-policies \
  --role-name enterprise-devops-platform-jenkins-role \
  --profile personal-devops
```

Verify the instance profile:

```bash
aws iam get-instance-profile \
  --instance-profile-name enterprise-devops-platform-jenkins-instance-profile \
  --profile personal-devops
```

---

## Cost Consideration

IAM roles, policy attachments and instance profiles do not have hourly running charges.

The IAM resources can remain in the AWS account when the compute infrastructure is destroyed.

---

## Engineering Notes

- An IAM role provides permissions without requiring permanent access keys.
- A trust policy defines who or what may assume a role.
- The Jenkins trust policy allows EC2 to assume the role.
- An instance profile is used to attach an IAM role to an EC2 instance.
- Systems Manager reduces the need to expose SSH access.
- Least privilege means adding only the permissions currently required.

---

## Interview Summary

The Jenkins server uses an EC2 IAM role instead of stored AWS credentials.

The role is attached through an instance profile and currently grants only Systems Manager permissions. Additional permissions will be added gradually as Jenkins integrates with ECR and Kubernetes.


## Amazon ECR Permission

The Jenkins IAM role also has a custom policy named:

```text
enterprise-devops-platform-jenkins-ecr-policy
```

This policy allows Jenkins to authenticate with Amazon ECR and push container images to:

```text
enterprise-devops-platform/pet-adoption
```

The policy grants repository actions including:

- Checking image-layer availability
- Starting and completing layer uploads
- Uploading image layers
- Publishing image manifests
- Listing and describing images
- Downloading image layers when required

The permission is restricted to the Pet Adoption repository rather than granting access to every ECR repository in the AWS account.

---

## ECR Authentication

The action:

```text
ecr:GetAuthorizationToken
```

uses:

```text
Resource = "*"
```

This is required because the ECR authorisation token is issued at the registry level rather than for one individual repository.

Repository-specific push and inspection permissions remain restricted to the Pet Adoption repository ARN.

---

## Updated Least-Privilege Design

The Jenkins role currently has:

- AWS Systems Manager access
- Access to push and inspect images in the Pet Adoption ECR repository

It does not have permission to:

- Create or delete ECR repositories
- Manage unrelated ECR repositories
- Create AWS infrastructure
- Administer IAM
- Manage the Kubernetes cluster

Additional permissions will be introduced only when the related pipeline stage is implemented.

---

## Updated Permission Flow

```text
Jenkins EC2 Instance
        |
        v
Jenkins Instance Profile
        |
        v
Jenkins IAM Role
        |
        +--> AmazonSSMManagedInstanceCore
        |
        +--> Jenkins ECR Custom Policy
                    |
                    v
Enterprise DevOps Platform
Pet Adoption ECR Repository
```

---

## ECR Verification

Verify all policies attached to Jenkins:

```bash
aws iam list-attached-role-policies \
  --role-name enterprise-devops-platform-jenkins-role \
  --profile personal-devops
```

Expected policies:

```text
AmazonSSMManagedInstanceCore
enterprise-devops-platform-jenkins-ecr-policy
```

---

## Interview Question: Why not use AmazonEC2ContainerRegistryFullAccess?

The AWS-managed full-access policy would give Jenkins much broader ECR permissions than it currently requires.

A custom policy was created to limit Jenkins to the actions needed to authenticate, upload, inspect and retrieve images from the Pet Adoption repository. This follows the principle of least privilege and reduces the impact of a compromised Jenkins server.