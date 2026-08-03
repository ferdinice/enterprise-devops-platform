#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/kops.env"

export AWS_PROFILE
export AWS_REGION
export KOPS_STATE_STORE
export NAME

LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "${LOG_DIR}"

LOG_FILE="${LOG_DIR}/delete-$(date +%Y%m%d-%H%M%S).log"

exec > >(tee -a "${LOG_FILE}") 2>&1

echo "=========================================="
echo " Delete KOps Cluster"
echo "=========================================="
echo "Date:        $(date)"
echo "Cluster:     ${NAME}"
echo "AWS profile: ${AWS_PROFILE}"
echo "Region:      ${AWS_REGION}"
echo "Log file:    ${LOG_FILE}"
echo "=========================================="

EXPECTED_ACCOUNT_ID="740994137090"

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
  echo "Cluster blueprint does not exist."
  echo "Running cleanup verification only."
  "${SCRIPT_DIR}/verify-cleanup.sh"
  exit 0
fi

echo
echo "Deletion preview:"
echo

kops delete cluster \
  --name "${NAME}" \
  --state "${KOPS_STATE_STORE}"

echo
echo "DANGER"
echo "This deletes the Kubernetes cluster and associated AWS resources."
echo "There is no undo."
echo
read -r -p "Type DELETE to permanently remove ${NAME}: " CONFIRMATION

if [[ "${CONFIRMATION}" != "DELETE" ]]; then
  echo "Deletion cancelled."
  exit 0
fi

echo
echo "Deleting cluster..."

kops delete cluster \
  --name "${NAME}" \
  --state "${KOPS_STATE_STORE}" \
  --wait 20m \
  --yes

echo
echo "KOps deletion command completed."
echo "Waiting 60 seconds for AWS resource cleanup..."

sleep 60

"${SCRIPT_DIR}/verify-cleanup.sh"

echo
echo "Deletion workflow completed."
echo "Review warnings and the log:"
echo "${LOG_FILE}"