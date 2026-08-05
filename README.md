# Enterprise DevOps Platform

## Project Overview

The Enterprise DevOps Platform is a production-inspired DevOps project that demonstrates the design, automation, security, and deployment of a modern cloud-native application using AWS, Terraform, Jenkins, Docker, SonarQube, Trivy, Kubernetes (KOps), ArgoCD, and GitOps.

The project is being built incrementally to simulate how enterprise engineering teams provision infrastructure, implement CI/CD pipelines, deploy applications to Kubernetes, and operate production workloads securely.

---

# Objectives

- Provision cloud infrastructure using Infrastructure as Code (Terraform)
- Implement an enterprise Continuous Integration (CI) pipeline
- Build immutable Docker images
- Perform automated code quality analysis
- Perform automated container vulnerability scanning
- Store trusted images in Amazon Elastic Container Registry (ECR)
- Deploy applications to Kubernetes using KOps
- Implement GitOps with ArgoCD
- Secure workloads with HTTPS and Ingress
- Implement monitoring and observability

---

# Current Project Status

| Phase | Status |
|---------|:------:|
| Terraform Remote Backend | ✅ Complete |
| Networking | ✅ Complete |
| IAM | ✅ Complete |
| Jenkins Infrastructure | ✅ Complete |
| SonarQube Infrastructure | ✅ Complete |
| Amazon ECR | ✅ Complete |
| CI Pipeline | ✅ Complete |
| Docker Image Build | ✅ Complete |
| Trivy Security Scan | ✅ Complete |
| Push Image to Amazon ECR | ✅ Complete |
| KOps Kubernetes Cluster | 🚧 In Progress |
| Application Deployment | ⏳ Pending |
| ArgoCD GitOps | ⏳ Pending |
| Monitoring | ⏳ Pending |

---

# Architecture

```
Developer
     │
     ▼
 GitHub Repository
     │
     ▼
 Jenkins CI Pipeline
     │
     ├──────── Build & Test (Maven)
     │
     ├──────── SonarQube Analysis
     │
     ├──────── Quality Gate
     │
     ├──────── Docker Build
     │
     ├──────── Trivy Scan
     │
     ▼
 Amazon Elastic Container Registry (ECR)
     │
     ▼
 Kubernetes (KOps)
     │
     ▼
 ArgoCD GitOps
     │
     ▼
 Pet Adoption Application
```

---

# Technology Stack

## Cloud

- AWS EC2
- Amazon ECR
- Amazon S3
- Amazon Route 53
- IAM

## Infrastructure as Code

- Terraform

## CI/CD

- Jenkins
- SonarQube
- Trivy

## Containerization

- Docker

## Orchestration

- Kubernetes
- KOps
- ArgoCD

## Application

- Java
- Maven
- Spring Boot

---

# Repository Structure

```
enterprise-devops-platform/

├── docs/
├── diagrams/
├── terraform/
│   ├── backend/
│   ├── network/
│   ├── iam/
│   ├── compute/
│   ├── sonarqube/
│   ├── ecr/
│   └── kops/
│
├── kubernetes/
├── monitoring/
├── scripts/
└── README.md
```

---

# Continuous Integration Features

- Automated GitHub checkout
- Maven build and testing
- SonarQube static code analysis
- Quality Gate enforcement
- Docker image creation
- Trivy vulnerability scanning
- Immutable Docker image tagging
- Amazon ECR publishing
- Build artifact archiving

---

# Security

The project follows several security best practices:

- Infrastructure provisioned using Terraform
- IAM Roles instead of long-lived AWS credentials
- Least Privilege access model
- Immutable Docker image tags
- SonarQube Quality Gates
- Container vulnerability scanning using Trivy
- Private Amazon ECR repository

---

# Documentation

Project documentation is organized under the `docs/` directory.

Topics include:

- Architecture
- CI Pipeline
- Infrastructure
- Operations
- Troubleshooting
- Interview Notes

---

# Future Enhancements

- Kubernetes deployment using KOps
- GitOps using ArgoCD
- NGINX Ingress Controller
- HTTPS using Let's Encrypt
- Prometheus
- Grafana
- Loki
- Kiali
- Service Mesh
- Multi-environment deployments
- Disaster Recovery

---

# Skills Demonstrated

- Infrastructure as Code
- AWS Cloud Engineering
- CI/CD Pipeline Design
- Containerization
- DevSecOps
- Kubernetes
- GitOps
- Cloud Security
- Linux Administration
- Infrastructure Automation
- Troubleshooting
- Production Deployment Strategies

---

# Author

**Ferdinand Anayo Ngaobiwu**

Enterprise DevOps Platform Portfolio Project

Built as part of my DevOps engineering journey to demonstrate practical cloud infrastructure automation, CI/CD implementation, Kubernetes deployment, GitOps, and production operations.

---

## License

This repository is intended for educational purposes and professional portfolio demonstration.