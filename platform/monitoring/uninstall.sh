#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/monitoring.env"

LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/uninstall-$(date +%Y%m%d-%H%M%S).log"

mkdir -p "${LOG_DIR}"

exec > >(tee -a "${LOG_FILE}") 2>&1

echo "=========================================="
echo " Uninstall Monitoring Stack"
echo "=========================================="
echo "Namespace: ${MONITORING_NAMESPACE}"
echo "Release:   ${RELEASE_NAME}"
echo "Log file:  ${LOG_FILE}"
echo "=========================================="

for command in helm kubectl; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "ERROR: ${command} is not installed or not in PATH."
    exit 1
  fi
done

echo
echo "WARNING"
echo "This will remove:"
echo "- Prometheus"
echo "- Grafana"
echo "- kube-state-metrics"
echo "- node-exporter"
echo "- Prometheus Operator"
echo

read -r -p "Type UNINSTALL to continue: " CONFIRMATION

if [[ "${CONFIRMATION}" != "UNINSTALL" ]]; then
  echo "Uninstall cancelled."
  exit 1
fi

echo
echo "Removing Helm release..."

if helm status "${RELEASE_NAME}" \
  --namespace "${MONITORING_NAMESPACE}" >/dev/null 2>&1; then

  helm uninstall "${RELEASE_NAME}" \
    --namespace "${MONITORING_NAMESPACE}"
else
  echo "Helm release does not exist. Skipping."
fi

echo
echo "Checking monitoring namespace..."

if kubectl get namespace "${MONITORING_NAMESPACE}" >/dev/null 2>&1; then
  kubectl delete namespace "${MONITORING_NAMESPACE}" \
    --wait=true
else
  echo "Namespace does not exist. Skipping."
fi

echo
echo "Monitoring stack uninstall completed."
echo
echo "Uninstall log:"
echo "${LOG_FILE}"