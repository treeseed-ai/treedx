#!/usr/bin/env bash
set -euo pipefail

required=(
  TREEDB_LIVE_NODE_A_URL
  TREEDB_LIVE_NODE_A_TOKEN
  TREEDB_LIVE_NODE_A_REPO_ID
  TREEDB_LIVE_NODE_B_URL
  TREEDB_LIVE_NODE_B_TOKEN
  TREEDB_LIVE_NODE_B_REPO_ID
)

for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "Federation live check not configured: ${name} is not set."
    exit 0
  fi
done

curl -fsS \
  -H "authorization: Bearer ${TREEDB_LIVE_NODE_A_TOKEN}" \
  -H "content-type: application/json" \
  -d "{\"repoIds\":[\"${TREEDB_LIVE_NODE_A_REPO_ID}\",\"${TREEDB_LIVE_NODE_B_REPO_ID}\"],\"query\":\"release\",\"includeErrors\":true,\"limit\":5}" \
  "${TREEDB_LIVE_NODE_A_URL%/}/api/v1/search" >/dev/null

echo "Federation live check passed."
