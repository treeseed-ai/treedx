#!/usr/bin/env bash
set -euo pipefail

section() {
  printf '\n==> %s\n' "$1"
}

cleanup_generated_outputs() {
  git clean -fd packages/python-sdk/dist packages/rust-sdk/target >/dev/null
}

binding_file=""
cleanup() {
  local status=$?
  if [[ -n "$binding_file" ]]; then
    set -a
    source "$binding_file"
    set +a
    if ! (cd packages/ts-sdk && node --import tsx scripts/native-conformance.ts stop); then status=1; fi
    rm -f "$binding_file"
  fi
  cleanup_generated_outputs
  return "$status"
}
trap cleanup EXIT

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
)
# Own one disposable engine for all original language suites in this process.
# Caller-provided connected credentials are never changed in the parent process.
cargo build -p treedx_git --bin treedx_git_worker
(cd apps/api && MIX_ENV=dev mix deps.get && MIX_ENV=dev mix compile)
binding_file="$(mktemp)"
(cd packages/ts-sdk && GITHUB_ENV="$binding_file" node --import tsx scripts/native-conformance.ts start)
set -a
source "$binding_file"
set +a
(cd packages/ts-sdk && npm test)

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
