# Terraform Backend Bootstrap

## Overview

This module creates the Amazon S3 bucket used as the remote Terraform backend for the Enterprise DevOps Platform.

Terraform uses a state file to remember which infrastructure resources it manages. The state file connects the Terraform configuration to the real resources running in AWS.

The backend is created before the other infrastructure modules so that those modules have a secure and central location for storing their state.

---

## Why the Backend Is Created Separately

Terraform cannot store its state in an S3 bucket before that bucket exists.

For this reason, the backend must be created first using local state. Once the S3 bucket has been created, the remaining Terraform modules can use it as their remote backend.

This is known as the Terraform bootstrap problem.

The backend prepares the foundation for every other Terraform module. It is similar to preparing the way before the main work begins.

---

## Why Remote State Is Used

Terraform stores state locally by default in:

```text
terraform.tfstate
```

Keeping the state only on one laptop creates several risks:

- The state could be lost if the laptop fails.
- The file could be accidentally deleted.
- Another authorised engineer or CI/CD system could not access it.
- The state could be accidentally committed to GitHub.
- Multiple engineers could make conflicting infrastructure changes.

Storing the state remotely in Amazon S3 provides a central, durable and secure location that authorised users and systems can access.

The state is not publicly available over the internet. Access is controlled through AWS IAM permissions.

---

## Resources Created

This module creates the following AWS resources:

- An Amazon S3 bucket
- S3 bucket versioning
- Server-side encryption
- S3 public-access blocking

The backend bucket is:

```text
ferdinand-enterprise-devops-tfstate-740994137090
```

The AWS region is:

```text
eu-west-3
```

---

## S3 Bucket Purpose

The S3 bucket stores the Terraform state files for the platform.

Each future infrastructure component will use a different state path, for example:

```text
network/terraform.tfstate
iam/terraform.tfstate
compute/terraform.tfstate
ecr/terraform.tfstate
kops/terraform.tfstate
```

Using separate state paths prevents one infrastructure component from overwriting another component's state.

---

## Versioning

S3 versioning is enabled on the backend bucket.

Versioning keeps previous versions of the Terraform state file. This allows an earlier version to be recovered if the current state is accidentally overwritten or corrupted.

Versioning is important because the Terraform state file is the record of the infrastructure Terraform manages.

---

## Encryption

The backend bucket uses AES-256 server-side encryption.

Terraform state may contain infrastructure information such as:

- Resource identifiers
- Network configuration
- IP addresses
- Infrastructure relationships
- Sensitive values

Encryption protects the state file while it is stored in Amazon S3.

---

## Public Access Protection

All public access to the backend bucket is blocked.

The following protections are enabled:

- Block public ACLs
- Ignore public ACLs
- Block public bucket policies
- Restrict public buckets

Terraform state must never be publicly accessible. Only authorised AWS identities should be able to read or update it.

---

## Destroy Protection

The S3 bucket uses the following lifecycle rule:

```hcl
lifecycle {
  prevent_destroy = true
}
```

This prevents Terraform from accidentally deleting the state bucket.

The backend is a permanent platform component and should remain available even when temporary infrastructure such as EC2 instances, load balancers or the Kubernetes cluster is destroyed.

---

## Bootstrap Process

The backend creation process is:

```text
Local Terraform State
        |
        v
Create S3 Backend Bucket
        |
        v
Enable Versioning, Encryption and Public Access Blocking
        |
        v
Use the S3 Bucket for Future Terraform Modules
```

The backend module keeps its initial state locally because the remote bucket did not exist when the module was first applied.

All future modules will use the S3 bucket as their remote backend.

---

## Cost Consideration

The S3 backend will remain running because it stores the infrastructure state.

The expected cost is very low because:

- Terraform state files are small.
- The number of S3 requests is limited.
- No large application files are stored in the bucket.

More expensive resources such as EC2 instances, NAT Gateways, load balancers and the KOps cluster will be destroyed when they are not required.

---

## Terraform Files

```text
terraform/backend/
├── main.tf
├── outputs.tf
├── provider.tf
├── variables.tf
└── README.md
```

### `provider.tf`

Defines:

- The required Terraform version
- The AWS provider
- The personal AWS CLI profile
- The AWS region
- Default resource tags

### `variables.tf`

Defines configurable values such as:

- AWS region
- S3 backend bucket name

### `main.tf`

Creates:

- The S3 bucket
- Bucket versioning
- AES-256 encryption
- Public-access blocking
- Destroy protection

### `outputs.tf`

Displays:

- The S3 bucket name
- The S3 bucket ARN

---

## Deployment Commands

```bash
terraform init
terraform fmt
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

---

## Verification Commands

### Verify versioning

```bash
aws s3api get-bucket-versioning \
  --bucket ferdinand-enterprise-devops-tfstate-740994137090 \
  --profile personal-devops
```

Expected result:

```text
Enabled
```

### Verify encryption

```bash
aws s3api get-bucket-encryption \
  --bucket ferdinand-enterprise-devops-tfstate-740994137090 \
  --profile personal-devops
```

Expected encryption algorithm:

```text
AES256
```

### Verify public-access blocking

```bash
aws s3api get-public-access-block \
  --bucket ferdinand-enterprise-devops-tfstate-740994137090 \
  --profile personal-devops
```

All four public-access settings should return:

```text
True
```

---

## Files That Must Not Be Committed

The following generated or local files must remain excluded from Git:

```text
.terraform/
terraform.tfvars
terraform.tfstate
terraform.tfstate.backup
tfplan
*.tfplan
```

The following file should be committed:

```text
.terraform.lock.hcl
```

The lock file ensures that the project uses a consistent AWS provider version.

---

## Interview Summary

The backend was created separately because Terraform cannot use a remote backend before that backend exists.

The module first creates a secure S3 bucket using local state. The remaining infrastructure modules then use the bucket for centralised, encrypted and versioned remote state storage.

This removes the dependency on one laptop, protects Terraform's infrastructure record and allows authorised engineers or CI/CD systems to work with the same state.