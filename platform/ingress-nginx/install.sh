#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/ingress.env"

export AWS_PROFILE
export AWS_REGION

VALUES_FILE="${SCRIPT_DIR}/values.yaml"
LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/install-$(date +%Y%m%d-%H%M%S).log"

mkdir -p "${LOG_DIR}"

exec > >(tee -a "${LOG_FILE}") 2>&1

echo "=========================================="
echo " Install NGINX Ingress Controller"
echo "=========================================="
echo "Release:       ${RELEASE_NAME}"
echo "Namespace:     ${NAMESPACE}"
echo "Chart:         ${CHART_NAME}"
echo "Chart version: ${CHART_VERSION}"
echo "Values file:   ${VALUES_FILE}"
echo "Log file:      ${LOG_FILE}"
echo "=========================================="

for command in helm kubectl; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "ERROR: ${command} is not installed or is not in PATH."
    exit 1
  fi
done

if [[ ! -f "${VALUES_FILE}" ]]; then
  echo "ERROR: values.yaml was not found:"
  echo "${VALUES_FILE}"
  exit 1
fi

CURRENT_CONTEXT="$(kubectl config current-context 2>/dev/null || true)"

if [[ -z "${CURRENT_CONTEXT}" ]]; then
  echo "ERROR: No kubectl context is configured."
  echo "Recreate the cluster and export kubeconfig first."
  exit 1
fi

if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "ERROR: Kubernetes cluster is not reachable."
  exit 1
fi

echo "Kubernetes context: ${CURRENT_CONTEXT}"

if ! helm repo list 2>/dev/null |
  awk 'NR > 1 {print $1}' |
  grep -qx "${HELM_REPOSITORY_NAME}"; then

  echo
  echo "Adding Helm repository..."

  helm repo add \
    "${HELM_REPOSITORY_NAME}" \
    "${HELM_REPOSITORY_URL}"
else
  echo "Helm repository already exists."
fi

echo
echo "Updating Helm repositories..."

helm repo update

echo
echo "Rendering chart for validation..."

RENDERED_FILE="$(mktemp)"

helm template "${RELEASE_NAME}" \
  "${CHART_NAME}" \
  --namespace "${NAMESPACE}" \
  --version "${CHART_VERSION}" \
  --values "${VALUES_FILE}" \
  > "${RENDERED_FILE}"

if [[ ! -s "${RENDERED_FILE}" ]]; then
  echo "ERROR: Helm produced an empty manifest."
  rm -f "${RENDERED_FILE}"
  exit 1
fi

echo "Helm rendering passed."
rm -f "${RENDERED_FILE}"

echo
echo "This operation will create an AWS Load Balancer."
read -r -p "Type INSTALL to continue: " CONFIRMATION

if [[ "${CONFIRMATION}" != "INSTALL" ]]; then
  echo "Installation cancelled."
  exit 0
fi

echo
echo "Installing or upgrading ingress-nginx..."

helm upgrade --install "${RELEASE_NAME}" \
  "${CHART_NAME}" \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  --version "${CHART_VERSION}" \
  --values "${VALUES_FILE}" \
  --wait \
  --timeout 10m

echo
echo "Waiting for controller deployment..."

kubectl rollout status \
  deployment/ingress-nginx-controller \
  --namespace "${NAMESPACE}" \
  --timeout=5m

echo
echo "Waiting for external load-balancer hostname..."

INGRESS_HOSTNAME=""

for attempt in {1..30}; do
  INGRESS_HOSTNAME="$(kubectl get service "${CONTROLLER_SERVICE}" \
    --namespace "${NAMESPACE}" \
    --output jsonpath='{.status.loadBalancer.ingress[0].hostname}' \
    2>/dev/null || true)"

  if [[ -n "${INGRESS_HOSTNAME}" ]]; then
    break
  fi

  echo "Attempt ${attempt}/30: hostname not assigned yet."
  sleep 10
done

if [[ -z "${INGRESS_HOSTNAME}" ]]; then
  echo "WARNING: Controller is installed, but the load-balancer hostname is not ready."
  echo "Run ./verify.sh later."
  exit 0
fi

echo
echo "NGINX Ingress Controller installed successfully."
echo "External hostname:"
echo "${INGRESS_HOSTNAME}"
echo
echo "Run:"
echo "  ./verify.sh"