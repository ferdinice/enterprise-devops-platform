#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/kops.env"

export AWS_PROFILE
export AWS_REGION
export KOPS_STATE_STORE
export NAME

echo "=========================================="
echo " Validate KOps Cluster"
echo "=========================================="
echo "Cluster: ${NAME}"
echo "=========================================="

for command in kops kubectl; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "ERROR: ${command} is not installed or not in PATH."
    exit 1
  fi
done

CURRENT_CONTEXT="$(kubectl config current-context 2>/dev/null || true)"

if [[ "${CURRENT_CONTEXT}" != "${NAME}" ]]; then
  echo "ERROR: kubectl is not using the expected cluster context."
  echo "Expected: ${NAME}"
  echo "Current:  ${CURRENT_CONTEXT:-none}"
  echo
  echo "Run ./export-kubeconfig.sh first."
  exit 1
fi

echo
echo "Waiting for the cluster to become healthy..."

kops validate cluster "${NAME}" \
  --state "${KOPS_STATE_STORE}" \
  --wait 15m \
  --count 3

echo
echo "KOps validation passed."

echo
echo "Kubernetes nodes:"
kubectl get nodes -o wide

echo
echo "System pods:"
kubectl get pods -n kube-system -o wide

echo
echo "Cluster information:"
kubectl cluster-info