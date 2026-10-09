#!/usr/bin/env bash
set -euo pipefail

(
  cd apps/api
  CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/tmp/treedx-target}" \
  RUSTLER_TARGET_DIR="${RUSTLER_TARGET_DIR:-/tmp/treedx-target}" \
  node ../../scripts/verification/reporting/command.ts exunit -- mix test \
    test/treedx_web/runtime/openapi_contract_test.exs \
    test/treedx_web/runtime/route_openapi_inventory_test.exs
)
