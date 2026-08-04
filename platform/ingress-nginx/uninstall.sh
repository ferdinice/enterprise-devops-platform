#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/ingress.env"

export AWS_PROFILE
export AWS_REGION

LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/uninstall-$(date +%Y%m%d-%H%M%S).log"

mkdir -p "${LOG_DIR}"

exec > >(tee -a "${LOG_FILE}") 2>&1

echo "=========================================="
echo " Uninstall NGINX Ingress Controller"
echo "=========================================="
echo "Release:   ${RELEASE_NAME}"
echo "Namespace: ${NAMESPACE}"
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

  echo "Helm release does not exist."
  echo "Nothing to uninstall."
  exit 0
fi

echo
echo "WARNING"
echo "This removes the ingress controller and its AWS Load Balancer."
echo "Application DNS records should be deleted first."
echo

read -r -p "Type DELETE to continue: " CONFIRMATION

if [[ "${CONFIRMATION}" != "DELETE" ]]; then
  echo "Uninstallation cancelled."
  exit 0
fi

echo
echo "Uninstalling Helm release..."

helm uninstall "${RELEASE_NAME}" \
  --namespace "${NAMESPACE}" \
  --wait \
  --timeout 10m

echo
echo "Waiting for controller Service deletion..."

for attempt in {1..30}; do
  if ! kubectl get service "${CONTROLLER_SERVICE}" \
    --namespace "${NAMESPACE}" >/dev/null 2>&1; then

    echo "Controller Service has been deleted."
    break
  fi

  echo "Attempt ${attempt}/30: Service still exists."
  sleep 10
done

if helm status "${RELEASE_NAME}" \
  --namespace "${NAMESPACE}" >/dev/null 2>&1; then

  echo "ERROR: Helm release still exists."
  exit 1
fi

echo "PASS: Helm release was removed."

if kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
  echo
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
echo "Uninstallation completed."
echo "Review log:"
echo "${LOG_FILE}"