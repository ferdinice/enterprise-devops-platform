#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_REPO="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

APPLICATION_DIR="${PLATFORM_REPO}/gitops/applications"

APPLICATIONS=(
  "pet-adoption-dev"
  "pet-adoption-staging"
  "pet-adoption-prod"
)

if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "ERROR: Kubernetes cluster is not reachable."
  exit 1
fi

if ! kubectl get crd applications.argoproj.io >/dev/null 2>&1; then
  echo "ERROR: ArgoCD Application CRD does not exist."
  echo "Install ArgoCD first."
  exit 1
fi

for application in "${APPLICATIONS[@]}"; do
  application_file="${APPLICATION_DIR}/${application}.yaml"

  if [[ ! -f "${application_file}" ]]; then
    echo "ERROR: Application manifest not found:"
    echo "${application_file}"
    exit 1
  fi
done

echo "Applying Pet Adoption ArgoCD Applications..."

for application in "${APPLICATIONS[@]}"; do
  kubectl apply \
    --filename "${APPLICATION_DIR}/${application}.yaml"
done

echo
echo "Waiting for DEV and STAGING..."

for application in pet-adoption-dev pet-adoption-staging; do
  for attempt in {1..30}; do

    SYNC_STATUS="$(kubectl get application "${application}" \
      --namespace argocd \
      --output jsonpath='{.status.sync.status}' \
      2>/dev/null || true)"

    HEALTH_STATUS="$(kubectl get application "${application}" \
      --namespace argocd \
      --output jsonpath='{.status.health.status}' \
      2>/dev/null || true)"

    echo "${application} attempt ${attempt}/30: Sync=${SYNC_STATUS:-unknown}, Health=${HEALTH_STATUS:-unknown}"

    if [[ "${SYNC_STATUS}" == "Synced" && "${HEALTH_STATUS}" == "Healthy" ]]; then
      echo "PASS: ${application} is Synced and Healthy."
      break
    fi

    sleep 10
  done
done

echo
echo "Production Application created."
echo "Production does not use automated sync."
echo "Promote and sync production only after staging validation."

echo
echo "Current ArgoCD Applications:"
kubectl get applications \
  --namespace argocd

echo
echo "Pet Adoption GitOps bootstrap completed."