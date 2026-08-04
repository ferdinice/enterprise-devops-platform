#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/dns.env"

export AWS_PROFILE
export AWS_REGION

RECORD_NAME="${1:-}"

if [[ -z "${RECORD_NAME}" ]]; then
  echo "Usage: $0 <hostname>"
  exit 1
fi

RECORD_JSON="$(aws route53 list-resource-record-sets \
  --hosted-zone-id "${HOSTED_ZONE_ID}" \
  --query "ResourceRecordSets[?Name=='${RECORD_NAME}.'] | [0]" \
  --output json)"

if [[ "${RECORD_JSON}" == "null" ]]; then
  echo "DNS record does not exist: ${RECORD_NAME}"
  exit 0
fi

echo "Record scheduled for deletion:"
echo "${RECORD_JSON}"

read -r -p "Type DELETE to remove ${RECORD_NAME}: " CONFIRMATION

if [[ "${CONFIRMATION}" != "DELETE" ]]; then
  echo "Deletion cancelled."
  exit 0
fi

CHANGE_FILE="$(mktemp)"

cat > "${CHANGE_FILE}" <<EOF
{
  "Comment": "Delete ${RECORD_NAME}",
  "Changes": [
    {
      "Action": "DELETE",
      "ResourceRecordSet": ${RECORD_JSON}
    }
  ]
}
EOF

CHANGE_ID="$(aws route53 change-resource-record-sets \
  --hosted-zone-id "${HOSTED_ZONE_ID}" \
  --change-batch "$(cat "${CHANGE_FILE}")" \
  --query ChangeInfo.Id \
  --output text)"

rm -f "${CHANGE_FILE}"

aws route53 wait resource-record-sets-changed \
  --id "${CHANGE_ID}"

echo "DNS record deleted."