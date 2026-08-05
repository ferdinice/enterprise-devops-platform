#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/cert-manager.env"

export AWS_PROFILE
export AWS_REGION

LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/uninstall-$(date +%Y%m%d-%H%M%S).log"

mkdir -p "${LOG_DIR}"

exec > >(tee -a "${LOG_FILE}") 2>&1

echo "=========================================="
echo " Uninstall cert-manager"
echo "=========================================="
echo "Release:   ${RELEASE_NAME}"
echo "Namespace: ${NAMESPACE}"
echo "Log file:  ${LOG_FILE}"
echo "=========================================="

for command in helm kubectl; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "ERROR: ${command} is not installed or is not in PATH."
    exit 1
  fi
done

if ! helm status "${RELEASE_NAME}" \
  --namespace "${NAMESPACE}" >/dev/null 2>&1; then

  echo "Helm release does not exist."
  echo "Nothing to uninstall."
  exit 0
fi

echo
echo "Existing Certificate resources:"

kubectl get certificate \
  --all-namespaces 2>/dev/null || true

echo
echo "Existing Issuer and ClusterIssuer resources:"

kubectl get issuer \
  --all-namespaces 2>/dev/null || true

kubectl get clusterissuer 2>/dev/null || true

echo
echo "WARNING"
echo "Removing cert-manager can stop certificate renewal."
echo "Delete application Certificates and Issuers deliberately first."
echo

read -r -p "Type DELETE to uninstall cert-manager: " CONFIRMATION

if [[ "${CONFIRMATION}" != "DELETE" ]]; then
  echo "Uninstallation cancelled."
  exit 0
fi

helm uninstall "${RELEASE_NAME}" \
  --namespace "${NAMESPACE}" \
  --wait \
  --timeout 10m

echo
echo "Helm release removed."

if kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
  read -r -p "Delete namespace ${NAMESPACE}? Type NAMESPACE: " DELETE_NAMESPACE

  if [[ "${DELETE_NAMESPACE}" == "NAMESPACE" ]]; then
    kubectl delete namespace "${NAMESPACE}" \
      --wait=true \
      --timeout=5m

    echo "Namespace deleted."
  else
    echo "Namespace retained."
  fi
fi

echo
echo "IMPORTANT:"
echo "cert-manager CRDs are intentionally not deleted automatically."
echo "Deleting CRDs can also delete Certificate-related resources."

echo
echo "Uninstallation completed."
echo "Review log:"
echo "${LOG_FILE}"