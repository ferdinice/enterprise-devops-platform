#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/cert-manager.env"

export AWS_PROFILE
export AWS_REGION

VALUES_FILE="${SCRIPT_DIR}/values.yaml"
LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/install-$(date +%Y%m%d-%H%M%S).log"

mkdir -p "${LOG_DIR}"

exec > >(tee -a "${LOG_FILE}") 2>&1

echo "=========================================="
echo " Install cert-manager"
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
  echo "Adding Jetstack Helm repository..."

  helm repo add \
    "${HELM_REPOSITORY_NAME}" \
    "${HELM_REPOSITORY_URL}"
else
  echo "Jetstack Helm repository already exists."
fi

echo
echo "Updating Helm repositories..."
helm repo update

echo
echo "Confirming pinned chart version exists..."

if ! helm search repo "${CHART_NAME}" \
  --versions |
  awk 'NR > 1 {print $2}' |
  grep -qx "${CHART_VERSION}"; then

  echo "ERROR: Chart version ${CHART_VERSION} was not found."
  echo
  echo "Available versions:"
  helm search repo "${CHART_NAME}" --versions | head -10
  exit 1
fi

echo "Chart version ${CHART_VERSION} is available."

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

if ! grep -q "kind: CustomResourceDefinition" "${RENDERED_FILE}"; then
  echo "ERROR: Rendered output does not contain cert-manager CRDs."
  rm -f "${RENDERED_FILE}"
  exit 1
fi

rm -f "${RENDERED_FILE}"

echo "Helm rendering and CRD validation passed."

echo
echo "This operation installs cluster-wide CRDs and cert-manager controllers."
read -r -p "Type INSTALL to continue: " CONFIRMATION

if [[ "${CONFIRMATION}" != "INSTALL" ]]; then
  echo "Installation cancelled."
  exit 0
fi

echo
echo "Installing or upgrading cert-manager..."

helm upgrade --install "${RELEASE_NAME}" \
  "${CHART_NAME}" \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  --version "${CHART_VERSION}" \
  --values "${VALUES_FILE}" \
  --wait \
  --timeout 10m

echo
echo "Waiting for cert-manager deployments..."

kubectl rollout status deployment/cert-manager \
  --namespace "${NAMESPACE}" \
  --timeout=5m

kubectl rollout status deployment/cert-manager-webhook \
  --namespace "${NAMESPACE}" \
  --timeout=5m

kubectl rollout status deployment/cert-manager-cainjector \
  --namespace "${NAMESPACE}" \
  --timeout=5m

echo
echo "cert-manager installation completed."
echo "Run:"
echo "  ./verify.sh"