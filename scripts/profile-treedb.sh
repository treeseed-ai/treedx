#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"
cd tools/treedb_profiler
mix deps.get
mix escript.build
cd "$ROOT_DIR"
exec tools/treedb_profiler/treedb_profiler "$@"
