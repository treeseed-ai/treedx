#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == -* || "$#" -eq 0 ]]; then
  umask 000

  args=(
    --base-url "${TREEDX_PROFILE_BASE_URL:-http://treedx-api:4000}"
    --auth-mode dev
    --load-mode "${TREEDX_PROFILE_LOAD_MODE:-portfolio}"
    --fixture "${TREEDX_PROFILE_FIXTURE:-small-docs}"
    --size "${TREEDX_PROFILE_SIZE:-small}"
    --scenario "${TREEDX_PROFILE_SCENARIO:-all}"
    --concurrency "${TREEDX_PROFILE_CONCURRENCY:-100}"
    --timeout-ms "${TREEDX_PROFILE_TIMEOUT_MS:-120000}"
    --fixture-root "${TREEDX_PROFILE_FIXTURE_ROOT:-/var/lib/treedx/profiler}"
    --repo-prefix "${TREEDX_PROFILE_REPO_PREFIX:-profile-}"
    --portfolio-repo-prefix "${TREEDX_PROFILE_REPO_PREFIX:-profile-}"
    --portfolio-initial-repos "${TREEDX_PROFILE_PORTFOLIO_INITIAL_REPOS:-1}"
    --portfolio-max-repos "${TREEDX_PROFILE_PORTFOLIO_MAX_REPOS:-1000}"
    --portfolio-growth-target "${TREEDX_PROFILE_PORTFOLIO_GROWTH_TARGET:-steady}"
    --portfolio-min-repo-age-before-delete "${TREEDX_PROFILE_PORTFOLIO_MIN_REPO_AGE_BEFORE_DELETE:-30m}"
    --report-format "${TREEDX_PROFILE_REPORT_FORMAT:-both}"
    --markdown-output "${TREEDX_PROFILE_MARKDOWN_OUTPUT:-target/profiles/compose-profile.md}"
    --include-admin "${TREEDX_PROFILE_INCLUDE_ADMIN:-true}"
    --include-destructive "${TREEDX_PROFILE_INCLUDE_DESTRUCTIVE:-true}"
    --include-exec "${TREEDX_PROFILE_INCLUDE_EXEC:-true}"
    --include-federation "${TREEDX_PROFILE_INCLUDE_FEDERATION:-true}"
    --federation-mode "${TREEDX_PROFILE_FEDERATION_MODE:-single_node}"
    --federation-exercise-promotion "${TREEDX_PROFILE_FEDERATION_EXERCISE_PROMOTION:-false}"
    --federation-exercise-write-proxy "${TREEDX_PROFILE_FEDERATION_EXERCISE_WRITE_PROXY:-false}"
    --federation-exercise-connected-denials "${TREEDX_PROFILE_FEDERATION_EXERCISE_CONNECTED_DENIALS:-true}"
    --reliability-verifier "${TREEDX_PROFILE_RELIABILITY_VERIFIER:-true}"
    --openapi-response-validation "${TREEDX_PROFILE_OPENAPI_RESPONSE_VALIDATION:-true}"
    --model-reconciliation "${TREEDX_PROFILE_MODEL_RECONCILIATION:-true}"
    --reconciliation-interval "${TREEDX_PROFILE_RECONCILIATION_INTERVAL:-30s}"
    --reconciliation-sample-size "${TREEDX_PROFILE_RECONCILIATION_SAMPLE_SIZE:-100}"
    --operation-chains "${TREEDX_PROFILE_OPERATION_CHAINS:-true}"
    --negative-tests "${TREEDX_PROFILE_NEGATIVE_TESTS:-true}"
    --metamorphic-checks "${TREEDX_PROFILE_METAMORPHIC_CHECKS:-true}"
    --delayed-consistency-checks "${TREEDX_PROFILE_DELAYED_CONSISTENCY_CHECKS:-true}"
    --delayed-check-intervals "${TREEDX_PROFILE_DELAYED_CHECK_INTERVALS:-5s,30s}"
    --restart-durability-check "${TREEDX_PROFILE_RESTART_DURABILITY_CHECK:-false}"
    --fault-injection "${TREEDX_PROFILE_FAULT_INJECTION:-false}"
    --permission-matrix "${TREEDX_PROFILE_PERMISSION_MATRIX:-true}"
    --replay-log "${TREEDX_PROFILE_REPLAY_LOG:-target/profiles/compose-profile-replay.jsonl}"
    --failure-replay-log "${TREEDX_PROFILE_FAILURE_REPLAY_LOG:-target/profiles/compose-profile-failures.jsonl}"
    --output "${TREEDX_PROFILE_OUTPUT:-target/profiles/compose-profile.yaml}"
    --profile-purpose "${TREEDX_PROFILE_PROFILE_PURPOSE:-reliability}"
    --include-probe-samples "${TREEDX_PROFILE_INCLUDE_PROBE_SAMPLES:-false}"
    --include-total-throughput "${TREEDX_PROFILE_INCLUDE_TOTAL_THROUGHPUT:-true}"
    --performance-workload "${TREEDX_PROFILE_PERFORMANCE_WORKLOAD:-balanced}"
    --heavy-operation-rate "${TREEDX_PROFILE_HEAVY_OPERATION_RATE:-0.05}"
    --repo-growth-rate "${TREEDX_PROFILE_REPO_GROWTH_RATE:-0.02}"
    --snapshot-rate "${TREEDX_PROFILE_SNAPSHOT_RATE:-0.02}"
    --graph-refresh-rate "${TREEDX_PROFILE_GRAPH_REFRESH_RATE:-0.03}"
    --import-rate "${TREEDX_PROFILE_IMPORT_RATE:-0.01}"
  )

  optional_arg() {
    local value="$1"
    local flag="$2"
    if [[ -n "$value" ]]; then
      args+=("$flag" "$value")
    fi
  }

  optional_arg "${TREEDX_PROFILE_FEDERATION_NODE_A_URL:-}" --federation-node-a-url
  optional_arg "${TREEDX_PROFILE_FEDERATION_NODE_B_URL:-}" --federation-node-b-url
  optional_arg "${TREEDX_PROFILE_FEDERATION_NODE_C_URL:-}" --federation-node-c-url
  optional_arg "${TREEDX_PROFILE_TARGET_PRIMARY_RPS:-}" --target-primary-rps
  optional_arg "${TREEDX_PROFILE_PROBE_SAMPLING_RATE:-}" --probe-sampling-rate
  optional_arg "${TREEDX_PROFILE_VALIDATION_PROBE_MODE:-}" --validation-probe-mode
  optional_arg "${TREEDX_PROFILE_FAIL_BELOW_PRIMARY_RPS:-}" --fail-below-primary-rps
  optional_arg "${TREEDX_PROFILE_RELIABILITY_BUDGET:-}" --reliability-budget
  optional_arg "${TREEDX_PROFILE_ITERATIONS:-}" --iterations

  duration="${TREEDX_PROFILE_DURATION-10m}"
  if [[ -n "$duration" ]]; then
    args+=(
      --duration "$duration"
      --duration-is-controlling "${TREEDX_PROFILE_DURATION_IS_CONTROLLING:-true}"
      --minimum-measured-duration "${TREEDX_PROFILE_MINIMUM_MEASURED_DURATION:-10m}"
    )
  fi

  set +e
  /usr/local/bin/treedx_profiler "${args[@]}" "$@"
  status="$?"
  set -e

  chown -R "${TREEDX_PROFILE_HOST_UID:-1000}:${TREEDX_PROFILE_HOST_GID:-1000}" \
    /workspace/treedx/target/profiles 2>/dev/null || true

  exit "$status"
fi

exec "$@"
