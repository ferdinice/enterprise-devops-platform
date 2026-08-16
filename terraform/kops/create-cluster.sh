#!/bin/bash
set -euo pipefail

# Find the directory where this script is stored.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load shared KOps configuration.
source "${SCRIPT_DIR}/kops.env"

export AWS_PROFILE
export AWS_REGION
export KOPS_STATE_STORE
export NAME

echo "=========================================="
echo " KOps Cluster Configuration"
echo "=========================================="
echo "AWS profile:      ${AWS_PROFILE}"
echo "AWS region:       ${AWS_REGION}"
echo "Cluster name:     ${NAME}"
echo "KOps state store: ${KOPS_STATE_STORE}"
echo "SSH public key:   ${SSH_PUBLIC_KEY}"
echo "=========================================="

# Verify required commands are installed.
for command in aws kops kubectl; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "ERROR: ${command} is not installed or is not in PATH."
    exit 1
  fi
done

# Verify that the expected AWS account is active.
CURRENT_ACCOUNT_ID="$(aws sts get-caller-identity \
  --query Account \
  --output text)"

EXPECTED_ACCOUNT_ID="740994137090"

if [[ "${CURRENT_ACCOUNT_ID}" != "${EXPECTED_ACCOUNT_ID}" ]]; then
  echo "ERROR: Wrong AWS account."
  echo "Expected: ${EXPECTED_ACCOUNT_ID}"
  echo "Current:  ${CURRENT_ACCOUNT_ID}"
  exit 1
fi

# Confirm the KOps state bucket exists.
STATE_BUCKET="${KOPS_STATE_STORE#s3://}"

if ! aws s3api head-bucket \
  --bucket "${STATE_BUCKET}" 2>/dev/null; then
  echo "ERROR: KOps state bucket does not exist or is inaccessible."
  echo "Bucket: ${STATE_BUCKET}"
  exit 1
fi

# Confirm the SSH public key exists.
if [[ ! -f "${SSH_PUBLIC_KEY}" ]]; then
  echo "ERROR: SSH public key was not found."
  echo "Expected location: ${SSH_PUBLIC_KEY}"
  exit 1
fi

# Prevent duplicate cluster configuration.
if kops get cluster "${NAME}" \
  --state "${KOPS_STATE_STORE}" >/dev/null 2>&1; then

  echo
  echo "Cluster configuration already exists:"
  echo "${NAME}"
  echo
  echo "No new configuration was created."
  echo "Review it with:"
  echo "  kops get cluster ${NAME}"
  echo "  kops get ig --name ${NAME}"
  exit 0
fi

echo
echo "Creating KOps cluster blueprint..."

kops create cluster \
  --name "${NAME}" \
  --state "${KOPS_STATE_STORE}" \
  --cloud aws \
  --zones eu-west-3a,eu-west-3b,eu-west-3c \
  --control-plane-zones eu-west-3a,eu-west-3b,eu-west-3c \
  --control-plane-count 3 \
  --node-count 2 \
  --control-plane-size t3.medium \
  --node-size t3.medium \
  --networking calico \
  --topology private \
  --bastion \
  --dns-zone ferdeve.fit \
  --ssh-public-key "${SSH_PUBLIC_KEY}" \
  --set spec.kubeProxy.metricsBindAddress=0.0.0.0

echo
echo "Cluster blueprint created successfully."
echo
echo "No AWS cluster infrastructure has been provisioned yet."
echo "Review the configuration before running update-cluster.sh."