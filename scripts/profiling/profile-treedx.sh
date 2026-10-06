#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

cd "$ROOT_DIR"
cd tools/treedx_profiler
mix deps.get
mix escript.build
cd "$ROOT_DIR"
exec tools/treedx_profiler/treedx_profiler "$@"
