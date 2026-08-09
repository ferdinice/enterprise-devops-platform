#!/bin/bash
set -euo pipefail

GITOPS_REPO="/c/DevOps-Lab/enterprise-gitops"
APPLICATION_FILE="${GITOPS_REPO}/applications/pet-adoption-dev.yaml"

if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "ERROR: Kubernetes cluster is not reachable."
  exit 1
fi

if ! kubectl get crd applications.argoproj.io >/dev/null 2>&1; then
  echo "ERROR: ArgoCD Application CRD does not exist."
  echo "Install ArgoCD first."
  exit 1
fi

if [[ ! -f "${APPLICATION_FILE}" ]]; then
  echo "ERROR: Application manifest not found:"
  echo "${APPLICATION_FILE}"
  exit 1
fi

echo "Applying Pet Adoption ArgoCD Application..."

kubectl apply \
  --filename "${APPLICATION_FILE}"

echo
echo "Waiting for ArgoCD Application..."

for attempt in {1..30}; do
  SYNC_STATUS="$(kubectl get application pet-adoption-dev \
    --namespace argocd \
    --output jsonpath='{.status.sync.status}' \
    2>/dev/null || true)"

  HEALTH_STATUS="$(kubectl get application pet-adoption-dev \
    --namespace argocd \
    --output jsonpath='{.status.health.status}' \
    2>/dev/null || true)"

  echo "Attempt ${attempt}/30: Sync=${SYNC_STATUS:-unknown}, Health=${HEALTH_STATUS:-unknown}"

  if [[ "${SYNC_STATUS}" == "Synced" && "${HEALTH_STATUS}" == "Healthy" ]]; then
    echo
    echo "PASS: Pet Adoption is Synced and Healthy."
    exit 0
  fi

  sleep 10
done

echo
echo "ERROR: Pet Adoption did not become Synced and Healthy."

kubectl describe application pet-adoption-dev \
  --namespace argocd || true

exit 1