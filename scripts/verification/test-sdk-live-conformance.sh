#!/usr/bin/env bash
set -euo pipefail

binding_file="$(mktemp)"
cleanup() {
  set -a
  source "$binding_file"
  set +a
  (cd packages/ts-sdk && node --import tsx scripts/native-conformance.ts stop)
  rm -f "$binding_file"
}
trap cleanup EXIT

(cd apps/api && MIX_ENV=dev mix deps.get && MIX_ENV=dev mix compile)
(cd packages/ts-sdk && npm ci && GITHUB_ENV="$binding_file" node --import tsx scripts/native-conformance.ts start)
set -a
source "$binding_file"
set +a

(cd packages/ts-sdk && npm run test:treedx-conformance)
(cd packages/python-sdk && python3 -m pip install -e ".[dev]" && python3 -m pytest tests/conformance)
(cd packages/rust-sdk && cargo test conformance)
(cd packages/elixir-sdk && mix deps.get && mix test test/conformance)
