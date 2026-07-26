# AWS Network Module

## Overview

The Network module provisions the foundational AWS networking infrastructure for the Enterprise DevOps Platform.

It establishes a secure, highly available, and scalable network that will host the Kubernetes cluster, Jenkins, monitoring services, and the Pet Adoption application.

This module follows AWS networking best practices by separating internet-facing resources from internal workloads while using a remote Terraform backend stored in Amazon S3.

---

# Architecture

```
                                Internet
                                    │
                            Internet Gateway
                                    │
                         Public Route Table
                                    │
             ┌──────────────────────┴──────────────────────┐
             │                                             │
      Public Subnet A                              Public Subnet B
       10.0.1.0/24                                 10.0.2.0/24
             │                                             │
             │                                             │
     NAT Gateway (EIP)                          Future Public Resources
             │
      Private Route Table
             │
      ┌──────┴──────────────┐
      │                     │
Private Subnet A      Private Subnet B
 10.0.11.0/24          10.0.12.0/24
      │                     │
      └──────────┬──────────┘
                 │
        Kubernetes Cluster
        Pet Adoption Application
```

---

# Purpose

This module creates the AWS networking foundation that every other infrastructure component depends on.

It provides:

- Network isolation
- High Availability
- Secure workload separation
- Controlled internet connectivity
- Scalable IP addressing
- Foundation for Kubernetes

---

# Resources Created

## Network

- One VPC
- Two Public Subnets
- Two Private Subnets

## Internet Connectivity

- One Internet Gateway
- One Public Route Table
- Two Public Route Table Associations

## Private Connectivity

- One Elastic IP
- One NAT Gateway
- One Private Route Table
- Two Private Route Table Associations

---

# VPC Design

The VPC uses the CIDR block:

```
10.0.0.0/16
```

This provides **65,536 IP addresses**, allowing the network to scale without redesign.

DNS Support and DNS Hostnames are enabled to support:

- EC2
- Kubernetes
- Internal service discovery
- Load Balancers

---

# Availability Zones

The infrastructure spans two Availability Zones:

```
eu-west-3a
eu-west-3b
```

Using multiple Availability Zones improves fault tolerance and availability.

If one Availability Zone experiences an outage, workloads can continue running in the other.

---

# Public Subnets

```
Public Subnet A
10.0.1.0/24

Public Subnet B
10.0.2.0/24
```

Characteristics:

- Automatically assign Public IP addresses
- Connected to the Internet Gateway
- Associated with the Public Route Table

Future resources:

- Application Load Balancer
- NAT Gateway
- Jenkins Server

---

# Private Subnets

```
Private Subnet A
10.0.11.0/24

Private Subnet B
10.0.12.0/24
```

Characteristics:

- No automatic Public IP assignment
- Associated with the Private Route Table
- Internet access only through the NAT Gateway

Future resources:

- Kubernetes Control Plane
- Worker Nodes
- Pet Adoption Pods
- Databases
- Internal Services

---

# Internet Gateway

The Internet Gateway is attached to the VPC.

It provides internet connectivity for resources located in public subnets.

The Internet Gateway is attached to the VPC rather than individual subnets because it serves as the single internet entry and exit point for the entire virtual network.

A subnet becomes public only when:

- An Internet Gateway is attached to the VPC
- A Route Table contains a default route to the Internet Gateway
- The subnet is associated with that Route Table
- The resource has a Public IP address

---

# NAT Gateway

A single NAT Gateway is deployed in Public Subnet A.

It uses an Elastic IP address.

Purpose:

Allow resources inside private subnets to initiate outbound internet connections without exposing them directly to the internet.

Examples include:

- Downloading operating system updates
- Pulling container images
- Installing software packages
- Communicating with external APIs

Inbound internet connections to private resources remain blocked.

---

# Route Tables

## Public Route Table

Default Route:

```
0.0.0.0/0 → Internet Gateway
```

Associated with:

- Public Subnet A
- Public Subnet B

---

## Private Route Table

Default Route:

```
0.0.0.0/0 → NAT Gateway
```

Associated with:

- Private Subnet A
- Private Subnet B

---

# High Availability

The network is distributed across two Availability Zones.

Benefits:

- Increased fault tolerance
- Improved resilience
- Better production readiness
- Reduced downtime

A production deployment would typically use one NAT Gateway per Availability Zone.

To minimise cost during development, this project uses a single NAT Gateway.

---

# Remote Terraform State

Terraform state is stored remotely in Amazon S3.

State path:

```
network/terraform.tfstate
```

Benefits:

- Centralised state management
- Versioning
- Encryption
- Team collaboration
- Protection against local machine failure

---

# Deployment

```bash
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
```

---

# Verification

Verify VPC

```bash
aws ec2 describe-vpcs
```

Verify Subnets

```bash
aws ec2 describe-subnets
```

Verify Internet Gateway

```bash
aws ec2 describe-internet-gateways
```

Verify Route Tables

```bash
aws ec2 describe-route-tables
```

Verify NAT Gateway

```bash
aws ec2 describe-nat-gateways
```

---

# Cost Considerations

Minimal cost resources:

- VPC
- Subnets
- Internet Gateway
- Route Tables
- Security Groups

Billable resources:

- NAT Gateway
- Elastic IP (when applicable)
- EC2 Instances
- Load Balancer
- Kubernetes Cluster

To reduce costs during learning, the NAT Gateway should be deleted after testing and recreated when required.

---

# Engineering Notes

## Key Concepts Learned

- A VPC is an isolated virtual network inside AWS.
- Public and private subnets improve security through workload separation.
- Public subnets require an Internet Gateway, a Route Table, a Route Table Association and a Public IP.
- Private subnets use a NAT Gateway for outbound internet access.
- The Internet Gateway belongs to the VPC, not to an individual subnet.
- Route Tables determine where network traffic is sent.
- High Availability is achieved by distributing infrastructure across multiple Availability Zones.
- Remote Terraform state provides a secure and central source of truth.

---

# Architecture Decisions (ADR)

## ADR-001 – VPC CIDR

**Decision**

Use `10.0.0.0/16`.

**Reason**

Provides sufficient address space for future growth while maintaining a simple addressing scheme.

---

## ADR-002 – Multi-AZ Design

**Decision**

Deploy resources across two Availability Zones.

**Reason**

Improves availability and resilience against Availability Zone failures.

---

## ADR-003 – Single NAT Gateway

**Decision**

Use one NAT Gateway.

**Reason**

A production environment would normally deploy one NAT Gateway per Availability Zone. For this learning project, one NAT Gateway demonstrates the correct architecture while keeping AWS costs low.

---

# Interview Questions

### Why did you choose 10.0.0.0/16?

It provides 65,536 private IP addresses, allowing the infrastructure to scale without redesigning the network.

---

### Why are Kubernetes nodes deployed in private subnets?

To prevent direct internet access and improve the security of production workloads.

---

### Why is the Internet Gateway attached to the VPC instead of a subnet?

Because it provides a single internet entry and exit point for the entire VPC. Individual subnets use Route Tables to decide whether their traffic should be forwarded to the Internet Gateway.

---

### Why is a NAT Gateway required?

It allows private resources to initiate outbound internet connections while preventing inbound internet connections, improving the security of internal workloads.

---

### Why use a remote Terraform backend?

To provide secure, encrypted, versioned and centralised state management that can be shared by authorised engineers and CI/CD systems.