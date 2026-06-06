#!/usr/bin/env bash
set -euo pipefail

TREEDX_URL="${TREEDX_URL:-http://localhost:4000}"
TREEDX_KEEP_RUNNING="${TREEDX_KEEP_RUNNING:-0}"
TREEDX_SMOKE_COMPOSE_FILE="${TREEDX_SMOKE_COMPOSE_FILE:-profiles/compose.profile.yaml}"
TOKEN=""
FIXTURE_DIR=""

compose() {
  docker compose -f "$TREEDX_SMOKE_COMPOSE_FILE" "$@"
}

cleanup() {
  local status=$?
  if [[ $status -ne 0 ]]; then
    compose logs --tail=120 treedx-api || true
  fi
  if [[ "$TREEDX_KEEP_RUNNING" != "1" ]]; then
    compose down || true
  fi
  if [[ -n "$FIXTURE_DIR" ]]; then
    rm -rf "$FIXTURE_DIR"
  fi
  exit "$status"
}
trap cleanup EXIT

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

need curl
need docker
need git

json_get() {
  local expr="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -r "$expr"
  else
    command -v node >/dev/null 2>&1 || {
      echo "missing required command: jq or node" >&2
      exit 1
    }
    node -e "
const fs = require('fs');
const input = JSON.parse(fs.readFileSync(0, 'utf8'));
const path = process.argv[1].replace(/^\\./, '').split('.').filter(Boolean);
let value = input;
for (const key of path) value = value == null ? undefined : value[key];
if (value == null) process.exit(1);
if (typeof value === 'object') console.log(JSON.stringify(value));
else console.log(String(value));
" "$expr"
  fi
}

compose down -v --remove-orphans >/dev/null 2>&1 || true
compose up -d --build treedx-api

for _ in $(seq 1 120); do
  if curl -fsS "$TREEDX_URL/api/v1/health" >/dev/null; then
    break
  fi
  sleep 3
done

curl -fsS "$TREEDX_URL/api/v1/health" >/dev/null

TOKEN="$(
  curl -fsS -X POST "$TREEDX_URL/api/v1/auth/dev-token" \
    -H 'content-type: application/json' \
    -d '{}' | json_get '.accessToken'
)"

AUTH=(-H "authorization: Bearer $TOKEN" -H 'content-type: application/json')
REPO_PATH="/var/lib/treedx/imports/mvp-smoke"

FIXTURE_DIR="$(mktemp -d)"
fixture_repo="$FIXTURE_DIR/imports/mvp-smoke"
mkdir -p "$fixture_repo/docs" "$fixture_repo/plain"
(
set -euo pipefail
cd "$fixture_repo"
git init -b main
git config user.name 'TreeDX Smoke'
git config user.email 'smoke@example.invalid'
cat > docs/readme.md <<'DOC'
---
title: Smoke
status: published
---
# Smoke

mvp provenance smoke fixture
DOC
echo 'mvp provenance plain fixture' > plain/search.txt
git add .
git commit -m 'Initial smoke fixture'
)
compose cp "$FIXTURE_DIR/imports" "treedx-api:/var/lib/treedx/imports"

repo_json="$(
  curl -fsS -X POST "$TREEDX_URL/api/v1/admin/repos/import-local" \
    "${AUTH[@]}" \
    -d '{"repositoryName":"mvp-smoke","sourceRelativePath":"imports/mvp-smoke"}'
)"
repo_id="$(json_get '.repo.repoId' <<<"$repo_json")"

workspace_json="$(
  curl -fsS -X POST "$TREEDX_URL/api/v1/repos/$repo_id/workspaces" \
    "${AUTH[@]}" \
    -d '{"baseRef":"refs/heads/main","branchName":"refs/heads/agent/mvp-smoke","mode":"writable","allowedPaths":["docs/**","plain/**"]}'
)"
workspace_id="$(json_get '.workspaceId' <<<"$workspace_json")"

curl -fsS -X POST "$TREEDX_URL/api/v1/repos/$repo_id/files/search" \
  "${AUTH[@]}" \
  -d '{"paths":["docs/**","plain/**"],"query":"mvp provenance"}' >/dev/null

curl -fsS -X PUT "$TREEDX_URL/api/v1/workspaces/$workspace_id/files?path=docs/readme.md" \
  "${AUTH[@]}" \
  -d '{"content":"---\ntitle: Smoke Updated\nstatus: published\n---\n# Smoke Updated\n\nmvp committed smoke update\n"}' >/dev/null

commit_json="$(
  curl -fsS -X POST "$TREEDX_URL/api/v1/workspaces/$workspace_id/commit" \
    "${AUTH[@]}" \
    -d '{"message":"MVP smoke update","author":{"name":"TreeDX Smoke","email":"smoke@example.invalid"}}'
)"
commit_sha="$(json_get '.commitSha' <<<"$commit_json")"
branch_name="$(json_get '.branchName' <<<"$commit_json")"

graph_json="$(
  curl -fsS -X POST "$TREEDX_URL/api/v1/repos/$repo_id/graph/refresh" \
    "${AUTH[@]}" \
    -d "{\"ref\":\"$branch_name\",\"paths\":[\"docs/**\",\"plain/**\"]}"
)"
graph_version="$(json_get '.graphVersion' <<<"$graph_json")"

snapshot_json="$(
  curl -fsS -X POST "$TREEDX_URL/api/v1/repos/$repo_id/snapshots/build" \
    "${AUTH[@]}" \
    -d "{\"ref\":\"$branch_name\",\"kind\":\"repository_snapshot\",\"paths\":[\"docs/**\"],\"includeGraph\":true}"
)"
snapshot_id="$(json_get '.snapshot.snapshotId' <<<"$snapshot_json")"

artifact_json="$(
  curl -fsS -X POST "$TREEDX_URL/api/v1/repos/$repo_id/artifacts/export" \
    "${AUTH[@]}" \
    -d "{\"snapshotId\":\"$snapshot_id\"}"
)"
artifact_checksum="$(json_get '.artifact.checksum' <<<"$artifact_json")"

curl -fsS "$TREEDX_URL/api/v1/audit/events?repoId=$repo_id&limit=50" "${AUTH[@]}" >/dev/null

cat <<SUMMARY
MVP smoke passed
repo_id=$repo_id
workspace_id=$workspace_id
commit_sha=$commit_sha
graph_version=$graph_version
snapshot_id=$snapshot_id
artifact_checksum=$artifact_checksum
SUMMARY
