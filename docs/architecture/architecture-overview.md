# Enterprise DevOps Platform Architecture Overview

## 1. Purpose

The Enterprise DevOps Platform is a portfolio-grade cloud-native delivery platform designed to demonstrate an end-to-end DevOps workflow on AWS.

The platform combines:

* Infrastructure as Code with Terraform
* Kubernetes cluster provisioning with KOps
* CI with Jenkins
* Code quality analysis with SonarQube
* Container security scanning with Trivy
* Container image storage with Amazon ECR
* GitOps delivery with ArgoCD
* Multi-environment promotion across Dev, Staging, and Production
* NGINX Ingress for application routing
* cert-manager and Let's Encrypt for TLS
* Route 53 for DNS
* Prometheus for metrics collection
* Grafana for visualization
* Alertmanager for alert routing
* Slack for operational notifications

The objective is not only to deploy an application, but to build a platform that demonstrates repeatability, security, observability, controlled promotion, and operational automation.

---

## 2. High-Level Architecture

The platform is divided into four major layers:

1. Infrastructure layer
2. Kubernetes platform layer
3. CI/CD and GitOps layer
4. Observability layer

The application delivery flow is:

```text
Developer
   |
   v
Application Git Repository
   |
   v
Jenkins CI Pipeline
   |
   +--> Maven Build and Tests
   |
   +--> SonarQube Analysis
   |
   +--> Trivy Image Scan
   |
   v
Amazon ECR
   |
   v
Immutable Container Image
   |
   v
GitOps Configuration
   |
   v
ArgoCD
   |
   +--> Development
   |
   +--> Staging
   |
   +--> Production
```

---

## 3. Infrastructure Layer

AWS infrastructure is provisioned using Terraform.

The Terraform configuration manages components such as:

* Remote Terraform state
* Networking
* IAM
* Amazon ECR
* Jenkins infrastructure
* SonarQube infrastructure
* KOps-related infrastructure

Terraform remote state is stored in Amazon S3 with state locking to prevent concurrent state modification.

The infrastructure design allows resources to be created and destroyed repeatedly, which is useful for a temporary portfolio environment where cost control is important.

---

## 4. Kubernetes Layer

The Kubernetes cluster is provisioned using KOps on AWS.

KOps manages the Kubernetes control-plane and worker-node infrastructure.

The cluster hosts the application platform components, including:

* NGINX Ingress Controller
* cert-manager
* ArgoCD
* Prometheus
* Grafana
* Alertmanager
* Pet Adoption application workloads

The platform uses namespaces to separate deployment environments.

```text
pet-adoption-dev
pet-adoption-staging
pet-adoption-prod
```

This provides logical isolation without requiring three separate Kubernetes clusters.

---

## 5. Continuous Integration

The application source code is stored in the separate `pet-adoption-devops` repository.

Jenkins is responsible for the CI workflow.

The pipeline performs:

1. Source code checkout
2. Build environment verification
3. Maven build and automated tests
4. SonarQube analysis
5. SonarQube Quality Gate validation
6. WAR artifact validation
7. Artifact archiving
8. Docker image build
9. Trivy vulnerability scanning
10. ECR authentication
11. Image push to ECR
12. ECR image verification
13. GitOps repository update

Container images use immutable tags containing both the Jenkins build number and the short Git commit SHA.

Example:

```text
build-2-4dad0b1
```

This allows the running Kubernetes workload to be traced back to the exact source-code commit that produced it.

---

## 6. GitOps and ArgoCD

The desired Kubernetes application state is stored inside:

```text
enterprise-devops-platform/gitops/
```

The GitOps structure contains:

```text
gitops/
├── applications/
└── pet-adoption/
    ├── base/
    └── overlays/
        ├── dev/
        ├── staging/
        └── prod/
```

ArgoCD continuously compares the desired state stored in Git with the actual state in Kubernetes.

Development and staging use automated synchronization.

Production does not use automated synchronization.

This creates an explicit production deployment boundary.

---

## 7. Environment Promotion Strategy

The platform follows a build-once, promote-many model.

A container image is built only once by Jenkins.

The same immutable image is then promoted through:

```text
DEV
 |
 v
STAGING
 |
 v
PRODUCTION
```

Jenkins automatically updates only the Dev GitOps manifest.

The staging promotion script reads the current Dev image tag and updates Staging with the exact same tag.

The production promotion script reads the Staging image tag and requires explicit confirmation before updating Production.

This prevents different application binaries from being built for different environments.

The artifact tested in Dev and Staging is the exact artifact promoted to Production.

---

## 8. Traffic Flow

External application traffic follows this path:

```text
User
 |
 v
Route 53 DNS
 |
 v
AWS Load Balancer
 |
 v
NGINX Ingress Controller
 |
 v
Kubernetes Ingress
 |
 v
Kubernetes Service
 |
 v
Pet Adoption Pod
```

Each environment has its own hostname.

```text
Dev:
dev.petadoption.ferdeve.fit

Staging:
staging.petadoption.ferdeve.fit

Production:
petadoption.ferdeve.fit
```

TLS certificates are issued automatically using cert-manager and Let's Encrypt.

---

## 9. Monitoring and Observability

The monitoring stack uses `kube-prometheus-stack`.

The stack contains:

* Prometheus
* Grafana
* Prometheus Operator
* kube-state-metrics
* node-exporter
* Alertmanager

Prometheus collects cluster and workload metrics.

Node Exporter provides host-level metrics such as CPU, memory, disk, and network usage.

kube-state-metrics exposes Kubernetes object state such as Deployment replicas and Pod health.

Grafana uses Prometheus as a data source to visualize the collected metrics.

---

## 10. Alerting

Prometheus evaluates alert rules using PrometheusRule resources.

Two custom platform alerts were added:

* Deployment unavailable
* High node CPU utilization

When an alert becomes active:

```text
Kubernetes problem
   |
   v
Metric exposed
   |
   v
Prometheus
   |
   v
PrometheusRule
   |
   v
Alertmanager
   |
   v
Slack
```

The alerting workflow was tested by deliberately creating an unavailable Kubernetes Deployment.

The alert moved through:

```text
Pending
→ Firing
→ Slack notification
→ Resolved
→ Slack resolved notification
```

This verified the complete monitoring and alerting path.

---

## 11. Security Considerations

The platform avoids storing operational secrets directly in Git.

Examples include:

* GitHub credentials stored in Jenkins Credentials
* SonarQube token stored in Jenkins Credentials
* Slack webhook stored as a Kubernetes Secret
* Terraform local variable files excluded from Git
* Terraform state excluded from source control
* Remote Terraform state stored in S3

Public endpoints use HTTPS.

cert-manager automates certificate issuance and renewal.

---

## 12. Automation

The platform includes automation scripts for:

* Full platform deployment
* Full platform destruction
* KOps lifecycle management
* NGINX installation and verification
* cert-manager installation and verification
* DNS creation and deletion
* ArgoCD installation and bootstrap
* Monitoring installation and verification
* Dev-to-Staging promotion
* Staging-to-Production promotion

The objective is to make the platform repeatable rather than dependent on manual console configuration.

---

## 13. Cost-Aware Design

The environment is designed as a temporary portfolio platform rather than a permanently running production system.

Expensive AWS resources are destroyed when testing is complete.

Major cost drivers identified during testing included:

* NAT Gateway
* EC2 instances
* Load Balancers
* EBS storage
* Public IPv4 addresses

This led to an operational approach of:

```text
Deploy
→ Test
→ Capture Evidence
→ Destroy
```

This reduces unnecessary AWS spend while still allowing full end-to-end testing.

---

## 14. Final Architecture Summary

The completed platform demonstrates:

* Infrastructure provisioning
* Kubernetes operations
* CI automation
* code-quality enforcement
* container security scanning
* immutable artifact management
* GitOps delivery
* multi-environment promotion
* production approval control
* TLS and DNS automation
* metrics collection
* dashboard visualization
* alert routing
* failure testing
* cost-aware operations

The final architecture provides a realistic demonstration of how a DevOps engineer can move application code from source control through automated validation and into a controlled Kubernetes production environment.
