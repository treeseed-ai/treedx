#!/usr/bin/env bash
set -euo pipefail

CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/tmp/treedb-target}" cargo test --workspace

(
  cd apps/api
  CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/tmp/treedb-target}" \
  RUSTLER_TARGET_DIR="${RUSTLER_TARGET_DIR:-/tmp/treedb-target}" \
  mix test \
    test/treedb_web/blob_controller_test.exs \
    test/treedb_web/push_controller_test.exs \
    test/treedb_web/exec_sandbox_test.exs \
    test/treedb_web/admin_storage_controller_test.exs \
    test/treedb_web/workspace_revocation_test.exs \
    test/treedb_web/capability_matrix_test.exs \
    test/treedb_web/leakage_regression_test.exs
)

(
  cd packages/ts-sdk
  npx vitest run --config ./vitest.config.ts \
    test/utils/treedb-client.test.ts \
    test/utils/treedb-blobs.test.ts \
    test/utils/treedb-git-remotes.test.ts \
    test/utils/treedb-auth-policy-audit.test.ts \
    test/utils/treedb-e2e-contract.test.ts
)
