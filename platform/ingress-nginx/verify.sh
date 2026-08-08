#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/ingress.env"

export AWS_PROFILE
export AWS_REGION

FAILURES=0

pass() {
  echo "PASS: $1"
}

fail() {
  echo "FAIL: $1"
  FAILURES=$((FAILURES + 1))
}

echo "=========================================="
echo " Verify NGINX Ingress Controller"
echo "=========================================="
echo "Release:   ${RELEASE_NAME}"
echo "Namespace: ${NAMESPACE}"
echo "=========================================="

for command in helm kubectl; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "ERROR: ${command} is not installed or is not in PATH."
    exit 1
  fi
done

if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "ERROR: Kubernetes cluster is not reachable."
  exit 1
fi

echo
echo "1. Helm release"

if helm status "${RELEASE_NAME}" \
  --namespace "${NAMESPACE}" >/dev/null 2>&1; then
  pass "Helm release exists."
else
  fail "Helm release does not exist."
fi

echo
echo "2. Controller deployment"

AVAILABLE_REPLICAS="$(kubectl get deployment ingress-nginx-controller \
  --namespace "${NAMESPACE}" \
  --output jsonpath='{.status.availableReplicas}' \
  2>/dev/null || true)"

AVAILABLE_REPLICAS="${AVAILABLE_REPLICAS:-0}"

if [[ "${AVAILABLE_REPLICAS}" == "${EXPECTED_REPLICAS}" ]]; then
  pass "${AVAILABLE_REPLICAS}/${EXPECTED_REPLICAS} controller replicas are available."
else
  fail "Expected ${EXPECTED_REPLICAS} replicas; found ${AVAILABLE_REPLICAS}."
fi

echo
echo "3. Controller Pods"

echo
echo "3. Controller Pods"

kubectl get pods \
  --namespace "${NAMESPACE}" \
  --selector app.kubernetes.io/component=controller \
  --output wide || true

TOTAL_PODS="$(kubectl get pods \
  --namespace "${NAMESPACE}" \
  --selector app.kubernetes.io/component=controller \
  --no-headers 2>/dev/null |
  wc -l |
  tr -d ' ')"

if [[ "${TOTAL_PODS}" == "0" ]]; then
  fail "No NGINX controller Pods were found."
else
  NOT_READY_PODS="$(kubectl get pods \
    --namespace "${NAMESPACE}" \
    --selector app.kubernetes.io/component=controller \
    --no-headers 2>/dev/null |
    awk '$2 != "1/1" || $3 != "Running" {count++} END {print count+0}')"

  if [[ "${NOT_READY_PODS}" == "0" ]]; then
    pass "All ${TOTAL_PODS} controller Pods are Running and Ready."
  else
    fail "${NOT_READY_PODS} of ${TOTAL_PODS} controller Pods are unhealthy."
  fi
fi

echo
echo "4. Controller Service"

SERVICE_TYPE="$(kubectl get service "${CONTROLLER_SERVICE}" \
  --namespace "${NAMESPACE}" \
  --output jsonpath='{.spec.type}' \
  2>/dev/null || true)"

if [[ "${SERVICE_TYPE}" == "LoadBalancer" ]]; then
  pass "Controller Service type is LoadBalancer."
else
  fail "Controller Service type is '${SERVICE_TYPE:-missing}'."
fi

echo
echo "5. External hostname"

INGRESS_HOSTNAME="$(kubectl get service "${CONTROLLER_SERVICE}" \
  --namespace "${NAMESPACE}" \
  --output jsonpath='{.status.loadBalancer.ingress[0].hostname}' \
  2>/dev/null || true)"

if [[ -n "${INGRESS_HOSTNAME}" ]]; then
  pass "External hostname is assigned."
  echo "${INGRESS_HOSTNAME}"
else
  fail "External load-balancer hostname is not assigned."
fi

echo
echo "6. IngressClass"

if kubectl get ingressclass "${INGRESS_CLASS_NAME}" >/dev/null 2>&1; then
  pass "IngressClass '${INGRESS_CLASS_NAME}' exists."
else
  fail "IngressClass '${INGRESS_CLASS_NAME}' does not exist."
fi

echo
echo "7. Controller metrics Service"

if kubectl get service ingress-nginx-controller-metrics \
  --namespace "${NAMESPACE}" >/dev/null 2>&1; then
  pass "Metrics Service exists."
else
  fail "Metrics Service does not exist."
fi

echo
echo "=========================================="

if [[ "${FAILURES}" -gt 0 ]]; then
  echo "Verification failed with ${FAILURES} problem(s)."
  exit 1
fi

echo "All NGINX Ingress checks passed."