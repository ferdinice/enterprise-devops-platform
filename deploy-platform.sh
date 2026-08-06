#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/platform/platform.env"

export AWS_PROFILE
export AWS_REGION

LOG_DIR="${SCRIPT_DIR}/platform/logs"
LOG_FILE="${LOG_DIR}/deploy-platform-$(date +%Y%m%d-%H%M%S).log"

mkdir -p "${LOG_DIR}"

exec > >(tee -a "${LOG_FILE}") 2>&1

section() {
  echo
  echo "=========================================="
  echo " $1"
  echo "=========================================="
}

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "ERROR: ${command_name} is not installed or not in PATH."
    exit 1
  fi
}

run_script() {
  local script_path="$1"
  shift

  if [[ ! -f "${script_path}" ]]; then
    echo "ERROR: Required script does not exist:"
    echo "${script_path}"
    exit 1
  fi

  if [[ ! -x "${script_path}" ]]; then
    echo "ERROR: Script is not executable:"
    echo "${script_path}"
    exit 1
  fi

  "${script_path}" "$@"
}

section "Enterprise Platform Deployment"

echo "AWS profile:            ${AWS_PROFILE}"
echo "AWS region:             ${AWS_REGION}"
echo "Platform repository:    ${PLATFORM_REPOSITORY}"
echo "Application repository: ${APPLICATION_REPOSITORY}"
echo "Log file:               ${LOG_FILE}"

echo
echo "This workflow will create billable AWS resources, including:"
echo "- EC2 instances"
echo "- NAT Gateways"
echo "- Load Balancers"
echo "- EBS volumes"
echo "- Elastic IP addresses"

read -r -p "Type DEPLOY to begin the complete platform deployment: " CONFIRMATION

if [[ "${CONFIRMATION}" != "DEPLOY" ]]; then
  echo "Platform deployment cancelled."
  exit 0
fi

section "Checking Local Dependencies"

for command_name in aws kubectl helm kops git curl; do
  require_command "${command_name}"
  echo "PASS: ${command_name} is available."
done

if [[ ! -d "${PLATFORM_REPOSITORY}" ]]; then
  echo "ERROR: Platform repository was not found."
  exit 1
fi

if [[ ! -d "${APPLICATION_REPOSITORY}" ]]; then
  echo "ERROR: Application repository was not found."
  exit 1
fi

ACCOUNT_ID="$(aws sts get-caller-identity \
  --query Account \
  --output text)"

if [[ "${ACCOUNT_ID}" != "740994137090" ]]; then
  echo "ERROR: Unexpected AWS account: ${ACCOUNT_ID}"
  exit 1
fi

echo "PASS: AWS account ${ACCOUNT_ID} confirmed."

section "1. Creating KOps Configuration"

run_script \
  "${PLATFORM_REPOSITORY}/terraform/kops/create-cluster.sh"

section "2. Provisioning KOps Cluster"

run_script \
  "${PLATFORM_REPOSITORY}/terraform/kops/update-cluster.sh"

section "3. Exporting Kubeconfig"

run_script \
  "${PLATFORM_REPOSITORY}/terraform/kops/export-kubeconfig.sh"

section "4. Validating Kubernetes Cluster"

run_script \
  "${PLATFORM_REPOSITORY}/terraform/kops/validate-cluster.sh"

section "5. Installing NGINX Ingress"

run_script \
  "${PLATFORM_REPOSITORY}/platform/ingress-nginx/install.sh"

run_script \
  "${PLATFORM_REPOSITORY}/platform/ingress-nginx/verify.sh"

section "6. Deploying Pet Adoption Application"

cd "${APPLICATION_REPOSITORY}"

kubectl apply \
  --kustomize kubernetes/overlays/dev

kubectl rollout status \
  deployment/pet-adoption \
  --namespace "${PET_ADOPTION_NAMESPACE}" \
  --timeout=5m

kubectl get deployment,pods,service,ingress \
  --namespace "${PET_ADOPTION_NAMESPACE}"

section "7. Creating Pet Adoption DNS"

cd "${PLATFORM_REPOSITORY}"

run_script \
  "${PLATFORM_REPOSITORY}/platform/dns/create-alias-record.sh" \
  "${PET_ADOPTION_HOSTNAME}"

run_script \
  "${PLATFORM_REPOSITORY}/platform/dns/verify-dns.sh" \
  "${PET_ADOPTION_HOSTNAME}"

section "8. Installing cert-manager"

run_script \
  "${PLATFORM_REPOSITORY}/platform/cert-manager/install.sh"

run_script \
  "${PLATFORM_REPOSITORY}/platform/cert-manager/verify.sh"

section "9. Creating Production ClusterIssuer"

ISSUER_FILE="${PLATFORM_REPOSITORY}/platform/cert-manager/issuers/letsencrypt-production.yaml"

if [[ ! -f "${ISSUER_FILE}" ]]; then
  echo "ERROR: Production ClusterIssuer manifest not found:"
  echo "${ISSUER_FILE}"
  exit 1
fi

kubectl apply --server-side \
  --filename "${ISSUER_FILE}"

echo "Waiting for ClusterIssuer ${PRODUCTION_CLUSTER_ISSUER}..."

for attempt in {1..30}; do
  ISSUER_READY="$(kubectl get clusterissuer \
    "${PRODUCTION_CLUSTER_ISSUER}" \
    --output jsonpath='{.status.conditions[?(@.type=="Ready")].status}' \
    2>/dev/null || true)"

  if [[ "${ISSUER_READY}" == "True" ]]; then
    echo "PASS: ClusterIssuer is Ready."
    break
  fi

  echo "Attempt ${attempt}/30: ClusterIssuer is not ready."
  sleep 10
done

if [[ "${ISSUER_READY:-}" != "True" ]]; then
  echo "ERROR: ClusterIssuer did not become Ready."
  kubectl describe clusterissuer \
    "${PRODUCTION_CLUSTER_ISSUER}" || true
  exit 1
fi

section "10. Creating Pet Adoption Certificate"

PET_CERTIFICATE_FILE="${PLATFORM_REPOSITORY}/platform/cert-manager/issuers/petadoption-production-certificate.yaml"

if [[ ! -f "${PET_CERTIFICATE_FILE}" ]]; then
  echo "ERROR: Pet Adoption Certificate manifest not found:"
  echo "${PET_CERTIFICATE_FILE}"
  exit 1
fi

kubectl apply \
  --filename "${PET_CERTIFICATE_FILE}"

echo "Waiting for Pet Adoption certificate..."

for attempt in {1..60}; do
  PET_CERTIFICATE_READY="$(kubectl get certificate \
    petadoption-production \
    --namespace "${PET_ADOPTION_NAMESPACE}" \
    --output jsonpath='{.status.conditions[?(@.type=="Ready")].status}' \
    2>/dev/null || true)"

  if [[ "${PET_CERTIFICATE_READY}" == "True" ]]; then
    echo "PASS: Pet Adoption certificate is Ready."
    break
  fi

  echo "Attempt ${attempt}/60: certificate is not ready."
  sleep 10
done

if [[ "${PET_CERTIFICATE_READY:-}" != "True" ]]; then
  echo "ERROR: Pet Adoption certificate did not become Ready."
  kubectl describe certificate petadoption-production \
    --namespace "${PET_ADOPTION_NAMESPACE}" || true
  exit 1
fi

echo
echo "Reapplying Pet Adoption manifests after TLS issuance..."

cd "${APPLICATION_REPOSITORY}"

kubectl apply \
  --kustomize kubernetes/overlays/dev

kubectl rollout status \
  deployment/pet-adoption \
  --namespace "${PET_ADOPTION_NAMESPACE}" \
  --timeout=5m

echo
echo "Testing Pet Adoption HTTPS endpoint..."

PET_HTTP_STATUS=""

for attempt in {1..30}; do
  PET_HTTP_STATUS="$(curl \
    --silent \
    --output /dev/null \
    --write-out '%{http_code}' \
    --max-time 20 \
    "https://${PET_ADOPTION_HOSTNAME}" \
    2>/dev/null || true)"

  if [[ "${PET_HTTP_STATUS}" =~ ^(200|301|302|307|308)$ ]]; then
    echo "PASS: Pet Adoption HTTPS returned ${PET_HTTP_STATUS}."
    break
  fi

  echo "Attempt ${attempt}/30: HTTPS returned '${PET_HTTP_STATUS:-no response}'."
  sleep 10
done

if [[ ! "${PET_HTTP_STATUS}" =~ ^(200|301|302|307|308)$ ]]; then
  echo "ERROR: Pet Adoption HTTPS endpoint is not healthy."
  exit 1
fi

cd "${PLATFORM_REPOSITORY}"

section "11. Installing ArgoCD"

run_script \
  "${PLATFORM_REPOSITORY}/platform/argocd/install.sh"

section "12. Creating ArgoCD DNS"

run_script \
  "${PLATFORM_REPOSITORY}/platform/dns/create-alias-record.sh" \
  "${ARGOCD_HOSTNAME}"

echo
echo "Waiting for ArgoCD DNS and TLS certificate validation..."

ARGOCD_CERT_READY=""

for attempt in {1..60}; do
  ARGOCD_CERT_READY="$(kubectl get certificate argocd-server \
    --namespace "${ARGOCD_NAMESPACE}" \
    --output jsonpath='{.status.conditions[?(@.type=="Ready")].status}' \
    2>/dev/null || true)"

  if [[ "${ARGOCD_CERT_READY}" == "True" ]]; then
    echo "PASS: ArgoCD certificate is Ready."
    break
  fi

  echo "Attempt ${attempt}/60: ArgoCD certificate is not ready."
  sleep 10
done

if [[ "${ARGOCD_CERT_READY}" != "True" ]]; then
  echo "ERROR: ArgoCD certificate did not become Ready."

  kubectl describe certificate argocd-server \
    --namespace "${ARGOCD_NAMESPACE}" || true

  kubectl get challenge,order \
    --namespace "${ARGOCD_NAMESPACE}" || true

  exit 1
fi

section "13. Verifying ArgoCD"

run_script \
  "${PLATFORM_REPOSITORY}/platform/argocd/verify.sh"

section "14. Final Platform Verification"

echo "Kubernetes nodes:"
kubectl get nodes

echo
echo "Platform namespaces:"
kubectl get namespaces

echo
echo "Helm releases:"
helm list --all-namespaces

echo
echo "Certificates:"
kubectl get certificates --all-namespaces

echo
echo "Ingress resources:"
kubectl get ingress --all-namespaces

echo
echo "Public endpoint checks:"

curl --fail --silent --show-error \
  --head \
  --max-time 30 \
  "https://${PET_ADOPTION_HOSTNAME}"

curl --fail --silent --show-error \
  --head \
  --max-time 30 \
  "https://${ARGOCD_HOSTNAME}"

section "Platform Deployment Completed"

echo "Pet Adoption:"
echo "https://${PET_ADOPTION_HOSTNAME}"

echo
echo "ArgoCD:"
echo "https://${ARGOCD_HOSTNAME}"

echo
echo "Deployment log:"
echo "${LOG_FILE}"