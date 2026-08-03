#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/kops.env"

export AWS_PROFILE
export AWS_REGION
export KOPS_STATE_STORE
export NAME

echo "=========================================="
echo " KOps Rolling Update"
echo "=========================================="
echo "Cluster: ${NAME}"
echo "=========================================="

for command in kops kubectl; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "ERROR: ${command} is not installed or not in PATH."
    exit 1
  fi
done

if ! kops get cluster "${NAME}" \
  --state "${KOPS_STATE_STORE}" >/dev/null 2>&1; then
  echo "ERROR: Cluster blueprint does not exist."
  exit 1
fi

CURRENT_CONTEXT="$(kubectl config current-context 2>/dev/null || true)"

if [[ "${CURRENT_CONTEXT}" != "${NAME}" ]]; then
  echo "ERROR: Wrong or missing kubectl context."
  echo "Expected: ${NAME}"
  echo "Current:  ${CURRENT_CONTEXT:-none}"
  exit 1
fi

echo
echo "Validating cluster before rolling update..."

kops validate cluster "${NAME}" \
  --state "${KOPS_STATE_STORE}" \
  --wait 10m \
  --count 1

echo
echo "Rolling-update preview:"
echo

kops rolling-update cluster "${NAME}" \
  --state "${KOPS_STATE_STORE}"

echo
echo "WARNING"
echo "A rolling update may drain workloads and replace EC2 instances."
read -r -p "Type ROLLING-UPDATE to continue: " CONFIRMATION

if [[ "${CONFIRMATION}" != "ROLLING-UPDATE" ]]; then
  echo "Rolling update cancelled."
  exit 0
fi

kops rolling-update cluster "${NAME}" \
  --state "${KOPS_STATE_STORE}" \
  --yes

echo
echo "Rolling update completed."

kops validate cluster "${NAME}" \
  --state "${KOPS_STATE_STORE}" \
  --wait 15m \
  --count 3