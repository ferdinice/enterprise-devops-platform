#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/cert-manager.env"

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
echo " Verify cert-manager"
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

check_deployment() {
  local deployment="$1"
  local expected="$2"

  local available
  available="$(kubectl get deployment "${deployment}" \
    --namespace "${NAMESPACE}" \
    --output jsonpath='{.status.availableReplicas}' \
    2>/dev/null || true)"

  available="${available:-0}"

  if [[ "${available}" == "${expected}" ]]; then
    pass "${deployment}: ${available}/${expected} replicas available."
  else
    fail "${deployment}: expected ${expected}; found ${available}."
  fi
}

echo
echo "2. Controller deployments"

check_deployment \
  "cert-manager" \
  "${EXPECTED_CONTROLLER_REPLICAS}"

check_deployment \
  "cert-manager-webhook" \
  "${EXPECTED_WEBHOOK_REPLICAS}"

check_deployment \
  "cert-manager-cainjector" \
  "${EXPECTED_CAINJECTOR_REPLICAS}"

echo
echo "3. Pods"

kubectl get pods \
  --namespace "${NAMESPACE}" \
  --output wide || true

NOT_READY_PODS="$(kubectl get pods \
  --namespace "${NAMESPACE}" \
  --no-headers 2>/dev/null |
  awk '$2 != "1/1" || $3 != "Running" {count++} END {print count+0}')"

if [[ "${NOT_READY_PODS}" == "0" ]]; then
  pass "All cert-manager Pods are Running and Ready."
else
  fail "${NOT_READY_PODS} cert-manager Pod or Pods are unhealthy."
fi

echo
echo "4. Required CRDs"

REQUIRED_CRDS=(
  certificates.cert-manager.io
  certificaterequests.cert-manager.io
  issuers.cert-manager.io
  clusterissuers.cert-manager.io
  challenges.acme.cert-manager.io
  orders.acme.cert-manager.io
)

for crd in "${REQUIRED_CRDS[@]}"; do
  if kubectl get crd "${crd}" >/dev/null 2>&1; then
    pass "CRD exists: ${crd}"
  else
    fail "CRD missing: ${crd}"
  fi
done

echo
echo "5. Webhook Service"

if kubectl get service cert-manager-webhook \
  --namespace "${NAMESPACE}" >/dev/null 2>&1; then
  pass "Webhook Service exists."
else
  fail "Webhook Service is missing."
fi

echo
echo "6. Kubernetes API discovery"

if kubectl api-resources \
  --api-group=cert-manager.io |
  grep -q "certificates"; then

  pass "cert-manager API resources are discoverable."
else
  fail "cert-manager API resources are not discoverable."
fi

echo
echo "=========================================="

if [[ "${FAILURES}" -gt 0 ]]; then
  echo "Verification failed with ${FAILURES} problem(s)."
  exit 1
fi

echo "All cert-manager checks passed."