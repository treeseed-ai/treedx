#!/usr/bin/env bash
set -euo pipefail

(
  cd apps/api
  CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/tmp/treedb-target}" \
  RUSTLER_TARGET_DIR="${RUSTLER_TARGET_DIR:-/tmp/treedb-target}" \
  mix test \
    test/treedb_web/openapi_contract_test.exs \
    test/treedb_web/route_openapi_inventory_test.exs
)
