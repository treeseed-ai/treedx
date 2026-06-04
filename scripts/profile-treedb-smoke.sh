#!/usr/bin/env bash
set -euo pipefail

TREEDB_URL="${TREEDB_URL:-http://localhost:4000}"
OUTPUT="${OUTPUT:-target/profiles/smoke.yaml}"
FIXTURE_ROOT="${TREEDB_PROFILER_FIXTURE_ROOT:-/var/lib/treedb/profiler}"

./scripts/profile-treedb.sh \
  --base-url "$TREEDB_URL" \
  --auth-mode dev \
  --fixture small-docs \
  --size small \
  --scenario full_api \
  --iterations 1 \
  --concurrency 1 \
  --fixture-root "$FIXTURE_ROOT" \
  --output "$OUTPUT"

test -s "$OUTPUT"
grep -q "totalErrors: 0" "$OUTPUT"
grep -q "unaccounted: 0" "$OUTPUT"
grep -q "failed: 0" "$OUTPUT"
