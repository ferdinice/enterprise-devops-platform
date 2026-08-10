#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/monitoring.env"

FAILURES=0

pass() {
  echo "PASS: $1"
}

fail() {
  echo "FAIL: $1"
  FAILURES=$((FAILURES + 1))
}

echo "=========================================="
echo " Verify Monitoring Stack"
echo "=========================================="
echo "Namespace: ${MONITORING_NAMESPACE}"
echo "Release:   ${RELEASE_NAME}"
echo "=========================================="

echo
echo "1. Helm release"

if helm status "${RELEASE_NAME}" \
  --namespace "${MONITORING_NAMESPACE}" >/dev/null 2>&1; then
  pass "Helm release exists."
else
  fail "Helm release does not exist."
fi

echo
echo "2. Monitoring Pods"

kubectl get pods \
  --namespace "${MONITORING_NAMESPACE}" \
  --output wide || true

TOTAL_PODS="$(kubectl get pods \
  --namespace "${MONITORING_NAMESPACE}" \
  --no-headers 2>/dev/null | wc -l | tr -d ' ')"

if [[ "${TOTAL_PODS}" == "0" ]]; then
  fail "No monitoring Pods were found."
else
  NOT_READY="$(kubectl get pods \
    --namespace "${MONITORING_NAMESPACE}" \
    --no-headers 2>/dev/null |
    awk '$3 != "Running" {count++} END {print count+0}')"

  if [[ "${NOT_READY}" == "0" ]]; then
    pass "All ${TOTAL_PODS} monitoring Pods are Running."
  else
    fail "${NOT_READY} monitoring Pods are not Running."
  fi
fi

echo
echo "3. Prometheus"

if kubectl get prometheus \
  --namespace "${MONITORING_NAMESPACE}" >/dev/null 2>&1; then
  pass "Prometheus resource exists."
else
  fail "Prometheus resource does not exist."
fi

echo
echo "4. Grafana Service"

GRAFANA_SERVICE="$(kubectl get svc \
  --namespace "${MONITORING_NAMESPACE}" \
  -l app.kubernetes.io/name=grafana \
  -o jsonpath='{.items[0].metadata.name}' \
  2>/dev/null || true)"

if [[ -n "${GRAFANA_SERVICE}" ]]; then
  pass "Grafana Service exists: ${GRAFANA_SERVICE}"
else
  fail "Grafana Service was not found."
fi

echo
echo "5. Ingress"

GRAFANA_INGRESS_HOST="$(kubectl get ingress \
  --namespace "${MONITORING_NAMESPACE}" \
  -o jsonpath='{range .items[*]}{range .spec.rules[*]}{.host}{"\n"}{end}{end}' \
  2>/dev/null | grep -Fx "${GRAFANA_HOSTNAME}" || true)"

if [[ "${GRAFANA_INGRESS_HOST}" == "${GRAFANA_HOSTNAME}" ]]; then
  pass "Grafana Ingress hostname is ${GRAFANA_HOSTNAME}."
else
  fail "Grafana Ingress hostname is missing."
fi

PROMETHEUS_INGRESS_HOST="$(kubectl get ingress \
  --namespace "${MONITORING_NAMESPACE}" \
  -o jsonpath='{range .items[*]}{range .spec.rules[*]}{.host}{"\n"}{end}{end}' \
  2>/dev/null | grep -Fx "${PROMETHEUS_HOSTNAME}" || true)"

if [[ "${PROMETHEUS_INGRESS_HOST}" == "${PROMETHEUS_HOSTNAME}" ]]; then
  pass "Prometheus Ingress hostname is ${PROMETHEUS_HOSTNAME}."
else
  fail "Prometheus Ingress hostname is missing."
fi

echo
echo "6. TLS Certificates"

for secret_name in grafana-tls prometheus-tls; do
  if kubectl get secret "${secret_name}" \
    --namespace "${MONITORING_NAMESPACE}" >/dev/null 2>&1; then
    pass "TLS Secret '${secret_name}' exists."
  else
    fail "TLS Secret '${secret_name}' is missing."
  fi
done

echo
echo "7. Metrics Components"

if kubectl get deployment \
  --namespace "${MONITORING_NAMESPACE}" \
  -l app.kubernetes.io/name=kube-state-metrics \
  >/dev/null 2>&1; then
  pass "kube-state-metrics is deployed."
else
  fail "kube-state-metrics is missing."
fi

if kubectl get daemonset \
  --namespace "${MONITORING_NAMESPACE}" \
  -l app.kubernetes.io/name=prometheus-node-exporter \
  >/dev/null 2>&1; then
  pass "node-exporter is deployed."
else
  fail "node-exporter is missing."
fi

echo
echo "=========================================="

if [[ "${FAILURES}" -eq 0 ]]; then
  echo "All monitoring checks passed."
  exit 0
fi

echo "Verification failed with ${FAILURES} problem(s)."
exit 1