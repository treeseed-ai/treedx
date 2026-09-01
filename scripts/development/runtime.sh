#!/usr/bin/env bash
set -euo pipefail

session_id="${TREESEED_DEVELOPMENT_SESSION_ID:?TREESEED_DEVELOPMENT_SESSION_ID is required}"
project="treeseed-treedx-${session_id//[^a-zA-Z0-9_-]/-}"
worktree="${TREESEED_DEVELOPMENT_WORKTREE:?TREESEED_DEVELOPMENT_WORKTREE is required}"
# TreeDX workspaces are durable development data, not disposable process state.
# Keep one managed development store across renewed sessions; otherwise an expired
# session can strand governed drafts even though PostgreSQL still references them.
state_root="${TREESEED_TREEDX_DEVELOPMENT_STATE_DIR:-${worktree}/.treeseed/development-state}"
data_root="${state_root}/data"
export TREESEED_TREEDX_HOST_DATA_DIR="$data_root"
export TREESEED_API_INTERNAL_URL="${TREESEED_API_INTERNAL_URL:-${TREESEED_API_URL:-http://api-live:3000}}"
export TREESEED_TREEDX_JWT_ISSUER="${TREESEED_TREEDX_JWT_ISSUER:-${TREEDX_JWT_ISSUER:-https://api.treeseed.localhost/treedx}}"
export TREESEED_TREEDX_JWT_AUDIENCE="${TREESEED_TREEDX_JWT_AUDIENCE:-${TREEDX_JWT_AUDIENCE:-treedx}}"
export TREESEED_TREEDX_JWKS_URL="${TREESEED_TREEDX_JWKS_URL:-${TREESEED_API_INTERNAL_URL}/.well-known/treedx-jwks.json}"
export TREESEED_TREEDX_CREDENTIAL_BROKER_ASSERTION="${TREESEED_TREEDX_CREDENTIAL_BROKER_ASSERTION:-${TREEDX_REMOTE_CREDENTIAL_BROKER_ASSERTION:-}}"

initialize_development_state() {
  mkdir -p "$state_root"
  if [[ -s "$data_root/workspaces/sessions.tdb" || -s "$data_root/catalog/repositories.tdb" ]]; then
    return
  fi
  local source="${TREESEED_TREEDX_CLONE_DATA_DIR:-}" candidate newest="" newest_mtime=0 candidate_mtime
  if [[ -z "$source" ]]; then
    for candidate in "$worktree"/.treeseed/cache/development-sessions/*/data; do
      [[ -d "$candidate" && "$candidate" != "$data_root" && -s "$candidate/catalog/repositories.tdb" ]] || continue
      candidate_mtime="$(stat --format '%Y' "$candidate/catalog/repositories.tdb")"
      if (( candidate_mtime > newest_mtime )); then newest="$candidate"; newest_mtime="$candidate_mtime"; fi
    done
    source="$newest"
  fi
  if [[ -z "$source" ]]; then
    candidate="$(cd "$worktree/../.." && pwd)/.treeseed/data/treedx/data"
    [[ -s "$candidate/catalog/repositories.tdb" ]] && source="$candidate"
  fi
  mkdir -p "$data_root"
  if [[ -n "$source" ]]; then
    printf 'Cloning durable TreeDX development state from %s\n' "$source"
    cp --archive --reflink=auto "$source/." "$data_root/"
  fi
}

case "${1:-}" in
  rebuild)
    initialize_development_state
    docker compose --project-name "$project" up --detach --build --force-recreate --wait treedx-api
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
