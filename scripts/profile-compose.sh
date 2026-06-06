#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'USAGE'
Usage:
  scripts/profile-compose.sh MODE [--dev-api] [--no-clean] [--no-build] [--config]

Modes:
  smoke        fast correctness profile
  fixed        deterministic fixed-fixture baseline
  portfolio    10-minute growing portfolio profile
  read-heavy   read/search/query-focused workload
  write-heavy  workspace/blob/snapshot-focused workload
  graph        graph/context/search-index-focused workload
  binary       blob/multipart/artifact-focused workload
  admin        admin/storage diagnostics workload
  soak         long growing portfolio soak profile
  mirror-federation      three-node mirror cluster profile
  connected-library      three-node connected-library profile
  federation-soak        long three-node federation soak profile
  performance            100 primary RPS target single-node benchmark
  federation-performance three-node federation performance benchmark

Environment overrides:
  Any TREEDX_PROFILE_* variable may be set before invoking this script.

Examples:
  scripts/profile-compose.sh portfolio
  TREEDX_PROFILE_CONCURRENCY=200 scripts/profile-compose.sh read-heavy
  TREEDX_PROFILE_DURATION=2h scripts/profile-compose.sh soak
  scripts/profile-compose.sh portfolio --dev-api
USAGE
}

mode="${1:-}"
if [[ -z "$mode" || "$mode" == "-h" || "$mode" == "--help" ]]; then
  usage
  exit 0
fi
shift || true

clean=true
build_flag="--build"
config_only=false
dev_api=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-clean)
      clean=false
      ;;
    --no-build)
      build_flag=""
      ;;
    --config)
      config_only=true
      ;;
    --dev-api)
      dev_api=true
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

case "$mode" in
  smoke|fixed|portfolio|read-heavy|write-heavy|graph|binary|admin|soak|performance|mirror-federation|connected-library|federation-soak|federation-performance)
    ;;
  *)
    echo "Unknown profile mode: $mode" >&2
    usage >&2
    exit 1
    ;;
esac

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
default_yaml="target/profiles/${mode}-${timestamp}.yaml"
default_md="target/profiles/${mode}-${timestamp}.md"
default_replay="target/profiles/${mode}-${timestamp}-replay.jsonl"
default_failures="target/profiles/${mode}-${timestamp}-failures.jsonl"

export TREEDX_PROFILE_OUTPUT="${TREEDX_PROFILE_OUTPUT:-$default_yaml}"
export TREEDX_PROFILE_MARKDOWN_OUTPUT="${TREEDX_PROFILE_MARKDOWN_OUTPUT:-$default_md}"
export TREEDX_PROFILE_REPLAY_LOG="${TREEDX_PROFILE_REPLAY_LOG:-$default_replay}"
export TREEDX_PROFILE_FAILURE_REPLAY_LOG="${TREEDX_PROFILE_FAILURE_REPLAY_LOG:-$default_failures}"
export TREEDX_PROFILE_REPORT_FORMAT="${TREEDX_PROFILE_REPORT_FORMAT:-both}"
export TREEDX_PROFILE_REPO_PREFIX="${TREEDX_PROFILE_REPO_PREFIX:-profile-${mode}-}"
export TREEDX_PROFILE_HOST_UID="${TREEDX_PROFILE_HOST_UID:-$(id -u)}"
export TREEDX_PROFILE_HOST_GID="${TREEDX_PROFILE_HOST_GID:-$(id -g)}"

case "$mode" in
  mirror-federation|connected-library|federation-soak|federation-performance)
    compose_files=(-f profiles/compose.profile.federation.yaml)
    ;;
  *)
    compose_files=(-f profiles/compose.profile.yaml)
    ;;
esac

if [[ "$dev_api" == true && "$mode" == "mirror-federation" || "$dev_api" == true && "$mode" == "connected-library" || "$dev_api" == true && "$mode" == "federation-soak" || "$dev_api" == true && "$mode" == "federation-performance" ]]; then
  echo "--dev-api is only supported for single-node profile modes" >&2
  exit 1
fi

if [[ "$dev_api" == true ]]; then
  compose_files+=(-f profiles/compose.profile.dev-api.yaml)
fi

compose_files+=(-f "profiles/compose.profile.${mode}.yaml")

cd "$ROOT_DIR"
mkdir -p target/profiles
chmod 0777 target/profiles

if [[ "$config_only" == true ]]; then
  docker compose "${compose_files[@]}" config
  exit 0
fi

if [[ "$clean" == true ]]; then
  docker compose "${compose_files[@]}" down -v --remove-orphans
fi

echo "Running TreeDX profile mode: $mode"
if [[ "$dev_api" == true ]]; then
  echo "API image: development"
else
  echo "API image: production release"
fi
echo "YAML report: $TREEDX_PROFILE_OUTPUT"
echo "Markdown report: $TREEDX_PROFILE_MARKDOWN_OUTPUT"

# shellcheck disable=SC2086
docker compose "${compose_files[@]}" up $build_flag --abort-on-container-exit --exit-code-from treedx-profiler
