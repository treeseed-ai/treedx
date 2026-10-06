#!/usr/bin/env bash
set -euo pipefail

required=(
  TREEDX_LIVE_NODE_A_URL
  TREEDX_LIVE_NODE_A_TOKEN
  TREEDX_LIVE_NODE_A_REPO_ID
  TREEDX_LIVE_NODE_B_URL
  TREEDX_LIVE_NODE_B_TOKEN
  TREEDX_LIVE_NODE_B_REPO_ID
)

for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "Federation live check not configured: ${name} is not set."
    exit 0
  fi
done

curl -fsS \
  -H "authorization: Bearer ${TREEDX_LIVE_NODE_A_TOKEN}" \
  -H "content-type: application/json" \
  -d "{\"repoIds\":[\"${TREEDX_LIVE_NODE_A_REPO_ID}\",\"${TREEDX_LIVE_NODE_B_REPO_ID}\"],\"query\":\"release\",\"includeErrors\":true,\"limit\":5}" \
  "${TREEDX_LIVE_NODE_A_URL%/}/api/v1/search" >/dev/null

echo "Federation live check passed."
