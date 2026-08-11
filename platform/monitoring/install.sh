#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/monitoring.env"

VALUES_FILE="${SCRIPT_DIR}/values.yaml"
RULES_FILE="${SCRIPT_DIR}/rules/platform-alerts.yaml"

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
echo "Rules file:    ${RULES_FILE}"
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

if [[ ! -f "${RULES_FILE}" ]]; then
  echo "ERROR: PrometheusRule manifest not found:"
  echo "${RULES_FILE}"
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
  --output jsonpath='{.status.conditions[?(@.type=="Ready")].status}' \
  2>/dev/null || true)"

if [[ "${ISSUER_READY}" != "True" ]]; then
  echo "ERROR: ClusterIssuer '${CLUSTER_ISSUER_NAME}' is not Ready."
  exit 1
fi

echo "PASS: ClusterIssuer '${CLUSTER_ISSUER_NAME}' is Ready."

echo
echo "Preparing Slack webhook..."

if [[ -z "${SLACK_WEBHOOK_URL:-}" ]]; then
  read -s -p "Enter Slack webhook URL: " SLACK_WEBHOOK_URL
  echo
fi

if [[ -z "${SLACK_WEBHOOK_URL}" ]]; then
  echo "ERROR: Slack webhook URL was not provided."
  exit 1
fi

echo
echo "Ensuring monitoring namespace exists..."

kubectl create namespace "${MONITORING_NAMESPACE}" \
  --dry-run=client \
  --output yaml \
  | kubectl apply -f -

echo
echo "Creating Slack webhook Secret..."

kubectl create secret generic slack-webhook \
  --namespace "${MONITORING_NAMESPACE}" \
  --from-literal=url="${SLACK_WEBHOOK_URL}" \
  --dry-run=client \
  --output yaml \
  | kubectl apply -f -

echo "PASS: Slack webhook Secret is present."

echo
echo "Checking Helm repository..."

if ! helm repo list 2>/dev/null \
  | awk 'NR > 1 {print $1}' \
  | grep -qx "${HELM_REPOSITORY_NAME}"; then

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

if ! grep -q "${GRAFANA_HOSTNAME}" "${RENDERED_FILE}"; then
  echo "ERROR: Grafana hostname not found in rendered output."
  exit 1
fi

if ! grep -q "${PROMETHEUS_HOSTNAME}" "${RENDERED_FILE}"; then
  echo "ERROR: Prometheus hostname not found in rendered output."
  exit 1
fi

echo "PASS: Helm rendering checks passed."

echo
echo "WARNING"
echo "This will install:"
echo "- Prometheus"
echo "- Grafana"
echo "- Alertmanager"
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
echo "Waiting for Prometheus Operator CRDs..."

kubectl wait \
  --for=condition=Established \
  crd/prometheusrules.monitoring.coreos.com \
  --timeout=2m

echo "PASS: PrometheusRule CRD is established."

echo
echo "Applying platform alert rules..."

kubectl apply \
  --filename "${RULES_FILE}"

echo "PASS: Platform alert rules applied."

echo
echo "Monitoring stack installation completed."
echo
echo "Next:"
echo "  ./verify.sh"
echo
echo "Installation log:"
echo "${LOG_FILE}"