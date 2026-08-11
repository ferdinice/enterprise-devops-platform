#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DEV_FILE="${ROOT_DIR}/gitops/pet-adoption/overlays/dev/kustomization.yaml"
STAGING_FILE="${ROOT_DIR}/gitops/pet-adoption/overlays/staging/kustomization.yaml"

DEV_TAG="$(awk '/newTag:/ {print $2; exit}' "${DEV_FILE}")"

if [[ -z "${DEV_TAG}" ]]; then
  echo "ERROR: Could not determine dev image tag."
  exit 1
fi

echo "Promoting image to staging:"
echo "${DEV_TAG}"

sed -i \
  "s/newTag: .*/newTag: ${DEV_TAG}/" \
  "${STAGING_FILE}"

echo
echo "Staging now references:"
grep "newTag:" "${STAGING_FILE}"

echo
echo "Promotion to staging completed."