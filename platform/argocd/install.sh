#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/argocd.env"

export AWS_PROFILE
export AWS_REGION

VALUES_FILE="${SCRIPT_DIR}/values.yaml"
LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/install-$(date +%Y%m%d-%H%M%S).log"

mkdir -p "${LOG_DIR}"

exec > >(tee -a "${LOG_FILE}") 2>&1

echo "=========================================="
echo " Install ArgoCD"
echo "=========================================="
echo "Release:       ${RELEASE_NAME}"
echo "Namespace:     ${NAMESPACE}"
echo "Chart:         ${CHART_NAME}"
echo "Chart version: ${CHART_VERSION}"
echo "Hostname:      ${ARGOCD_HOSTNAME}"
echo "Values file:   ${VALUES_FILE}"
echo "Log file:      ${LOG_FILE}"
echo "=========================================="

# ---------------------------------------------------------
# 1. Local dependency checks
# ---------------------------------------------------------

for command in helm kubectl; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "ERROR: ${command} is not installed or not in PATH."
    exit 1
  fi
done

if [[ ! -f "${VALUES_FILE}" ]]; then
  echo "ERROR: values.yaml was not found:"
  echo "${VALUES_FILE}"
  exit 1
fi

# ---------------------------------------------------------
# 2. Kubernetes connectivity
# ---------------------------------------------------------

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

# ---------------------------------------------------------
# 3. Platform dependency checks
# ---------------------------------------------------------

echo
echo "Checking platform dependencies..."

if ! kubectl get ingressclass "${INGRESS_CLASS_NAME}" >/dev/null 2>&1; then
  echo "ERROR: IngressClass '${INGRESS_CLASS_NAME}' does not exist."
  echo "Install NGINX Ingress first."
  exit 1
fi

echo "PASS: IngressClass '${INGRESS_CLASS_NAME}' exists."

if ! kubectl get crd certificates.cert-manager.io >/dev/null 2>&1; then
  echo "ERROR: cert-manager Certificate CRD does not exist."
  echo "Install cert-manager first."
  exit 1
fi

echo "PASS: cert-manager CRDs exist."

ISSUER_READY="$(kubectl get clusterissuer "${CLUSTER_ISSUER_NAME}" \
  --output jsonpath='{.status.conditions[?(@.type=="Ready")].status}' \
  2>/dev/null || true)"

if [[ "${ISSUER_READY}" != "True" ]]; then
  echo "ERROR: ClusterIssuer '${CLUSTER_ISSUER_NAME}' is not Ready."
  echo "Current status: ${ISSUER_READY:-missing}"
  exit 1
fi

echo "PASS: ClusterIssuer '${CLUSTER_ISSUER_NAME}' is Ready."

# ---------------------------------------------------------
# 4. Helm repository
# ---------------------------------------------------------

if ! helm repo list 2>/dev/null |
  awk 'NR > 1 {print $1}' |
  grep -qx "${HELM_REPOSITORY_NAME}"; then

  echo
  echo "Adding Argo Helm repository..."

  helm repo add \
    "${HELM_REPOSITORY_NAME}" \
    "${HELM_REPOSITORY_URL}"
else
  echo "Argo Helm repository already exists."
fi

echo
echo "Updating Helm repositories..."

helm repo update

# ---------------------------------------------------------
# 5. Verify pinned chart version
# ---------------------------------------------------------

echo
echo "Confirming pinned chart version exists..."

if ! helm search repo "${CHART_NAME}" \
  --versions |
  awk 'NR > 1 {print $2}' |
  grep -qx "${CHART_VERSION}"; then

  echo "ERROR: Chart version ${CHART_VERSION} was not found."
  echo
  echo "Available chart versions:"
  helm search repo "${CHART_NAME}" --versions | head -10
  exit 1
fi

echo "PASS: Chart version ${CHART_VERSION} exists."

# ---------------------------------------------------------
# 6. Render and validate Helm manifests
# ---------------------------------------------------------

echo
echo "Rendering chart before installation..."

RENDERED_FILE="$(mktemp)"

cleanup_rendered_file() {
  rm -f "${RENDERED_FILE}"
}

trap cleanup_rendered_file EXIT

helm template "${RELEASE_NAME}" \
  "${CHART_NAME}" \
  --namespace "${NAMESPACE}" \
  --version "${CHART_VERSION}" \
  --api-versions cert-manager.io/v1 \
  --api-versions cert-manager.io/v1/Certificate \
  --values "${VALUES_FILE}" \
  > "${RENDERED_FILE}"

if [[ ! -s "${RENDERED_FILE}" ]]; then
  echo "ERROR: Helm produced an empty manifest."
  exit 1
fi

if ! grep -q "^kind: Ingress$" "${RENDERED_FILE}"; then
  echo "ERROR: Rendered output does not contain the ArgoCD Ingress."
  exit 1
fi

if ! grep -q "^kind: Certificate$" "${RENDERED_FILE}"; then
  echo "ERROR: Rendered output does not contain the ArgoCD Certificate."
  exit 1
fi

if ! grep -q "${ARGOCD_HOSTNAME}" "${RENDERED_FILE}"; then
  echo "ERROR: Rendered output does not contain ${ARGOCD_HOSTNAME}."
  exit 1
fi

if ! grep -q "${CLUSTER_ISSUER_NAME}" "${RENDERED_FILE}"; then
  echo "ERROR: Rendered output does not reference ${CLUSTER_ISSUER_NAME}."
  exit 1
fi

echo "PASS: Helm rendering checks passed."

# ---------------------------------------------------------
# 7. Confirmation
# ---------------------------------------------------------

echo
echo "WARNING"
echo "This installs ArgoCD and creates:"
echo "- ArgoCD controllers and services"
echo "- ArgoCD CRDs"
echo "- An Ingress for ${ARGOCD_HOSTNAME}"
echo "- A Let's Encrypt Certificate request"
echo

read -r -p "Type INSTALL to continue: " CONFIRMATION

if [[ "${CONFIRMATION}" != "INSTALL" ]]; then
  echo "Installation cancelled."
  exit 1
fi

# ---------------------------------------------------------
# 8. Install / upgrade ArgoCD
# ---------------------------------------------------------

echo
echo "Installing or upgrading ArgoCD..."

helm upgrade --install "${RELEASE_NAME}" \
  "${CHART_NAME}" \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  --version "${CHART_VERSION}" \
  --values "${VALUES_FILE}" \
  --wait=legacy \
  --timeout 15m

# ---------------------------------------------------------
# 9. Verify workload rollouts
# ---------------------------------------------------------

echo
echo "Waiting for ArgoCD deployments..."

DEPLOYMENTS=(
  argocd-server
  argocd-repo-server
  argocd-applicationset-controller
)

for deployment in "${DEPLOYMENTS[@]}"; do
  kubectl rollout status \
    deployment/"${deployment}" \
    --namespace "${NAMESPACE}" \
    --timeout=5m
done

if kubectl get statefulset argocd-application-controller \
  --namespace "${NAMESPACE}" >/dev/null 2>&1; then

  kubectl rollout status \
    statefulset/argocd-application-controller \
    --namespace "${NAMESPACE}" \
    --timeout=5m
fi

# ---------------------------------------------------------
# 10. Finish
# ---------------------------------------------------------

echo
echo "ArgoCD installation completed."
echo "The TLS certificate will become Ready after DNS is created."
echo
echo "Next:"
echo "  ../../dns/create-alias-record.sh ${ARGOCD_HOSTNAME}"
echo "  ./verify.sh"
echo
echo "Installation log:"
echo "${LOG_FILE}"