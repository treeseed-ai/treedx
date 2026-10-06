#!/usr/bin/env bash
set -euo pipefail

require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required security tool missing: $1" >&2
    exit 127
  }
}

retry() {
  local attempt
  for attempt in 1 2 3 4 5; do
    if "$@"; then
      return 0
    fi
    if [[ "$attempt" == "5" ]]; then
      return 1
    fi
    sleep $((attempt * 5))
  done
}

ensure_cargo_audit() {
  if command -v cargo-audit >/dev/null 2>&1; then
    return 0
  fi
  echo "Installing cargo-audit for TreeDX security scan..." >&2
  retry cargo install cargo-audit --locked
}

ensure_scanner_tool() {
  local name="$1"
  local url="$2"
  if command -v "$name" >/dev/null 2>&1; then
    return 0
  fi
  local tools_dir="${TREEDX_TOOLS_DIR:-"$PWD/.treedx-tools/bin"}"
  mkdir -p "$tools_dir"
  echo "Installing $name for TreeDX security scan..." >&2
  retry bash -c "curl --http1.1 -sSfL '$url' | sh -s -- -b '$tools_dir'"
  export PATH="$tools_dir:$PATH"
}

require_tool cargo
ensure_cargo_audit
ensure_scanner_tool syft https://raw.githubusercontent.com/anchore/syft/main/install.sh
ensure_scanner_tool trivy https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh
require_tool docker

check_hex_security_advisories() {
  local app_dir="$1"
  local log_path
  log_path="$(mktemp)"
  (
    cd "$app_dir"
    mix deps.get 2>&1 | tee "$log_path"
    status="${PIPESTATUS[0]}"
    if [[ "$status" -ne 0 ]]; then
      exit "$status"
    fi
  )
  if grep -E 'VULNERABLE!|Found packages with security advisories' "$log_path" >/dev/null; then
    echo "Hex security advisories found in ${app_dir}; update or replace vulnerable dependencies before release." >&2
    cat "$log_path" >&2
    rm -f "$log_path"
    exit 1
  fi
  rm -f "$log_path"
}

CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/tmp/treedx-target}" cargo audit
check_hex_security_advisories apps/api
check_hex_security_advisories tools/treedx_profiler

mkdir -p target
syft dir:. -o spdx-json=target/treedx-sbom.spdx.json

docker build -t treedx-security-scan:local -f Dockerfile --target prod .
syft treedx-security-scan:local -o spdx-json=target/treedx-image-sbom.spdx.json
trivy image --exit-code 1 --ignore-unfixed --severity HIGH,CRITICAL treedx-security-scan:local

docker build -t treedx-profiler-security-scan:local -f Dockerfile.profiler --target profiler .
syft treedx-profiler-security-scan:local -o spdx-json=target/treedx-profiler-image-sbom.spdx.json
trivy image --exit-code 1 --ignore-unfixed --severity HIGH,CRITICAL treedx-profiler-security-scan:local
