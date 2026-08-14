#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/platform/platform.env"
source "${SCRIPT_DIR}/platform/monitoring/monitoring.env"

export AWS_PROFILE
export AWS_REGION

LOG_DIR="${SCRIPT_DIR}/platform/logs"
LOG_FILE="${LOG_DIR}/destroy-platform-$(date +%Y%m%d-%H%M%S).log"

mkdir -p "${LOG_DIR}"

exec > >(tee -a "${LOG_FILE}") 2>&1

FAILURES=0

section() {
  echo
  echo "=========================================="
  echo " $1"
  echo "=========================================="
}

record_failure() {
  echo "WARNING: $1"
  FAILURES=$((FAILURES + 1))
}

run_cleanup_script() {
  local description="$1"
  local script_path="$2"
  shift 2

  echo
  echo "Running: ${description}"

  if [[ ! -f "${script_path}" ]]; then
    record_failure "Script not found: ${script_path}"
    return
  fi

  if [[ ! -x "${script_path}" ]]; then
    record_failure "Script is not executable: ${script_path}"
    return
  fi

  if ! "${script_path}" "$@"; then
    record_failure "${description} reported an error."
  fi
}

section "Enterprise Platform Destruction"

echo "AWS profile: ${AWS_PROFILE}"
echo "AWS region:  ${AWS_REGION}"
echo "Log file:    ${LOG_FILE}"

echo
echo "DANGER"
echo "This workflow removes:"
echo "- Application DNS records"
echo "- ArgoCD"
echo "- cert-manager"
echo "- NGINX Ingress Controller"
echo "- The complete KOps cluster"
echo "- Billable AWS cluster resources"
echo "- Monitoring stack"
echo "- Grafana and Prometheus DNS records"

read -r -p "Type DESTROY-PLATFORM to continue: " CONFIRMATION

if [[ "${CONFIRMATION}" != "DESTROY-PLATFORM" ]]; then
  echo "Platform destruction cancelled."
  exit 0
fi

section "1. Deleting Grafana DNS"

run_cleanup_script \
  "Delete Grafana DNS" \
  "${PLATFORM_REPOSITORY}/platform/dns/delete-alias-record.sh" \
  "${GRAFANA_HOSTNAME}"


section "2. Deleting Prometheus DNS"

run_cleanup_script \
  "Delete Prometheus DNS" \
  "${PLATFORM_REPOSITORY}/platform/dns/delete-alias-record.sh" \
  "${PROMETHEUS_HOSTNAME}"


section "3. Uninstalling Monitoring"

run_cleanup_script \
  "Uninstall Monitoring" \
  "${PLATFORM_REPOSITORY}/platform/monitoring/uninstall.sh"

section "4. Deleting ArgoCD DNS"

run_cleanup_script \
  "Delete ArgoCD DNS" \
  "${PLATFORM_REPOSITORY}/platform/dns/delete-alias-record.sh" \
  "${ARGOCD_HOSTNAME}"

section "5. Uninstalling ArgoCD"

run_cleanup_script \
  "Uninstall ArgoCD" \
  "${PLATFORM_REPOSITORY}/platform/argocd/uninstall.sh"

section "6. Deleting Pet Adoption DNS"

run_cleanup_script \
  "Delete Pet Adoption DNS" \
  "${PLATFORM_REPOSITORY}/platform/dns/delete-alias-record.sh" \
  "${PET_ADOPTION_HOSTNAME}"

section "7. Uninstalling cert-manager"

run_cleanup_script \
  "Uninstall cert-manager" \
  "${PLATFORM_REPOSITORY}/platform/cert-manager/uninstall.sh"

section "8. Uninstalling NGINX Ingress"

run_cleanup_script \
  "Uninstall NGINX Ingress" \
  "${PLATFORM_REPOSITORY}/platform/ingress-nginx/uninstall.sh"

section "9. Deleting KOps Cluster"

run_cleanup_script \
  "Delete KOps cluster" \
  "${PLATFORM_REPOSITORY}/terraform/kops/delete-cluster.sh"

section "10. Verifying AWS Cleanup"

if [[ -x "${PLATFORM_REPOSITORY}/terraform/kops/verify-cleanup.sh" ]]; then
  if ! "${PLATFORM_REPOSITORY}/terraform/kops/verify-cleanup.sh"; then
    record_failure "AWS cleanup verification reported a problem."
  fi
else
  record_failure "verify-cleanup.sh was not found or executable."
fi

section "11. Destruction Summary"

if [[ "${FAILURES}" -gt 0 ]]; then
  echo "Platform destruction completed with ${FAILURES} warning(s)."
  echo "Review every warning and inspect:"
  echo "${LOG_FILE}"
  exit 1
fi

echo "Platform destruction completed successfully."
echo "No cleanup errors were reported."
echo
echo "Destruction log:"
echo "${LOG_FILE}"