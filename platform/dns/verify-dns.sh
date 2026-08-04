#!/bin/bash
set -euo pipefail

RECORD_NAME="${1:-}"

if [[ -z "${RECORD_NAME}" ]]; then
  echo "Usage: $0 <hostname>"
  exit 1
fi

echo "Resolving ${RECORD_NAME}..."
nslookup "${RECORD_NAME}"

echo
echo "Testing HTTP..."
curl --fail --silent --show-error \
  --head \
  --max-time 30 \
  "http://${RECORD_NAME}"