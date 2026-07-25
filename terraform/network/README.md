# AWS Network Module

## Overview

This module provisions the foundational AWS networking infrastructure for the Enterprise DevOps Platform.

The network is designed using AWS networking best practices by separating internet-facing resources from internal workloads. It provides a secure, scalable and highly available environment that will host the Kubernetes cluster, Jenkins, monitoring stack and the Pet Adoption application.

This module stores its Terraform state remotely in Amazon S3 using the backend created during the bootstrap phase.

---

# Architecture

```
                              Internet
                                  │
                          Internet Gateway
                                  │
                  ┌───────────────┴───────────────┐
                  │                               │
          Public Subnet A                 Public Subnet B
                  │                               │
         Load Balancer / Jenkins        Future Public Services
                  │
          ┌───────┴────────┐
          │                │
  Private Subnet A   Private Subnet B
          │                │
 Kubernetes Nodes     Kubernetes Nodes
          │                │
      Pet Adoption Application
```

---

# Purpose

The objective of this module is to build the network foundation on which every other infrastructure component will depend.

The network provides:

- Isolation
- High Availability
- Scalability
- Secure communication
- Controlled internet access

Every resource created later in this project will be deployed inside this VPC.

---

# Resources Created

This module currently provisions:

- One Virtual Private Cloud (VPC)
- Two Public Subnets
- Two Private Subnets

Future updates will include:

- Internet Gateway
- Route Tables
- Route Table Associations
- NAT Gateway
- Elastic IP
- Network ACLs

---

# VPC Design

The VPC uses:

```
10.0.0.0/16
```

This private CIDR block provides 65,536 IP addresses.

Using a `/16` network allows future expansion without redesigning the network.

The VPC has:

- DNS Support Enabled
- DNS Hostnames Enabled

These settings are required for services such as EC2, Kubernetes, load balancers and internal service discovery.

---

# Availability Zones

The network spans two Availability Zones:

```
eu-west-3a
eu-west-3b
```

Using multiple Availability Zones improves fault tolerance.

If one Availability Zone experiences an outage, workloads can continue running in the other zone.

This is an example of High Availability (HA).

---

# Public Subnets

```
10.0.1.0/24
10.0.2.0/24
```

Public subnets automatically assign public IP addresses to launched instances.

These subnets will host resources that must communicate directly with the internet, including:

- Application Load Balancer
- NAT Gateway
- Jenkins (during this project)

Public subnets alone do not provide internet access.

They also require:

- Internet Gateway
- Route Table
- Route Table Association

---

# Private Subnets

```
10.0.11.0/24
10.0.12.0/24
```

Private subnets do not assign public IP addresses.

These subnets are intended for internal workloads such as:

- Kubernetes Worker Nodes
- Application Pods
- Databases
- Internal Services

Resources inside these subnets cannot be reached directly from the internet.

---

# Why Separate Public and Private Subnets?

Separating workloads improves security.

Internet-facing resources remain isolated from internal infrastructure.

If a public-facing server is compromised, private workloads remain protected behind additional networking controls.

This follows the principle of least exposure.

---

# High Availability

Resources are distributed across multiple Availability Zones.

Benefits include:

- Better fault tolerance
- Increased resilience
- Reduced downtime
- Improved production reliability

High Availability is a fundamental cloud design principle.

---

# Remote Terraform State

This module stores its Terraform state in the remote S3 backend created during the backend bootstrap phase.

State location:

```
network/terraform.tfstate
```

Using remote state provides:

- Centralised state management
- Better collaboration
- Encryption
- Versioning
- Protection against local machine failure

---

# Deployment Steps

```bash
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
```

---

# Verification

Verify the VPC:

```bash
aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=enterprise-devops-platform-vpc" \
  --profile personal-devops \
  --region eu-west-3
```

Verify the subnets:

```bash
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=<VPC_ID>" \
  --profile personal-devops \
  --region eu-west-3
```

---

# Cost Considerations

The following resources have no significant hourly running cost:

- VPC
- Subnets
- Route Tables
- Internet Gateway

Future resources that will incur charges include:

- NAT Gateway
- Load Balancer
- EC2 Instances
- Kubernetes Cluster

These resources will be destroyed when they are no longer required.

---

# Engineering Notes

## What I learned

- A VPC is an isolated virtual network inside AWS.
- Public subnets automatically assign public IP addresses.
- Private subnets do not assign public IP addresses.
- A subnet is not public simply because of its name; it requires an Internet Gateway and an appropriate Route Table.
- High Availability is achieved by distributing resources across multiple Availability Zones.
- Terraform remote state allows multiple modules to share a central source of truth.

---

# Interview Questions

### Why did you choose 10.0.0.0/16?

To provide sufficient IP address space for future expansion while maintaining a simple and scalable addressing scheme.

### Why are Kubernetes nodes deployed in private subnets?

To prevent direct internet access and improve the security of production workloads.

### Why use multiple Availability Zones?

To improve fault tolerance and ensure the platform remains available if one Availability Zone becomes unavailable.

### Why use a remote Terraform backend?

To provide secure, centralised, versioned and durable state management that can be shared by authorised engineers and CI/CD systems.