#!/usr/bin/env bash
set -euo pipefail

run_stage() {
  local name="$1"
  local timeout_seconds="$2"
  shift 2

  echo "::group::${name}"
  echo "[release-gate] starting ${name}"
  if command -v timeout >/dev/null 2>&1; then
    timeout --foreground "${timeout_seconds}" "$@"
  else
    "$@"
  fi
  echo "[release-gate] completed ${name}"
  echo "::endgroup::"
}

run_stage "TreeDX tests" "${TREEDX_TEST_ALL_TIMEOUT_SECONDS:-1200}" ./scripts/test-all.sh
run_stage "TreeDX security check" "${TREEDX_SECURITY_CHECK_TIMEOUT_SECONDS:-1200}" ./scripts/security-check.sh
run_stage "TreeDX MVP smoke" "${TREEDX_MVP_SMOKE_TIMEOUT_SECONDS:-900}" ./scripts/mvp-smoke.sh
run_stage "TreeDX federation live check" "${TREEDX_FEDERATION_LIVE_TIMEOUT_SECONDS:-120}" ./scripts/federation-live-check.sh
