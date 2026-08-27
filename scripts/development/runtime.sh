#!/usr/bin/env bash
set -euo pipefail

session_id="${TREESEED_DEVELOPMENT_SESSION_ID:?TREESEED_DEVELOPMENT_SESSION_ID is required}"
project="treeseed-treedx-${session_id//[^a-zA-Z0-9_-]/-}"
data_root="${TREESEED_DEVELOPMENT_WORKTREE:?TREESEED_DEVELOPMENT_WORKTREE is required}/.treeseed/cache/development-sessions/${session_id}/data"
export TREESEED_TREEDX_HOST_DATA_DIR="$data_root"

case "${1:-}" in
  rebuild)
    mkdir -p "$data_root"
    docker compose --project-name "$project" up --detach --build --wait treedx-api
    ;;
  stop)
    docker compose --project-name "$project" down --remove-orphans
    ;;
  verify)
    curl --fail --silent --show-error http://127.0.0.1:4000/api/v1/health >/dev/null
    ./scripts/verification/storage-recovery-check.sh
    CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/tmp/treedx-target}" cargo test -p treedx_git -p treedx_graph -p treedx_search
    ;;
  cleanup)
    docker compose --project-name "$project" down --remove-orphans
    ;;
  freeze)
    image="treeseed/treedx:development-candidate-${session_id}"
    docker build --target prod --tag "$image" .
    mkdir -p .treeseed/candidates
    docker image inspect --format '{{.Id}}' "$image" > .treeseed/candidates/treedx-image-digest.txt.new
    mv .treeseed/candidates/treedx-image-digest.txt.new .treeseed/candidates/treedx-image-digest.txt
    ;;
  *)
    printf 'usage: %s rebuild|stop|verify|cleanup|freeze\n' "$0" >&2
    exit 2
    ;;
esac
