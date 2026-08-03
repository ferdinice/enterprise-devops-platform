#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/kops.env"

export AWS_PROFILE
export AWS_REGION
export KOPS_STATE_STORE
export NAME

EXPECTED_ACCOUNT_ID="740994137090"

echo "=========================================="
echo " KOps Cluster Update"
echo "=========================================="
echo "AWS profile:      ${AWS_PROFILE}"
echo "AWS region:       ${AWS_REGION}"
echo "Cluster name:     ${NAME}"
echo "KOps state store: ${KOPS_STATE_STORE}"
echo "=========================================="

for command in aws kops kubectl; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "ERROR: ${command} is not installed or not in PATH."
    exit 1
  fi
done

CURRENT_ACCOUNT_ID="$(aws sts get-caller-identity \
  --query Account \
  --output text)"

if [[ "${CURRENT_ACCOUNT_ID}" != "${EXPECTED_ACCOUNT_ID}" ]]; then
  echo "ERROR: Wrong AWS account."
  echo "Expected: ${EXPECTED_ACCOUNT_ID}"
  echo "Current:  ${CURRENT_ACCOUNT_ID}"
  exit 1
fi

if ! kops get cluster "${NAME}" \
  --state "${KOPS_STATE_STORE}" >/dev/null 2>&1; then
  echo "ERROR: Cluster blueprint does not exist."
  echo "Run ./create-cluster.sh first."
  exit 1
fi

echo
echo "Generating infrastructure preview..."
echo

kops update cluster \
  --name "${NAME}" \
  --state "${KOPS_STATE_STORE}"

echo
echo "WARNING"
echo "This operation creates billable AWS resources, including:"
echo "- EC2 instances"
echo "- NAT Gateways"
echo "- Network Load Balancers"
echo "- EBS volumes"
echo "- Elastic IP addresses"
echo
read -r -p "Type APPLY to create or update the cluster: " CONFIRMATION

if [[ "${CONFIRMATION}" != "APPLY" ]]; then
  echo "Update cancelled. No infrastructure was changed."
  exit 0
fi

echo
echo "Applying KOps cluster configuration..."

kops update cluster \
  --name "${NAME}" \
  --state "${KOPS_STATE_STORE}" \
  --yes \
  --admin

echo
echo "KOps update completed."
echo "The infrastructure may take several minutes to become healthy."
echo
echo "Next:"
echo "  ./export-kubeconfig.sh"
echo "  ./validate-cluster.sh"