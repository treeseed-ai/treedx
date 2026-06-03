#!/usr/bin/env bash
set -euo pipefail

CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/tmp/treedb-target}" cargo fmt --all -- --check
CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/tmp/treedb-target}" cargo clippy --workspace -- -D warnings
CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/tmp/treedb-target}" cargo test --workspace

(
  cd apps/api
  CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/tmp/treedb-target}" \
  RUSTLER_TARGET_DIR="${RUSTLER_TARGET_DIR:-/tmp/treedb-target}" \
  mix format --check-formatted

  CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/tmp/treedb-target}" \
  RUSTLER_TARGET_DIR="${RUSTLER_TARGET_DIR:-/tmp/treedb-target}" \
  mix test
)

(
  cd packages/ts-sdk
  npm run build
  npm run treedb:check-types
  npm test
  npm run treedb:contract
  npx vitest run --config ./vitest.config.ts \
    test/utils/treedb-sdk-exports.test.ts \
    test/utils/treedb-client.test.ts \
    test/utils/treedb-adapters.test.ts \
    test/utils/treedb-e2e-contract.test.ts \
    test/utils/treedb-remote-mode.test.ts \
    test/utils/treedb-contract-drift.test.ts \
    test/utils/treedb-live-contract.test.ts
)

./scripts/federation-live-check.sh
