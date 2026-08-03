#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/kops.env"

export AWS_PROFILE
export AWS_REGION
export KOPS_STATE_STORE
export NAME

echo "=========================================="
echo " Verify KOps Cleanup"
echo "=========================================="
echo "Cluster: ${NAME}"
echo "Region:  ${AWS_REGION}"
echo "=========================================="

echo
echo "1. EC2 instances"

EC2_INSTANCES="$(aws ec2 describe-instances \
  --region "${AWS_REGION}" \
  --filters \
    "Name=tag:KubernetesCluster,Values=${NAME}" \
    "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query "Reservations[].Instances[].InstanceId" \
  --output text)"

if [[ -z "${EC2_INSTANCES}" || "${EC2_INSTANCES}" == "None" ]]; then
  echo "PASS: No active cluster EC2 instances found."
else
  echo "WARNING: EC2 instances remain:"
  echo "${EC2_INSTANCES}"
fi

echo
echo "2. NAT Gateways"

NAT_GATEWAYS="$(aws ec2 describe-nat-gateways \
  --region "${AWS_REGION}" \
  --filter \
    "Name=tag:KubernetesCluster,Values=${NAME}" \
    "Name=state,Values=pending,available,deleting" \
  --query "NatGateways[].NatGatewayId" \
  --output text)"

if [[ -z "${NAT_GATEWAYS}" || "${NAT_GATEWAYS}" == "None" ]]; then
  echo "PASS: No cluster NAT Gateways found."
else
  echo "WARNING: NAT Gateways remain:"
  echo "${NAT_GATEWAYS}"
fi

echo
echo "3. Load Balancers"

LOAD_BALANCERS="$(aws elbv2 describe-load-balancers \
  --region "${AWS_REGION}" \
  --query "LoadBalancers[?contains(DNSName, 'k8s.ferdeve.fit') || contains(LoadBalancerName, 'k8s-ferdeve')].[LoadBalancerArn]" \
  --output text 2>/dev/null || true)"

if [[ -z "${LOAD_BALANCERS}" || "${LOAD_BALANCERS}" == "None" ]]; then
  echo "PASS: No cluster load balancers found."
else
  echo "WARNING: Load balancers remain:"
  echo "${LOAD_BALANCERS}"
fi

echo
echo "4. EBS volumes"

EBS_VOLUMES="$(aws ec2 describe-volumes \
  --region "${AWS_REGION}" \
  --filters "Name=tag:KubernetesCluster,Values=${NAME}" \
  --query "Volumes[].VolumeId" \
  --output text)"

if [[ -z "${EBS_VOLUMES}" || "${EBS_VOLUMES}" == "None" ]]; then
  echo "PASS: No cluster EBS volumes found."
else
  echo "WARNING: EBS volumes remain:"
  echo "${EBS_VOLUMES}"
fi

echo
echo "5. Elastic IP addresses"

ELASTIC_IPS="$(aws ec2 describe-addresses \
  --region "${AWS_REGION}" \
  --filters "Name=tag:KubernetesCluster,Values=${NAME}" \
  --query "Addresses[].AllocationId" \
  --output text)"

if [[ -z "${ELASTIC_IPS}" || "${ELASTIC_IPS}" == "None" ]]; then
  echo "PASS: No cluster Elastic IP addresses found."
else
  echo "WARNING: Elastic IP addresses remain:"
  echo "${ELASTIC_IPS}"
fi

echo
echo "Cleanup verification completed."
echo "Any WARNING above requires manual investigation."