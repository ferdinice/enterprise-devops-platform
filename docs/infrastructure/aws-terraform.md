# AWS Infrastructure with Terraform

## 1. Purpose

Terraform is used to provision and manage the AWS infrastructure required by the Enterprise DevOps Platform.

The objective is to make the environment:

* repeatable
* version controlled
* auditable
* easy to recreate
* easy to destroy
* less dependent on manual AWS Console configuration

Infrastructure is divided into logical Terraform modules rather than being maintained in one large configuration.

---

## 2. Terraform Structure

The platform uses the following Terraform structure:

```text
terraform/
├── backend/
├── network/
├── iam/
├── ecr/
├── compute/
├── sonarqube/
└── kops/
```

Each directory has a specific responsibility.

This modular structure makes the infrastructure easier to understand, troubleshoot, and manage independently.

---

## 3. Remote State Backend

The `terraform/backend` module creates the infrastructure required to store Terraform state remotely.

The remote backend uses Amazon S3.

Remote state is important because Terraform needs a consistent record of the infrastructure it manages.

Using remote state provides:

* centralized state storage
* improved collaboration
* protection against losing local state
* easier recovery
* state versioning
* encryption

The S3 bucket is configured with:

* server-side encryption
* versioning
* public access blocking

Terraform locking is used to reduce the risk of multiple Terraform operations modifying the same state simultaneously.

---

## 4. Networking

The `terraform/network` module creates the AWS networking foundation used by the platform.

The network layer includes:

* VPC
* public subnets
* private subnets
* route tables
* Internet Gateway
* NAT Gateway
* Elastic IP
* security-group-related networking dependencies

The VPC provides an isolated network boundary for the platform.

Public subnets are used for components that require direct external connectivity.

Private subnets are used for workloads that should not be directly exposed to the internet.

---

## 5. Internet Gateway

The Internet Gateway provides internet connectivity for resources located in public subnets.

Traffic from public subnets can reach the internet when the corresponding route table contains a route such as:

```text
0.0.0.0/0
    |
    v
Internet Gateway
```

This is required for resources such as public-facing load balancers and other internet-accessible services.

---

## 6. NAT Gateway

The NAT Gateway allows resources in private subnets to initiate outbound internet connections without accepting unsolicited inbound traffic from the internet.

Typical examples include:

* downloading container images
* retrieving operating-system packages
* communicating with external APIs
* accessing external repositories

The flow is:

```text
Private Resource
      |
      v
Private Route Table
      |
      v
NAT Gateway
      |
      v
Internet Gateway
      |
      v
Internet
```

During project testing, NAT Gateway became one of the largest AWS cost contributors.

This demonstrated an important operational lesson: network architecture can cost more than expected even when application compute usage is relatively small.

---

## 7. IAM

The `terraform/iam` module creates the AWS identity used by the Jenkins EC2 instance.

The module provisions:

* a Jenkins IAM role trusted by the EC2 service
* an EC2 instance profile for attaching the role to the Jenkins server
* the AWS-managed `AmazonSSMManagedInstanceCore` policy
* a custom ECR policy for the Pet Adoption repository

The SSM policy allows the Jenkins EC2 instance to be managed through AWS Systems Manager without embedding AWS credentials into the server.

The custom ECR policy allows Jenkins to:

* authenticate to Amazon ECR
* inspect the Pet Adoption repository
* check image layers
* upload image layers
* push container manifests
* verify pushed images
* retrieve images when required

Repository-level ECR permissions are restricted to:

```text
arn:aws:ecr:eu-west-3:740994137090:repository/enterprise-devops-platform/pet-adoption
```

`ecr:GetAuthorizationToken` uses the wildcard resource because AWS requires that action to operate at account scope.

This provides a stronger least-privilege model than giving the Jenkins server broad ECR administrator permissions.


## 8. Amazon ECR

The `terraform/ecr` module creates the Elastic Container Registry repository used by the Pet Adoption application.

The CI pipeline builds Docker images and pushes them to ECR.

Example image:

```text
740994137090.dkr.ecr.eu-west-3.amazonaws.com/enterprise-devops-platform/pet-adoption:build-2-4dad0b1
```

The image tag contains:

* Jenkins build number
* short Git commit SHA

This creates traceability between source code and the deployed container.

ECR acts as the boundary between CI and deployment.

Jenkins creates the artifact.

ArgoCD later deploys that already-built artifact.

---

## 9. Jenkins Compute Infrastructure

The `terraform/compute` module provisions the EC2 infrastructure used for Jenkins.

Jenkins performs the application CI workflow, including:

* checkout
* build
* testing
* code analysis integration
* vulnerability scanning
* container creation
* ECR push
* GitOps manifest update

Jenkins is deployed separately from the Kubernetes cluster in this portfolio implementation.

This separation prevents the CI system from depending on the Kubernetes environment it is responsible for delivering workloads into.

---

## 10. SonarQube Infrastructure

The `terraform/sonarqube` module provisions a dedicated SonarQube EC2 instance.

SonarQube performs static code-quality analysis.

Jenkins communicates with SonarQube during CI.

The pipeline does not proceed blindly after analysis.

A SonarQube Quality Gate is checked before later deployment stages continue.

This creates a quality-control boundary in the pipeline.

---

## 11. KOps Infrastructure

The Kubernetes cluster is managed through the `terraform/kops` area and KOps lifecycle scripts.

KOps creates and manages AWS resources required by Kubernetes.

These include resources such as:

* EC2 control-plane nodes
* EC2 worker nodes
* security groups
* Auto Scaling Groups
* load balancers
* IAM resources
* DNS-related cluster records
* EBS volumes

KOps stores cluster configuration and state so the Kubernetes environment can be recreated and updated.

---

## 12. Terraform Execution Pattern

A typical Terraform module workflow is:

```text
terraform init
      |
      v
terraform validate
      |
      v
terraform plan
      |
      v
review changes
      |
      v
terraform apply
```

Each step serves a different purpose.

### terraform init

Initializes the working directory and downloads required providers and backend configuration.

### terraform validate

Checks the configuration for syntax and structural validity.

### terraform plan

Shows the infrastructure changes Terraform intends to make.

### terraform apply

Applies the approved infrastructure changes.

---

## 13. Why Plan Review Matters

The Terraform plan is reviewed before applying infrastructure changes.

This helps detect:

* accidental resource deletion
* unexpected replacement
* incorrect regions
* wrong subnet selection
* unwanted security-group changes
* unexpected cost-generating resources

Blindly running `terraform apply` without reviewing the plan is avoided.

---

## 14. Terraform State Security

Terraform state is not committed to the Git repository.

Files such as the following are excluded:

```text
*.tfstate
*.tfstate.*
*.tfvars
tfplan
```

This reduces the risk of exposing:

* infrastructure identifiers
* configuration values
* sensitive values
* credentials or secrets accidentally stored in state

The repository contains reusable Terraform configuration, while operational state remains external.

---

## 15. Infrastructure Lifecycle

The platform is designed to be temporary and reproducible.

The lifecycle is:

```text
Provision
    |
    v
Validate
    |
    v
Test
    |
    v
Capture Evidence
    |
    v
Destroy
```

The infrastructure can therefore be recreated when required rather than being left running continuously.

---

## 16. Cost Considerations

During platform testing, the main AWS cost contributors included:

* NAT Gateway
* EC2
* Load Balancers
* EBS
* Public IPv4 addresses
* Route 53

The NAT Gateway was particularly significant because cost came from both:

* hourly runtime
* processed data

This led to a cost-aware operating model in which the environment is destroyed after testing.

Persistent low-cost resources, such as selected S3 and Route 53 configuration, can remain where required.

---

## 17. Failure and Recovery Considerations

Terraform provides a repeatable path for recovering infrastructure.

If a resource is accidentally deleted outside Terraform, the next plan can identify the difference between desired configuration and actual infrastructure.

If Terraform state is protected using remote storage and versioning, recovery is easier than relying on a single local state file.

This reinforces why both Infrastructure as Code and remote state management are important parts of the platform.

---

## 18. Terraform Design Summary

Terraform provides the infrastructure foundation for the platform.

Its responsibilities include:

```text
Remote State
    |
Networking
    |
IAM
    |
ECR
    |
Jenkins
    |
SonarQube
    |
KOps Infrastructure
```

The modular approach makes the platform easier to recreate, audit, explain, and troubleshoot.

Terraform is therefore responsible for establishing the AWS environment on which the Kubernetes and DevOps platform services operate.
