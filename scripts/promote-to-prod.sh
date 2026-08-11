#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

STAGING_FILE="${ROOT_DIR}/gitops/pet-adoption/overlays/staging/kustomization.yaml"
PROD_FILE="${ROOT_DIR}/gitops/pet-adoption/overlays/prod/kustomization.yaml"

STAGING_TAG="$(awk '/newTag:/ {print $2; exit}' "${STAGING_FILE}")"

if [[ -z "${STAGING_TAG}" ]]; then
  echo "ERROR: Could not determine staging image tag."
  exit 1
fi

echo "Production promotion candidate:"
echo "${STAGING_TAG}"
echo
echo "This will promote the exact staging image to production."
echo

read -r -p "Type PROMOTE to continue: " CONFIRMATION

if [[ "${CONFIRMATION}" != "PROMOTE" ]]; then
  echo "Production promotion cancelled."
  exit 0
fi

sed -i \
  "s/newTag: .*/newTag: ${STAGING_TAG}/" \
  "${PROD_FILE}"

echo
echo "Production now references:"
grep "newTag:" "${PROD_FILE}"

echo
echo "Promotion to production completed."