#!/usr/bin/env bash
set -euo pipefail

tmp="$(mktemp -d)"
server_pid=""

cleanup() {
  if [[ -n "${server_pid}" ]] && kill -0 "${server_pid}" 2>/dev/null; then
    kill "${server_pid}" 2>/dev/null || true
    wait "${server_pid}" 2>/dev/null || true
  fi
  rm -rf "${tmp}"
}
trap cleanup EXIT

port="$(python3 - <<'PY'
import socket
with socket.socket() as s:
    s.bind(("127.0.0.1", 0))
    print(s.getsockname()[1])
PY
)"

section() {
  printf '\n==> %s\n' "$1"
}

section "Start local TreeDB"
(
  cd apps/api
  MIX_ENV=dev \
  TREEDB_AUTH_MODE=dev \
  TREEDB_ENV=dev \
  TREEDB_DATA_DIR="${tmp}/data" \
  PORT="${port}" \
  PHX_SERVER=true \
  CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/tmp/treedb-target}" \
  RUSTLER_TARGET_DIR="${RUSTLER_TARGET_DIR:-/tmp/treedb-target}" \
  mix run --no-halt
) >"${tmp}/treedb.log" 2>&1 &
server_pid="$!"

base_url="http://127.0.0.1:${port}"
for _ in {1..120}; do
  if curl -fsS "${base_url}/api/v1/health" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! curl -fsS "${base_url}/api/v1/health" >/dev/null 2>&1; then
  cat "${tmp}/treedb.log" >&2 || true
  printf 'TreeDB did not become healthy at %s\n' "${base_url}" >&2
  exit 1
fi

token_payload="$(curl -fsS -X POST "${base_url}/api/v1/auth/dev-token" \
  -H 'content-type: application/json' \
  --data '{}')"
token="$(TOKEN_PAYLOAD="${token_payload}" python3 - <<'PY'
import os
import json, sys
payload = json.loads(os.environ["TOKEN_PAYLOAD"])
print(payload.get("token") or payload.get("accessToken") or payload.get("devToken") or "")
PY
)"

export TREEDB_BASE_URL="${base_url}"
export TREEDB_TOKEN="${token}"
export TREEDB_CONFORMANCE_REF="refs/heads/main"
export TREEDB_CONFORMANCE_ALLOW_ADMIN=1
export TREEDB_CONFORMANCE_ALLOW_INTERNAL=1
export TREEDB_CONFORMANCE_ALLOW_DESTRUCTIVE=1
export TREEDB_CONFORMANCE_TMP="${tmp}"

section "TypeScript conformance"
(cd packages/ts-sdk && npm ci && npm run test:treedb-conformance)

section "Python conformance"
(cd packages/python-sdk && python3 -m pip install -e ".[dev]" && python3 -m pytest tests/conformance)

section "Rust conformance"
(cd packages/rust-sdk && cargo test conformance)

section "Elixir conformance"
(cd packages/elixir-sdk && mix deps.get && mix test test/conformance)

section "SDK live conformance complete"
