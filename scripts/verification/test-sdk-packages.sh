#!/usr/bin/env bash
set -euo pipefail

section() {
  printf '\n==> %s\n' "$1"
}

cleanup_generated_outputs() {
  git clean -fd packages/python-sdk/dist packages/rust-sdk/target >/dev/null
}

trap cleanup_generated_outputs EXIT

tsx_bin() {
  local candidate="../sdk-spec/node_modules/.bin/tsx"
  if [[ -x "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi
  if command -v tsx >/dev/null 2>&1; then
    command -v tsx
    return 0
  fi
  echo "Unable to find tsx. Run the SDK Spec stage first or install tsx on PATH." >&2
  return 1
}

python_pip_args() {
  if python3 -m pip install --help 2>/dev/null | grep -q -- "--break-system-packages"; then
    printf '%s\n' "--break-system-packages"
  fi
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
  mapfile -t pip_extra_args < <(python_pip_args)
  python3 -m pip install "${pip_extra_args[@]}" -e ".[dev]"
  python3 scripts/check_treedx_generated_types.py
  python3 -m build
  python3 -m pytest
)

section "Rust SDK"
(
  cd packages/rust-sdk
  "$(tsx_bin)" scripts/check_treedx_generated_types.ts
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
