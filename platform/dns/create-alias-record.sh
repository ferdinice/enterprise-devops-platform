#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/dns.env"

export AWS_PROFILE
export AWS_REGION

RECORD_NAME="${1:-}"

if [[ -z "${RECORD_NAME}" ]]; then
  echo "Usage: $0 <hostname>"
  echo "Example: $0 petadoption.ferdeve.fit"
  exit 1
fi

for command in aws kubectl; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "ERROR: ${command} is not installed or not in PATH."
    exit 1
  fi
done

CURRENT_ACCOUNT_ID="$(aws sts get-caller-identity \
  --query Account \
  --output text)"

if [[ "${CURRENT_ACCOUNT_ID}" != "740994137090" ]]; then
  echo "ERROR: Wrong AWS account: ${CURRENT_ACCOUNT_ID}"
  exit 1
fi

INGRESS_HOSTNAME="$(kubectl get service "${INGRESS_SERVICE}" \
  --namespace "${INGRESS_NAMESPACE}" \
  --output jsonpath='{.status.loadBalancer.ingress[0].hostname}')"

if [[ -z "${INGRESS_HOSTNAME}" ]]; then
  echo "ERROR: Ingress load-balancer hostname is not available."
  exit 1
fi

CLASSIC_ZONE_ID="$(aws elb describe-load-balancers \
  --region "${AWS_REGION}" \
  --query "LoadBalancerDescriptions[?DNSName=='${INGRESS_HOSTNAME}'].CanonicalHostedZoneNameID | [0]" \
  --output text)"

MODERN_ZONE_ID="$(aws elbv2 describe-load-balancers \
  --region "${AWS_REGION}" \
  --query "LoadBalancers[?DNSName=='${INGRESS_HOSTNAME}'].CanonicalHostedZoneId | [0]" \
  --output text)"

if [[ -n "${CLASSIC_ZONE_ID}" && "${CLASSIC_ZONE_ID}" != "None" ]]; then
  LOAD_BALANCER_ZONE_ID="${CLASSIC_ZONE_ID}"
elif [[ -n "${MODERN_ZONE_ID}" && "${MODERN_ZONE_ID}" != "None" ]]; then
  LOAD_BALANCER_ZONE_ID="${MODERN_ZONE_ID}"
else
  echo "ERROR: Could not determine the load balancer hosted-zone ID."
  exit 1
fi

CHANGE_FILE="$(mktemp)"

cat > "${CHANGE_FILE}" <<EOF
{
  "Comment": "Route ${RECORD_NAME} to the Kubernetes ingress controller",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${RECORD_NAME}",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "${LOAD_BALANCER_ZONE_ID}",
          "DNSName": "${INGRESS_HOSTNAME}.",
          "EvaluateTargetHealth": true
        }
      }
    }
  ]
}
EOF

echo "DNS record:          ${RECORD_NAME}"
echo "Ingress hostname:    ${INGRESS_HOSTNAME}"
echo "Load balancer zone:  ${LOAD_BALANCER_ZONE_ID}"
echo "Route 53 hosted zone:${HOSTED_ZONE_ID}"

read -r -p "Type CREATE to create or update this DNS record: " CONFIRMATION

if [[ "${CONFIRMATION}" != "CREATE" ]]; then
  echo "DNS change cancelled."
  rm -f "${CHANGE_FILE}"
  exit 0
fi

CHANGE_ID="$(aws route53 change-resource-record-sets \
  --hosted-zone-id "${HOSTED_ZONE_ID}" \
  --change-batch "$(cat "${CHANGE_FILE}")" \
  --query ChangeInfo.Id \
  --output text)"

rm -f "${CHANGE_FILE}"

echo "Waiting for Route 53 change:"
echo "${CHANGE_ID}"

aws route53 wait resource-record-sets-changed \
  --id "${CHANGE_ID}"

echo "DNS record is now INSYNC."