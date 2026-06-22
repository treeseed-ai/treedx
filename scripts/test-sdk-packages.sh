#!/usr/bin/env bash
set -euo pipefail

section() {
  printf '\n==> %s\n' "$1"
}

section "SDK Spec"
(
  cd packages/sdk-spec
  npm ci
  npm run validate
  npm run check-openapi-coverage
  npm run check-sdk-manifests
  npm run render-capability-matrix
  npm test
)

section "TypeScript SDK"
(
  cd packages/ts-sdk
  npm ci
  npm run treedx:check-generated
  npm run build
  npm test
)

section "Python SDK"
(
  cd packages/python-sdk
  python3 -m pip install -e ".[dev]"
  python3 scripts/check_treedx_generated_types.py
  python3 -m build
  python3 -m pytest
)

section "Rust SDK"
(
  cd packages/rust-sdk
  tsx scripts/check_treedx_generated_types.ts
  cargo fmt --all -- --check
  cargo clippy --all-targets -- -D warnings
  cargo test
)

section "Elixir SDK"
(
  cd packages/elixir-sdk
  mix deps.get
  mix run scripts/check_treedx_generated_types.exs
  mix format --check-formatted
  mix test
)

section "SDK package verification complete"
