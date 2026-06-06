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

CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/tmp/treedx-target}" cargo audit

mkdir -p target
syft dir:. -o spdx-json=target/treedx-sbom.spdx.json

docker build -t treedx-security-scan:local -f Dockerfile --target prod .
syft treedx-security-scan:local -o spdx-json=target/treedx-image-sbom.spdx.json
trivy image --exit-code 1 --ignore-unfixed --severity HIGH,CRITICAL treedx-security-scan:local

docker build -t treedx-profiler-security-scan:local -f Dockerfile.profiler --target profiler .
syft treedx-profiler-security-scan:local -o spdx-json=target/treedx-profiler-image-sbom.spdx.json
trivy image --exit-code 0 --ignore-unfixed --severity HIGH,CRITICAL treedx-profiler-security-scan:local
