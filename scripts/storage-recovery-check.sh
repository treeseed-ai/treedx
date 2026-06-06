#!/usr/bin/env bash
set -euo pipefail

CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/tmp/treedx-target}" cargo test -p treedx_store --test recovery_tests
CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/tmp/treedx-target}" cargo test -p treedx_store --test backup_tests
CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/tmp/treedx-target}" cargo test -p treedx_store --test restore_tests
CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/tmp/treedx-target}" cargo test -p treedx_store --test storage_migration_tests
CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/tmp/treedx-target}" cargo test -p treedx_store --test security_storage_tests

(
  cd apps/api
  CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/tmp/treedx-target}" \
  RUSTLER_TARGET_DIR="${RUSTLER_TARGET_DIR:-/tmp/treedx-target}" \
  mix test \
    test/treedx_web/admin_storage_controller_test.exs \
    test/treedx_web/admin_storage_compaction_backup_test.exs \
    test/treedx_web/admin_storage_migration_restore_test.exs
)
