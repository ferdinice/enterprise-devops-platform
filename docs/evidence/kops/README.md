# KOps Deployment Evidence

This directory contains deployment evidence captured during the live AWS deployment and validation of the Enterprise DevOps Platform Kubernetes cluster.

The evidence demonstrates that the KOps configuration stored in the repository was successfully translated into a functioning multi-AZ Kubernetes environment on AWS.

## Evidence Index

| ID | Evidence | Demonstrates |
|---|---|---|
| 01 | `01-kubernetes-nodes-ready.png` | Three control-plane nodes and two worker nodes reached `Ready` state |
| 02 | `02-kops-instance-groups.png` | KOps InstanceGroup configuration across eu-west-3a, eu-west-3b and eu-west-3c |
| 03 | `03-kops-cluster-validation.png` | Successful `kops validate cluster` result |
| 04A | `04a-kube-system-pods-1.png` | Kubernetes system workloads running |
| 04B | `04b-kube-system-pods-2.png` | Additional kube-system control-plane and networking workloads |
| 05A | `05a-aws-ec2-instances-overview.png` | Six KOps-managed EC2 instances running and healthy |
| 05B | `05b-aws-ec2-security-networking.png` | EC2 security and networking configuration |
| 06 | `06-aws-auto-scaling-groups.png` | Seven KOps-managed Auto Scaling Groups at desired capacity |
| 07 | `07-aws-network-load-balancers.png` | Kubernetes API and bastion Network Load Balancers |
| 08A | `08a-aws-kops-vpc.png` | Dedicated KOps VPC using `172.20.0.0/16` |
| 08B | `08b-aws-kops-subnets.png` | Six KOps subnets distributed across three Availability Zones |
| 09 | `09-aws-nat-gateways.png` | Three NAT Gateways providing outbound connectivity for private subnets |
| 10 | `10-route53-kops-records.png` | Route 53 DNS records created for the Kubernetes API and bastion |
| 11A | `11a-s3-kops-state-root.png` | Dedicated S3 KOps state store |
| 11B | `11b-s3-kops-state-contents-1.png` | KOps cluster configuration/state stored under the cluster prefix |
| 11C | `11c-s3-kops-state-contents-2.png` | Additional KOps state, PKI, manifests and cluster metadata |

## Deployment Result

The live validation confirmed:

- Kubernetes version `1.35.7`
- three highly available control-plane nodes
- two active worker nodes
- a dedicated bastion InstanceGroup
- multi-AZ deployment across `eu-west-3a`, `eu-west-3b` and `eu-west-3c`
- Calico networking
- healthy Kubernetes system workloads
- AWS Auto Scaling integration
- Network Load Balancers
- private cluster networking with NAT Gateway egress
- Route 53 integration
- persistent KOps state stored in Amazon S3

The cluster successfully passed:

```bash
kops validate cluster \
  --name k8s.ferdeve.fit \
  --state s3://enterprise-devops-platform-kops-state-740994137090