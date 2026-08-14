# Enterprise DevOps Platform Deployment Runbook

## 1. Purpose

This runbook describes the operational procedure for deploying, validating, promoting applications through, and destroying the Enterprise DevOps Platform.

The objective is to make platform deployment repeatable rather than dependent on manual AWS Console configuration or undocumented engineer knowledge.

The high-level lifecycle is:

```text
Prepare
   |
   v
Provision AWS Foundation
   |
   v
Provision Supporting Services
   |
   v
Create Kubernetes Cluster
   |
   v
Install Platform Services
   |
   v
Validate Platform
   |
   v
Run CI Pipeline
   |
   v
Deploy Development
   |
   v
Promote to Staging
   |
   v
Promote to Production
   |
   v
Capture Evidence / Operate
   |
   v
Destroy Temporary Environment
```

---

## 2. Repository Responsibilities

Two repositories participate in the delivery workflow.

### Application Repository

```text
pet-adoption-devops
```

Responsibilities:

* application source
* Maven build
* automated tests
* Dockerfile
* Jenkinsfile
* SonarQube integration
* Trivy scanning
* ECR publishing
* Development GitOps update

### Platform Repository

```text
enterprise-devops-platform
```

Responsibilities:

* Terraform
* AWS infrastructure
* KOps
* Kubernetes configuration
* NGINX
* cert-manager
* DNS
* ArgoCD
* GitOps desired state
* Dev/Staging/Prod overlays
* monitoring
* promotion scripts
* deployment automation
* destruction automation
* documentation

---

# Prerequisites

## 3. Local Tooling

The deployment workstation requires the platform tooling used by the repository.

Typical tools include:

```text
AWS CLI
Terraform
kubectl
KOps
Helm
Git
Bash
```

The required tools should be available in `PATH`.

Before starting, verify the basic commands:

```bash
aws --version
terraform version
kubectl version --client
kops version
helm version
git --version
```

---

## 4. AWS Authentication

The project uses the AWS CLI profile:

```text
personal-devops
```

Confirm authentication before provisioning infrastructure:

```bash
aws sts get-caller-identity \
  --profile personal-devops
```

The returned AWS account should match the account intended for the platform.

Do not proceed if the active account is incorrect.

---

## 5. Region

The platform uses:

```text
eu-west-3
```

for the primary project infrastructure.

Terraform backend configuration and other platform configuration should remain aligned with the intended AWS region.

---

# Terraform Remote State

## 6. Backend Foundation

The Terraform backend is created before the modules that depend on remote state.

Navigate to:

```bash
cd terraform/backend
```

Typical workflow:

```bash
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply
```

The backend creates the S3 bucket used for Terraform state.

The bucket includes:

* versioning
* AES256 server-side encryption
* public-access blocking
* `prevent_destroy`

The remaining Terraform modules use S3 remote state with native S3 locking through:

```text
use_lockfile = true
```

---

## 7. Why Backend Comes First

Modules such as:

```text
network
iam
ecr
compute
sonarqube
```

reference the S3 backend.

Therefore:

```text
Backend Storage
      |
      v
Other Terraform Modules
```

is a dependency relationship.

The state backend cannot be treated as an afterthought.

---

# Network

## 8. Provision Networking

Navigate to:

```bash
cd terraform/network
```

Run:

```bash
terraform init -reconfigure
terraform fmt -check
terraform validate
terraform plan
```

Review the plan carefully.

When correct:

```bash
terraform apply
```

The network module provisions the platform networking foundation, including:

* VPC
* public subnets
* private subnets
* Internet Gateway
* route tables
* Elastic IP
* NAT Gateway

---

## 9. Network Validation

After deployment, confirm the expected Terraform outputs and inspect AWS resources where necessary.

Important questions include:

* Does the VPC exist?
* Are the expected public/private subnets present?
* Is the Internet Gateway attached?
* Is the NAT Gateway available?
* Do route tables reference the intended gateways?

---

# IAM

## 10. Provision Jenkins IAM

Navigate to:

```bash
cd terraform/iam
```

Run:

```bash
terraform init -reconfigure
terraform validate
terraform plan
terraform apply
```

The module creates the Jenkins EC2 IAM role and instance profile.

It includes:

* SSM permissions
* ECR authentication
* repository-scoped ECR permissions

---

# Amazon ECR

## 11. Provision Container Registry

Navigate to:

```bash
cd terraform/ecr
```

Run:

```bash
terraform init -reconfigure
terraform validate
terraform plan
terraform apply
```

The ECR repository is configured with immutable image tags.

Confirm the repository exists before expecting Jenkins to publish container images.

---

# Jenkins Infrastructure

## 12. Provision Jenkins

Navigate to:

```bash
cd terraform/compute
```

Run:

```bash
terraform init -reconfigure
terraform validate
terraform plan
terraform apply
```

After provisioning, validate that the Jenkins EC2 instance can operate correctly.

Important checks include:

* EC2 instance running
* IAM instance profile attached
* SSM connectivity
* Jenkins service running
* required build tools available
* AWS CLI access through the instance role
* Docker operational

---

# SonarQube Infrastructure

## 13. Provision SonarQube

Navigate to:

```bash
cd terraform/sonarqube
```

Run:

```bash
terraform init -reconfigure
terraform validate
terraform plan
terraform apply
```

Verify the SonarQube instance and service before expecting Jenkins analysis stages to work.

The current pipeline performs SonarQube analysis.

The Jenkins Quality Gate stage currently remains disabled because the webhook-based Quality Gate integration has not yet been completed.

---

# Kubernetes

## 14. KOps Configuration

KOps-related files are maintained under:

```text
terraform/kops/
```

Important files include:

```text
config/cluster.yaml
config/instance-groups.yaml

create-cluster.sh
validate-cluster.sh
export-kubeconfig.sh
update-cluster.sh
rolling-update.sh
delete-cluster.sh
verify-cleanup.sh
```

---

## 15. Create Kubernetes Cluster

Use the project cluster creation workflow:

```bash
./terraform/kops/create-cluster.sh
```

Do not immediately begin installing platform components.

First validate Kubernetes itself.

---

## 16. Export kubeconfig

If required:

```bash
./terraform/kops/export-kubeconfig.sh
```

Then verify API access:

```bash
kubectl cluster-info
kubectl get nodes
```

All required nodes should become Ready.

---

## 17. Validate Cluster

Run:

```bash
./terraform/kops/validate-cluster.sh
```

The Kubernetes foundation should be healthy before proceeding.

A broken cluster should be fixed at the cluster layer rather than hidden by installing higher-level platform services on top of it.

---

# Complete Platform Deployment

## 18. Top-Level Deployment

Return to the repository root:

```bash
cd /c/DevOps-Lab/enterprise-devops-platform
```

Run:

```bash
./deploy-platform.sh
```

The script orchestrates the core platform rather than requiring each platform component to be installed manually.

The implemented workflow includes:

```text
KOps configuration / cluster readiness
            |
            v
NGINX Ingress Controller
            |
            v
Pet Adoption workload
            |
            v
Pet Adoption DNS
            |
            v
cert-manager
            |
            v
Let's Encrypt Production ClusterIssuer
            |
            v
Pet Adoption TLS Certificate
            |
            v
ArgoCD DNS
            |
            v
ArgoCD
            |
            v
ArgoCD TLS + Verification
            |
            v
Monitoring Stack
            |
            v
Grafana + Prometheus DNS
            |
            v
Monitoring TLS
            |
            v
Monitoring Verification
```

---

## 19. Why the Top-Level Script Matters

Without orchestration, an engineer would need to remember a long sequence of component-specific commands.

The top-level script turns the deployment process into a reproducible workflow.

Individual scripts remain available for troubleshooting and component-specific operations.

---

# NGINX

## 20. Ingress Verification

The deployment process installs and verifies the NGINX Ingress Controller.

The controller provides the shared public application routing layer.

Useful manual checks include:

```bash
kubectl get ingressclass

kubectl get pods \
  -n ingress-nginx

kubectl get svc \
  -n ingress-nginx
```

---

# cert-manager

## 21. Certificate Infrastructure

The platform installs cert-manager and validates the production ClusterIssuer.

Useful manual checks:

```bash
kubectl get clusterissuer

kubectl get certificate -A
```

The expected production issuer should reach:

```text
Ready=True
```

before relying on production TLS certificates.

---

# DNS and TLS

## 22. DNS Validation

DNS is managed using the repository scripts under:

```text
platform/dns/
```

The platform deployment verifies required records.

Manual DNS verification can also be performed using:

```bash
./platform/dns/verify-dns.sh <hostname>
```

The exact hostname should resolve toward the ingress infrastructure.

---

## 23. TLS Validation

Certificate readiness should be verified rather than assuming that an Ingress annotation automatically guarantees TLS.

Useful checks:

```bash
kubectl get certificate -A
kubectl get challenge -A
kubectl get order -A
```

If certificate issuance fails, investigate:

```text
DNS
Ingress
ClusterIssuer
Certificate
Order
Challenge
```

rather than repeatedly reinstalling cert-manager.

---

# ArgoCD

## 24. ArgoCD Installation

ArgoCD is installed by the top-level platform deployment using:

```text
platform/argocd/install.sh
```

After installation, the platform verifies ArgoCD.

The public endpoint is:

```text
https://argocd.ferdeve.fit
```

---

## 25. ArgoCD Applications

The platform defines three application environments:

```text
pet-adoption-dev
pet-adoption-staging
pet-adoption-prod
```

Their definitions live under:

```text
gitops/applications/
```

and point to:

```text
gitops/pet-adoption/overlays/dev
gitops/pet-adoption/overlays/staging
gitops/pet-adoption/overlays/prod
```

---

## 26. Environment Namespaces

The expected namespaces are:

```text
pet-adoption-dev
pet-adoption-staging
pet-adoption-prod
```

Useful verification:

```bash
kubectl get namespaces
```

and:

```bash
kubectl get applications \
  -n argocd
```

---

# Monitoring

## 27. Monitoring Installation

Monitoring is now integrated into:

```bash
./deploy-platform.sh
```

A separate manual monitoring installation should not normally be required during a normal full-platform deployment.

The underlying component script remains:

```text
platform/monitoring/install.sh
```

for troubleshooting and independent component testing.

---

## 28. Monitoring Endpoints

After successful deployment, verify:

```text
https://grafana.ferdeve.fit

https://prometheus.ferdeve.fit
```

TLS certificates should be ready.

---

## 29. Monitoring Verification

The deployment invokes:

```text
platform/monitoring/verify.sh
```

The verification checks areas including:

* Helm release
* monitoring Pods
* Prometheus
* Grafana service
* Grafana ingress
* Prometheus ingress
* TLS Secrets
* kube-state-metrics
* node-exporter
* Alertmanager
* Slack Secret
* custom PrometheusRule

A successful deployment should not be considered complete if monitoring verification fails.

---

# CI Workflow

## 30. Trigger Jenkins Pipeline

After platform prerequisites are available, run the Pet Adoption Jenkins pipeline from the application repository configuration.

The pipeline performs:

```text
Checkout
→ Java verification
→ Maven build/test
→ SonarQube analysis
→ artifact verification
→ artifact archive
→ Docker build
→ Trivy scan
→ ECR push
→ ECR verification
→ Dev GitOps update
```

---

## 31. Verify ECR Artifact

The Jenkins pipeline verifies the image automatically.

Manual verification is also possible using:

```bash
aws ecr describe-images \
  --repository-name enterprise-devops-platform/pet-adoption \
  --region eu-west-3 \
  --profile personal-devops
```

The expected build tag should be present.

---

# Development

## 32. Development Deployment

Jenkins modifies only:

```text
gitops/pet-adoption/overlays/dev/kustomization.yaml
```

ArgoCD Development synchronization is automated.

Verify:

```bash
kubectl get application pet-adoption-dev \
  -n argocd
```

The desired result is:

```text
Synced
Healthy
```

Also inspect:

```bash
kubectl get deployment,pods,service,ingress \
  -n pet-adoption-dev
```

---

## 33. Development Endpoint

The Development endpoint is:

```text
https://dev.petadoption.ferdeve.fit
```

Validate the actual application before promoting the image.

A successful CI pipeline alone is not sufficient evidence that the application behaves correctly after deployment.

---

# Staging Promotion

## 34. Promote the Tested Artifact

After Development validation:

```bash
./scripts/promote-to-staging.sh
```

The script copies the Development image tag into the Staging overlay.

It does not rebuild the image.

---

## 35. Commit Staging Promotion

The promotion script changes Git desired state locally.

The resulting change must be reviewed and committed.

Example workflow:

```bash
git diff

git add \
  gitops/pet-adoption/overlays/staging/kustomization.yaml

git commit -m "Promote pet-adoption to staging"

git push origin main
```

ArgoCD Staging uses automated synchronization.

---

## 36. Validate Staging

Verify:

```bash
kubectl get application pet-adoption-staging \
  -n argocd
```

Then:

```bash
kubectl get deployment,pods,service,ingress \
  -n pet-adoption-staging
```

The Staging endpoint is:

```text
https://staging.petadoption.ferdeve.fit
```

The same immutable image that passed Development should now be running in Staging.

---

# Production Promotion

## 37. Production Candidate

After Staging validation:

```bash
./scripts/promote-to-prod.sh
```

The script displays the image currently referenced by Staging.

To continue, the operator must type:

```text
PROMOTE
```

This updates the Production desired-state image tag.

---

## 38. Commit Production Promotion

Review:

```bash
git diff
```

Then commit the Production desired-state change:

```bash
git add \
  gitops/pet-adoption/overlays/prod/kustomization.yaml

git commit -m "Promote pet-adoption to production"

git push origin main
```

---

## 39. Production Does Not Auto-Sync

The Production ArgoCD Application intentionally does not use automated synchronization.

Therefore the Git change should make Production:

```text
OutOfSync
```

rather than immediately deploying it.

This is expected.

---

## 40. Production Approval

After final review, synchronize Production explicitly through the approved ArgoCD workflow.

The intended deployment boundary is:

```text
Production Git change
        |
        v
ArgoCD OutOfSync
        |
        v
Final approval
        |
        v
Manual synchronization
        |
        v
Production deployment
```

---

## 41. Production Verification

Verify:

```bash
kubectl get application pet-adoption-prod \
  -n argocd
```

After synchronization the target state is:

```text
Synced
Healthy
```

Then verify:

```bash
kubectl get deployment,pods,service,ingress \
  -n pet-adoption-prod
```

Production is configured with two application replicas.

---

## 42. Production Endpoint

Verify:

```text
https://petadoption.ferdeve.fit
```

A deployment is not complete until actual application access and functionality have been validated.

---

# Artifact Consistency

## 43. Confirm Same Image Across Environments

During promotion testing, inspect the image deployed into each environment.

Example:

```bash
kubectl get deployment pet-adoption \
  -n pet-adoption-dev \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'

kubectl get deployment pet-adoption \
  -n pet-adoption-staging \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'

kubectl get deployment pet-adoption \
  -n pet-adoption-prod \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

After complete promotion, all three should reference the intended immutable image.

This proves:

```text
Build once
→ Promote
→ Promote
```

rather than rebuilding per environment.

---

# Observability Validation

## 44. Grafana

Open:

```text
https://grafana.ferdeve.fit
```

Validate that Kubernetes metrics are visible.

Useful areas include:

* cluster CPU
* memory
* namespace metrics
* Pod metrics
* node metrics

---

## 45. Prometheus

Open:

```text
https://prometheus.ferdeve.fit
```

Verify Prometheus is collecting data and alert rules are loaded.

---

## 46. Alertmanager / Slack

Confirm operational alerting through:

```text
Prometheus
→ Alertmanager
→ #devops-alerts
```

The platform has previously validated both:

```text
FIRING
RESOLVED
```

notification states.

A controlled alert test may be repeated during final end-to-end validation if required.

---

# Troubleshooting Rule

## 47. Troubleshoot the Correct Layer

Do not randomly reinstall components.

Identify the layer that failed.

For example:

```text
Application unreachable
```

does not automatically mean the application Pod is broken.

Investigate progressively:

```text
DNS
→ Load Balancer
→ Ingress
→ Service
→ Pod
→ Application
```

Likewise:

```text
Slack alert missing
```

should be investigated through:

```text
Prometheus rule
→ Prometheus alert state
→ Alertmanager
→ Secret
→ Slack webhook
```

Layered troubleshooting reduces wasted changes.

---

# Destruction

## 48. Why Destruction Matters

The project runs real AWS resources.

Leaving a portfolio environment running after testing generates unnecessary cost.

Important cost-generating resources include:

* EC2
* NAT Gateway
* Load Balancer
* public IPv4 addresses
* EBS

---

## 49. Destroy the Platform

From the platform repository root:

```bash
./destroy-platform.sh
```

The workflow requires explicit confirmation:

```text
DESTROY-PLATFORM
```

---

## 50. Destruction Order

The teardown includes the reverse dependency flow:

```text
Grafana DNS
→ Prometheus DNS
→ Monitoring
→ ArgoCD DNS
→ ArgoCD
→ Pet Adoption DNS
→ cert-manager
→ NGINX Ingress
→ KOps cluster
→ AWS cleanup verification
```

The script tracks cleanup failures instead of silently ignoring them.

---

## 51. Verify AWS Cleanup

The destruction process uses:

```text
terraform/kops/verify-cleanup.sh
```

to detect remaining AWS cluster resources.

Additional manual cost checks can be performed where required.

The goal is not merely:

```text
kubectl no longer works
```

The goal is:

```text
billable infrastructure has actually been removed.
```

---

# Operational Checklist

## 52. Deployment Checklist

* [ ] Confirm correct AWS account.
* [ ] Confirm `personal-devops` AWS profile works.
* [ ] Confirm required CLI tools.
* [ ] Confirm Terraform backend.
* [ ] Validate and provision networking.
* [ ] Validate and provision IAM.
* [ ] Validate and provision ECR.
* [ ] Provision Jenkins.
* [ ] Provision SonarQube.
* [ ] Create KOps cluster.
* [ ] Export kubeconfig.
* [ ] Validate Kubernetes cluster.
* [ ] Run `deploy-platform.sh`.
* [ ] Verify NGINX.
* [ ] Verify cert-manager.
* [ ] Verify DNS/TLS.
* [ ] Verify ArgoCD.
* [ ] Verify monitoring.
* [ ] Trigger Jenkins CI.
* [ ] Confirm ECR image.
* [ ] Confirm Development.
* [ ] Validate Development.
* [ ] Promote to Staging.
* [ ] Validate Staging.
* [ ] Promote to Production.
* [ ] Manually synchronize Production.
* [ ] Validate Production.
* [ ] Confirm same immutable artifact across environments.
* [ ] Confirm monitoring visibility.
* [ ] Capture final evidence.

---

## 53. Teardown Checklist

* [ ] Confirm testing is finished.
* [ ] Preserve required screenshots/evidence.
* [ ] Run `destroy-platform.sh`.
* [ ] Confirm monitoring removed.
* [ ] Confirm ArgoCD removed.
* [ ] Confirm NGINX removed.
* [ ] Confirm KOps deletion completed.
* [ ] Run AWS cleanup verification.
* [ ] Check for remaining EC2 instances.
* [ ] Check NAT Gateways.
* [ ] Check Load Balancers.
* [ ] Check public IPv4 addresses.
* [ ] Check EBS volumes.
* [ ] Review AWS cost/budget dashboard if necessary.

---

# 54. Runbook Summary

The deployment runbook follows a controlled progression:

```text
AWS Foundation
      |
      v
Kubernetes
      |
      v
Platform Services
      |
      v
CI Artifact
      |
      v
Development
      |
      v
Staging
      |
      v
Production
      |
      v
Observability
      |
      v
Evidence
      |
      v
Controlled Teardown
```

The key operating principles are:

* provision through code
* validate every layer
* build artifacts once
* deploy through GitOps
* promote rather than rebuild
* require explicit production control
* monitor the running platform
* troubleshoot by layer
* destroy unnecessary cloud infrastructure when testing ends

This provides a repeatable operational procedure for taking the platform from source code and infrastructure definitions to a validated multi-environment Kubernetes deployment.
