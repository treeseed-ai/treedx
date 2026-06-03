#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${TREEDB_LIVE_URL:-}" || -z "${TREEDB_LIVE_TOKEN:-}" || -z "${TREEDB_LIVE_REPO_ID:-}" ]]; then
  echo "TreeDB live SDK contract not configured: TREEDB_LIVE_URL, TREEDB_LIVE_TOKEN, and TREEDB_LIVE_REPO_ID are required."
  exit 0
fi

(
  cd packages/ts-sdk
  npx vitest run --config ./vitest.config.ts test/utils/treedb-live-contract.test.ts
)
