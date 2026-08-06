#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/argocd.env"

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

echo "=========================================="
echo " Verify ArgoCD"
echo "=========================================="
echo "Release:   ${RELEASE_NAME}"
echo "Namespace: ${NAMESPACE}"
echo "Hostname:  ${ARGOCD_HOSTNAME}"
echo "=========================================="

for command in helm kubectl; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "ERROR: ${command} is not installed or not in PATH."
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
echo "2. ArgoCD deployments"

check_deployment \
  "argocd-server" \
  "${EXPECTED_SERVER_REPLICAS}"

check_deployment \
  "argocd-repo-server" \
  "${EXPECTED_REPO_SERVER_REPLICAS}"

check_deployment \
  "argocd-applicationset-controller" \
  "${EXPECTED_APPLICATIONSET_REPLICAS}"

echo
echo "3. Application controller"

CONTROLLER_READY="$(kubectl get statefulset argocd-application-controller \
  --namespace "${NAMESPACE}" \
  --output jsonpath='{.status.readyReplicas}' \
  2>/dev/null || true)"

CONTROLLER_READY="${CONTROLLER_READY:-0}"

if [[ "${CONTROLLER_READY}" == "${EXPECTED_CONTROLLER_REPLICAS}" ]]; then
  pass "Application controller: ${CONTROLLER_READY}/${EXPECTED_CONTROLLER_REPLICAS} ready."
else
  fail "Application controller expected ${EXPECTED_CONTROLLER_REPLICAS}; found ${CONTROLLER_READY}."
fi

echo
echo "4. Pods"

kubectl get pods \
  --namespace "${NAMESPACE}" \
  --output wide || true

UNHEALTHY_PODS="$(kubectl get pods \
  --namespace "${NAMESPACE}" \
  --no-headers 2>/dev/null |
  awk '
    {
      split($2, ready, "/")
      if (ready[1] != ready[2] || $3 != "Running") count++
    }
    END {print count+0}
  ')"

if [[ "${UNHEALTHY_PODS}" == "0" ]]; then
  pass "All ArgoCD Pods are Running and Ready."
else
  fail "${UNHEALTHY_PODS} ArgoCD Pod or Pods are unhealthy."
fi

echo
echo "5. Server Service"

SERVICE_TYPE="$(kubectl get service "${SERVER_SERVICE}" \
  --namespace "${NAMESPACE}" \
  --output jsonpath='{.spec.type}' \
  2>/dev/null || true)"

if [[ "${SERVICE_TYPE}" == "ClusterIP" ]]; then
  pass "ArgoCD Server Service is ClusterIP."
else
  fail "Expected ClusterIP; found '${SERVICE_TYPE:-missing}'."
fi

echo
echo "6. Ingress"

INGRESS_HOST="$(kubectl get ingress argocd-server \
  --namespace "${NAMESPACE}" \
  --output jsonpath='{.spec.rules[0].host}' \
  2>/dev/null || true)"

if [[ "${INGRESS_HOST}" == "${ARGOCD_HOSTNAME}" ]]; then
  pass "Ingress hostname is ${ARGOCD_HOSTNAME}."
else
  fail "Ingress hostname is '${INGRESS_HOST:-missing}'."
fi

INGRESS_CLASS="$(kubectl get ingress argocd-server \
  --namespace "${NAMESPACE}" \
  --output jsonpath='{.spec.ingressClassName}' \
  2>/dev/null || true)"

if [[ "${INGRESS_CLASS}" == "${INGRESS_CLASS_NAME}" ]]; then
  pass "IngressClass is ${INGRESS_CLASS_NAME}."
else
  fail "IngressClass is '${INGRESS_CLASS:-missing}'."
fi

echo
echo "7. TLS Certificate"

CERTIFICATE_READY="$(kubectl get certificate argocd-server \
  --namespace "${NAMESPACE}" \
  --output jsonpath='{.status.conditions[?(@.type=="Ready")].status}' \
  2>/dev/null || true)"

if [[ "${CERTIFICATE_READY}" == "True" ]]; then
  pass "ArgoCD Certificate is Ready."
else
  fail "ArgoCD Certificate is not Ready."
fi

if kubectl get secret "${TLS_SECRET_NAME}" \
  --namespace "${NAMESPACE}" >/dev/null 2>&1; then

  pass "TLS Secret '${TLS_SECRET_NAME}' exists."
else
  fail "TLS Secret '${TLS_SECRET_NAME}' is missing."
fi

echo
echo "8. ArgoCD CRDs"

REQUIRED_CRDS=(
  applications.argoproj.io
  applicationsets.argoproj.io
  appprojects.argoproj.io
)

for crd in "${REQUIRED_CRDS[@]}"; do
  if kubectl get crd "${crd}" >/dev/null 2>&1; then
    pass "CRD exists: ${crd}"
  else
    fail "CRD missing: ${crd}"
  fi
done

echo
echo "9. HTTPS endpoint"

if command -v curl >/dev/null 2>&1; then
  HTTP_STATUS="$(curl \
    --silent \
    --output /dev/null \
    --write-out '%{http_code}' \
    --max-time 30 \
    "https://${ARGOCD_HOSTNAME}" \
    2>/dev/null || true)"

  if [[ "${HTTP_STATUS}" =~ ^(200|302|307)$ ]]; then
    pass "HTTPS endpoint responded with status ${HTTP_STATUS}."
  else
    fail "HTTPS endpoint returned '${HTTP_STATUS:-no response}'."
  fi
else
  echo "SKIP: curl is not installed."
fi

echo
echo "=========================================="

if [[ "${FAILURES}" -gt 0 ]]; then
  echo "Verification failed with ${FAILURES} problem(s)."
  exit 1
fi

echo "All ArgoCD checks passed."