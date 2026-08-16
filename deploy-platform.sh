#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/platform/platform.env"
source "${SCRIPT_DIR}/platform/monitoring/monitoring.env"

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

section "6. Installing cert-manager"

run_script \
  "${PLATFORM_REPOSITORY}/platform/cert-manager/install.sh"

run_script \
  "${PLATFORM_REPOSITORY}/platform/cert-manager/verify.sh"


section "7. Creating Production ClusterIssuer"

ISSUER_FILE="${PLATFORM_REPOSITORY}/platform/cert-manager/issuers/letsencrypt-production.yaml"

if [[ ! -f "${ISSUER_FILE}" ]]; then
  echo "ERROR: Production ClusterIssuer manifest not found:"
  echo "${ISSUER_FILE}"
  exit 1
fi

kubectl apply --server-side \
  --filename "${ISSUER_FILE}"

echo "Waiting for ClusterIssuer ${PRODUCTION_CLUSTER_ISSUER}..."

ISSUER_READY=""

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

if [[ "${ISSUER_READY}" != "True" ]]; then
  echo "ERROR: ClusterIssuer did not become Ready."

  kubectl describe clusterissuer \
    "${PRODUCTION_CLUSTER_ISSUER}" || true

  exit 1
fi


section "8. Creating Pet Adoption Environment DNS"

for hostname in \
  "${DEV_HOSTNAME}" \
  "${STAGING_HOSTNAME}" \
  "${PROD_HOSTNAME}"
do

  echo
  echo "Creating DNS for ${hostname}..."

  run_script \
    "${PLATFORM_REPOSITORY}/platform/dns/create-alias-record.sh" \
    "${hostname}"

  run_script \
    "${PLATFORM_REPOSITORY}/platform/dns/verify-dns.sh" \
    "${hostname}"

done



section "9. Preparing ArgoCD DNS"

run_script \
  "${PLATFORM_REPOSITORY}/platform/dns/create-alias-record.sh" \
  "${ARGOCD_HOSTNAME}"

echo
echo "Waiting for ${ARGOCD_HOSTNAME} to resolve inside Kubernetes..."

ARGOCD_DNS_READY="false"

for attempt in {1..30}; do

  DNS_CHECK_POD="argocd-dns-check-${attempt}"

  if kubectl run "${DNS_CHECK_POD}" \
    --image=busybox:1.36 \
    --restart=Never \
    --rm \
    --attach \
    -- nslookup "${ARGOCD_HOSTNAME}" >/dev/null 2>&1; then

    ARGOCD_DNS_READY="true"

    echo "PASS: ${ARGOCD_HOSTNAME} resolves inside Kubernetes."
    break
  fi

  echo "Attempt ${attempt}/30: DNS not resolvable inside Kubernetes yet."

  # CoreDNS may temporarily retain a negative DNS response
  # if the hostname was queried before the Route53 record existed.
  if [[ "${attempt}" == "12" ]]; then

    echo
    echo "Refreshing CoreDNS after extended DNS propagation delay..."

    kubectl rollout restart deployment coredns \
      --namespace kube-system

    kubectl rollout status deployment coredns \
      --namespace kube-system \
      --timeout=2m
  fi

  sleep 10
done

if [[ "${ARGOCD_DNS_READY}" != "true" ]]; then

  echo "ERROR: ${ARGOCD_HOSTNAME} did not become resolvable inside Kubernetes."

  echo
  echo "CoreDNS diagnostics:"

  kubectl get pods \
    --namespace kube-system \
    --selector k8s-app=kube-dns || true

  exit 1
fi


section "10. Installing ArgoCD"

run_script \
  "${PLATFORM_REPOSITORY}/platform/argocd/install.sh"


section "11. Waiting for ArgoCD TLS Certificate"

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

  echo "Attempt ${attempt}/60: ArgoCD certificate not ready."

  sleep 10
done

if [[ "${ARGOCD_CERT_READY}" != "True" ]]; then

  echo
  echo "ERROR: ArgoCD certificate did not become Ready."

  echo
  echo "Certificate:"
  kubectl describe certificate argocd-server \
    --namespace "${ARGOCD_NAMESPACE}" || true

  echo
  echo "ACME Order and Challenge:"
  kubectl get order,challenge \
    --namespace "${ARGOCD_NAMESPACE}" || true

  exit 1
fi

section "12. Verifying ArgoCD"

run_script \
  "${PLATFORM_REPOSITORY}/platform/argocd/verify.sh"

section "13. Bootstrapping Pet Adoption GitOps Applications"

run_script \
  "${PLATFORM_REPOSITORY}/platform/argocd/applications/bootstrap-pet-adoption.sh"

section "14. Installing Monitoring Stack"

run_script \
  "${PLATFORM_REPOSITORY}/platform/monitoring/install.sh"


section "15. Creating Monitoring DNS"

run_script \
  "${PLATFORM_REPOSITORY}/platform/dns/create-alias-record.sh" \
  "${GRAFANA_HOSTNAME}"

run_script \
  "${PLATFORM_REPOSITORY}/platform/dns/create-alias-record.sh" \
  "${PROMETHEUS_HOSTNAME}"

run_script \
  "${PLATFORM_REPOSITORY}/platform/dns/verify-dns.sh" \
  "${GRAFANA_HOSTNAME}"

run_script \
  "${PLATFORM_REPOSITORY}/platform/dns/verify-dns.sh" \
  "${PROMETHEUS_HOSTNAME}"


section "16. Waiting for Monitoring TLS Certificates"

for certificate_name in grafana-tls prometheus-tls; do

  CERTIFICATE_READY=""

  echo "Waiting for ${certificate_name}..."

  for attempt in {1..60}; do

    CERTIFICATE_READY="$(kubectl get certificate "${certificate_name}" \
      --namespace "${MONITORING_NAMESPACE}" \
      --output jsonpath='{.status.conditions[?(@.type=="Ready")].status}' \
      2>/dev/null || true)"

    if [[ "${CERTIFICATE_READY}" == "True" ]]; then
      echo "PASS: ${certificate_name} is Ready."
      break
    fi

    echo "Attempt ${attempt}/60: ${certificate_name} is not ready."
    sleep 10
  done

  if [[ "${CERTIFICATE_READY}" != "True" ]]; then
    echo
    echo "ERROR: ${certificate_name} did not become Ready."

    kubectl describe certificate "${certificate_name}" \
      --namespace "${MONITORING_NAMESPACE}" || true

    echo
    echo "ACME diagnostics:"

    kubectl get order,challenge \
      --namespace "${MONITORING_NAMESPACE}" || true

    exit 1
  fi
done


section "17. Verifying Monitoring Stack"

run_script \
  "${PLATFORM_REPOSITORY}/platform/monitoring/verify.sh"


section "18. Final Platform Verification"

echo "Pet Adoption Development:"
echo "https://${DEV_HOSTNAME}"

echo
echo "Pet Adoption Staging:"
echo "https://${STAGING_HOSTNAME}"

echo
echo "Pet Adoption Production:"
echo "https://${PROD_HOSTNAME}"
echo "Production requires explicit ArgoCD synchronization after promotion."

echo
echo "ArgoCD:"
echo "https://${ARGOCD_HOSTNAME}"

echo
echo "Grafana:"
echo "https://${GRAFANA_HOSTNAME}"

echo
echo "Prometheus:"
echo "https://${PROMETHEUS_HOSTNAME}"

echo
echo "Deployment log:"
echo "${LOG_FILE}"