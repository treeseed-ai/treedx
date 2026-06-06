#!/usr/bin/env bash
set -euo pipefail

TREEDX_URL="${TREEDX_URL:-http://localhost:4000}"
OUTPUT="${OUTPUT:-target/profiles/smoke.yaml}"
FIXTURE_ROOT="${TREEDX_PROFILER_FIXTURE_ROOT:-/var/lib/treedx/profiler}"

./scripts/profile-treedx.sh \
  --base-url "$TREEDX_URL" \
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
