#!/usr/bin/env bash
set -euo pipefail

TREEDX_BUILD_TMP_DIR="${TREEDX_BUILD_TMP_DIR:-${TMPDIR:-/tmp}}"
TREEDX_TARGET_DIR="${TREEDX_TARGET_DIR:-${TREEDX_BUILD_TMP_DIR%/}/treedx-target}"

./scripts/verification/check-file-lengths.sh
rg -q 'TREESEED_TREEDX_AUTH_VERIFIER:-jwks_oidc' compose.yaml
rg -q 'TREESEED_TREEDX_JWKS_URL:-http://host.docker.internal:3002/.well-known/treedx-jwks.json' compose.yaml

CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$TREEDX_TARGET_DIR}" cargo fmt --all -- --check
CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$TREEDX_TARGET_DIR}" cargo clippy --workspace -- -D warnings
CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$TREEDX_TARGET_DIR}" cargo test --workspace
CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$TREEDX_TARGET_DIR}" cargo build -p treedx_git --bin treedx_git_worker

(
  cd apps/api
  CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$TREEDX_TARGET_DIR}" \
  RUSTLER_TARGET_DIR="${RUSTLER_TARGET_DIR:-$TREEDX_TARGET_DIR}" \
  mix deps.get

  CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$TREEDX_TARGET_DIR}" \
  RUSTLER_TARGET_DIR="${RUSTLER_TARGET_DIR:-$TREEDX_TARGET_DIR}" \
  mix format --check-formatted

  CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$TREEDX_TARGET_DIR}" \
  RUSTLER_TARGET_DIR="${RUSTLER_TARGET_DIR:-$TREEDX_TARGET_DIR}" \
  mix test
)
