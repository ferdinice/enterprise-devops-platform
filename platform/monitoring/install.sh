#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/monitoring.env"

VALUES_FILE="${SCRIPT_DIR}/values.yaml"
LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/install-$(date +%Y%m%d-%H%M%S).log"

mkdir -p "${LOG_DIR}"

exec > >(tee -a "${LOG_FILE}") 2>&1

echo "=========================================="
echo " Install Monitoring Stack"
echo "=========================================="
echo "Namespace:     ${MONITORING_NAMESPACE}"
echo "Release:       ${RELEASE_NAME}"
echo "Chart:         ${CHART_NAME}"
echo "Grafana:       ${GRAFANA_HOSTNAME}"
echo "Prometheus:    ${PROMETHEUS_HOSTNAME}"
echo "Values file:   ${VALUES_FILE}"
echo "Log file:      ${LOG_FILE}"
echo "=========================================="

for command in helm kubectl; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "ERROR: ${command} is not installed or not in PATH."
    exit 1
  fi
done

if [[ ! -f "${VALUES_FILE}" ]]; then
  echo "ERROR: values.yaml not found:"
  echo "${VALUES_FILE}"
  exit 1
fi

if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "ERROR: Kubernetes cluster is not reachable."
  exit 1
fi

echo
echo "Checking platform dependencies..."

if ! kubectl get ingressclass "${INGRESS_CLASS_NAME}" >/dev/null 2>&1; then
  echo "ERROR: IngressClass '${INGRESS_CLASS_NAME}' does not exist."
  exit 1
fi

echo "PASS: IngressClass '${INGRESS_CLASS_NAME}' exists."

ISSUER_READY="$(kubectl get clusterissuer "${CLUSTER_ISSUER_NAME}" \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' \
  2>/dev/null || true)"

if [[ "${ISSUER_READY}" != "True" ]]; then
  echo "ERROR: ClusterIssuer '${CLUSTER_ISSUER_NAME}' is not Ready."
  exit 1
fi

echo "PASS: ClusterIssuer '${CLUSTER_ISSUER_NAME}' is Ready."

if ! helm repo list 2>/dev/null | awk 'NR > 1 {print $1}' | grep -qx "${HELM_REPOSITORY_NAME}"; then
  echo
  echo "Adding Prometheus Community Helm repository..."

  helm repo add \
    "${HELM_REPOSITORY_NAME}" \
    "${HELM_REPOSITORY_URL}"
else
  echo "Prometheus Community Helm repository already exists."
fi

echo
echo "Updating Helm repositories..."
helm repo update

echo
echo "Rendering monitoring chart..."

RENDERED_FILE="$(mktemp)"

cleanup() {
  rm -f "${RENDERED_FILE}"
}

trap cleanup EXIT

helm template "${RELEASE_NAME}" \
  "${CHART_NAME}" \
  --namespace "${MONITORING_NAMESPACE}" \
  --values "${VALUES_FILE}" \
  > "${RENDERED_FILE}"

if [[ ! -s "${RENDERED_FILE}" ]]; then
  echo "ERROR: Helm rendered an empty manifest."
  exit 1
fi

if ! grep -q "kind: Prometheus" "${RENDERED_FILE}"; then
  echo "ERROR: Rendered output does not contain a Prometheus resource."
  exit 1
fi

if ! grep -q "grafana.ferdeve.fit" "${RENDERED_FILE}"; then
  echo "ERROR: Grafana hostname not found in rendered output."
  exit 1
fi

if ! grep -q "prometheus.ferdeve.fit" "${RENDERED_FILE}"; then
  echo "ERROR: Prometheus hostname not found in rendered output."
  exit 1
fi

echo "PASS: Helm rendering checks passed."

echo
echo "WARNING"
echo "This will install:"
echo "- Prometheus"
echo "- Grafana"
echo "- kube-state-metrics"
echo "- node-exporter"
echo "- Prometheus Operator"
echo

read -r -p "Type INSTALL to continue: " CONFIRMATION

if [[ "${CONFIRMATION}" != "INSTALL" ]]; then
  echo "Installation cancelled."
  exit 1
fi

echo
echo "Installing monitoring stack..."

helm upgrade --install "${RELEASE_NAME}" \
  "${CHART_NAME}" \
  --namespace "${MONITORING_NAMESPACE}" \
  --create-namespace \
  --values "${VALUES_FILE}" \
  --wait \
  --timeout 15m

echo
echo "Monitoring stack installation completed."
echo
echo "Next:"
echo "  ./verify.sh"
echo
echo "Installation log:"
echo "${LOG_FILE}"