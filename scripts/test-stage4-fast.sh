#!/usr/bin/env bash
set -euo pipefail

CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/tmp/treedb-target}" cargo test --workspace

(
  cd apps/api
  CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/tmp/treedb-target}" \
  RUSTLER_TARGET_DIR="${RUSTLER_TARGET_DIR:-/tmp/treedb-target}" \
  mix test \
    test/treedb_web/federated_execution_test.exs \
    test/treedb_web/federated_leakage_test.exs \
    test/treedb_web/federated_remote_routing_test.exs \
    test/treedb_web/federated_graph_test.exs \
    test/treedb_web/leakage_regression_test.exs \
    test/treedb_web/capability_matrix_test.exs
)

(
  cd packages/ts-sdk
  npx vitest run --config ./vitest.config.ts \
    test/utils/treedb-federated-execution.test.ts \
    test/utils/treedb-federation-plan.test.ts \
    test/utils/treedb-registry-routing.test.ts \
    test/utils/treedb-e2e-contract.test.ts
)
