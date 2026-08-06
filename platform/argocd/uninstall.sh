#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/argocd.env"

export AWS_PROFILE
export AWS_REGION

LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/uninstall-$(date +%Y%m%d-%H%M%S).log"

mkdir -p "${LOG_DIR}"

exec > >(tee -a "${LOG_FILE}") 2>&1

echo "=========================================="
echo " Uninstall ArgoCD"
echo "=========================================="
echo "Release:   ${RELEASE_NAME}"
echo "Namespace: ${NAMESPACE}"
echo "Hostname:  ${ARGOCD_HOSTNAME}"
echo "Log file:  ${LOG_FILE}"
echo "=========================================="

for command in helm kubectl; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "ERROR: ${command} is not installed or not in PATH."
    exit 1
  fi
done

if ! helm status "${RELEASE_NAME}" \
  --namespace "${NAMESPACE}" >/dev/null 2>&1; then

  echo "ArgoCD Helm release does not exist."
  echo "Nothing to uninstall."
  exit 0
fi

echo
echo "Existing ArgoCD Applications:"

kubectl get applications.argoproj.io \
  --all-namespaces 2>/dev/null || true

echo
echo "WARNING"
echo "This removes ArgoCD from the cluster."
echo "Applications managed by ArgoCD may remain unless explicitly deleted."
echo "Delete the DNS record for ${ARGOCD_HOSTNAME} first."
echo

read -r -p "Type DELETE to uninstall ArgoCD: " CONFIRMATION

if [[ "${CONFIRMATION}" != "DELETE" ]]; then
  echo "Uninstallation cancelled."
  exit 0
fi

echo
echo "Uninstalling ArgoCD..."

helm uninstall "${RELEASE_NAME}" \
  --namespace "${NAMESPACE}" \
  --wait \
  --timeout 15m

if helm status "${RELEASE_NAME}" \
  --namespace "${NAMESPACE}" >/dev/null 2>&1; then

  echo "ERROR: ArgoCD Helm release still exists."
  exit 1
fi

echo "PASS: ArgoCD Helm release was removed."

if kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
  echo
  read -r -p "Delete namespace ${NAMESPACE}? Type NAMESPACE: " DELETE_NAMESPACE

  if [[ "${DELETE_NAMESPACE}" == "NAMESPACE" ]]; then
    kubectl delete namespace "${NAMESPACE}" \
      --wait=true \
      --timeout=10m

    echo "Namespace deleted."
  else
    echo "Namespace retained."
  fi
fi

echo
echo "IMPORTANT:"
echo "ArgoCD CRDs are intentionally not deleted automatically."
echo "Deleting them can remove all ArgoCD Application and AppProject objects."

echo
echo "Uninstallation completed."
echo "Review log:"
echo "${LOG_FILE}"