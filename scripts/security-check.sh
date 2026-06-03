#!/usr/bin/env bash
set -euo pipefail

require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required security tool missing: $1" >&2
    exit 127
  }
}

require_tool cargo
require_tool cargo-audit
require_tool syft
require_tool trivy
require_tool docker

CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/tmp/treedb-target}" cargo audit

mkdir -p target
syft dir:. -o spdx-json=target/treedb-sbom.spdx.json

docker build -t treedb-security-scan:local -f Dockerfile .
trivy image --exit-code 1 --severity HIGH,CRITICAL treedb-security-scan:local
