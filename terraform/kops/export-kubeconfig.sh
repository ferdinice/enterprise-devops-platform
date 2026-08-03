#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/kops.env"

export AWS_PROFILE
export AWS_REGION
export KOPS_STATE_STORE
export NAME

KUBECONFIG_PATH="${HOME}/.kube/config"

echo "=========================================="
echo " Export Kubernetes Kubeconfig"
echo "=========================================="
echo "Cluster:    ${NAME}"
echo "Kubeconfig: ${KUBECONFIG_PATH}"
echo "=========================================="

for command in aws kops kubectl; do
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

mkdir -p "${HOME}/.kube"

if [[ -f "${KUBECONFIG_PATH}" ]]; then
  BACKUP="${KUBECONFIG_PATH}.$(date +%Y%m%d-%H%M%S).bak"
  cp "${KUBECONFIG_PATH}" "${BACKUP}"
  echo "Existing kubeconfig backed up to:"
  echo "${BACKUP}"
fi

kops export kubeconfig "${NAME}" \
  --state "${KOPS_STATE_STORE}" \
  --admin=18h \
  --kubeconfig "${KUBECONFIG_PATH}"

echo
echo "Kubeconfig exported successfully."

echo
echo "Current kubectl context:"
kubectl config current-context

echo
echo "Configured contexts:"
kubectl config get-contexts