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

Environment overrides:
  Any TREEDB_PROFILE_* variable may be set before invoking this script.

Examples:
  scripts/profile-compose.sh portfolio
  TREEDB_PROFILE_CONCURRENCY=200 scripts/profile-compose.sh read-heavy
  TREEDB_PROFILE_DURATION=2h scripts/profile-compose.sh soak
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
  smoke|fixed|portfolio|read-heavy|write-heavy|graph|binary|admin|soak)
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

export TREEDB_PROFILE_OUTPUT="${TREEDB_PROFILE_OUTPUT:-$default_yaml}"
export TREEDB_PROFILE_MARKDOWN_OUTPUT="${TREEDB_PROFILE_MARKDOWN_OUTPUT:-$default_md}"
export TREEDB_PROFILE_REPORT_FORMAT="${TREEDB_PROFILE_REPORT_FORMAT:-both}"
export TREEDB_PROFILE_REPO_PREFIX="${TREEDB_PROFILE_REPO_PREFIX:-profile-${mode}-}"
export TREEDB_PROFILE_HOST_UID="${TREEDB_PROFILE_HOST_UID:-$(id -u)}"
export TREEDB_PROFILE_HOST_GID="${TREEDB_PROFILE_HOST_GID:-$(id -g)}"

compose_files=(-f profiles/compose.profile.yaml)

if [[ "$dev_api" == true ]]; then
  compose_files+=(-f profiles/compose.profile.dev-api.yaml)
fi

compose_files+=(-f "profiles/compose.profile.${mode}.yaml")

cd "$ROOT_DIR"

if [[ "$config_only" == true ]]; then
  docker compose "${compose_files[@]}" config
  exit 0
fi

if [[ "$clean" == true ]]; then
  docker compose "${compose_files[@]}" down -v --remove-orphans
fi

echo "Running TreeDB profile mode: $mode"
if [[ "$dev_api" == true ]]; then
  echo "API image: development"
else
  echo "API image: production release"
fi
echo "YAML report: $TREEDB_PROFILE_OUTPUT"
echo "Markdown report: $TREEDB_PROFILE_MARKDOWN_OUTPUT"

# shellcheck disable=SC2086
docker compose "${compose_files[@]}" up $build_flag --abort-on-container-exit --exit-code-from treedb-profiler
