#!/usr/bin/env bash
set -euo pipefail

CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/tmp/treedx-target}" cargo fmt --all -- --check
CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/tmp/treedx-target}" cargo clippy --workspace -- -D warnings
CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/tmp/treedx-target}" cargo test --workspace

(
  cd apps/api
  CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/tmp/treedx-target}" \
  RUSTLER_TARGET_DIR="${RUSTLER_TARGET_DIR:-/tmp/treedx-target}" \
  mix deps.get

  CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/tmp/treedx-target}" \
  RUSTLER_TARGET_DIR="${RUSTLER_TARGET_DIR:-/tmp/treedx-target}" \
  mix format --check-formatted

  CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/tmp/treedx-target}" \
  RUSTLER_TARGET_DIR="${RUSTLER_TARGET_DIR:-/tmp/treedx-target}" \
  mix test
)
