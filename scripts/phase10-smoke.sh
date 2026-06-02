#!/usr/bin/env bash
set -euo pipefail

TREEDB_URL="${TREEDB_URL:-http://localhost:4000}"
TREEDB_KEEP_RUNNING="${TREEDB_KEEP_RUNNING:-0}"
TOKEN=""

cleanup() {
  local status=$?
  if [[ $status -ne 0 ]]; then
    docker compose logs --tail=120 treedb-api || true
  fi
  if [[ "$TREEDB_KEEP_RUNNING" != "1" ]]; then
    docker compose down || true
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

docker compose down -v --remove-orphans >/dev/null 2>&1 || true
docker compose up -d treedb-api

for _ in $(seq 1 120); do
  if curl -fsS "$TREEDB_URL/api/v1/health" >/dev/null; then
    break
  fi
  sleep 3
done

curl -fsS "$TREEDB_URL/api/v1/health" >/dev/null

TOKEN="$(
  curl -fsS -X POST "$TREEDB_URL/api/v1/auth/dev-token" \
    -H 'content-type: application/json' \
    -d '{}' | json_get '.accessToken'
)"

AUTH=(-H "authorization: Bearer $TOKEN" -H 'content-type: application/json')
REPO_PATH="/var/lib/treedb/repos/bare/phase10-smoke"

docker compose exec -T treedb-api bash -lc "
set -euo pipefail
rm -rf '$REPO_PATH'
mkdir -p '$REPO_PATH/docs' '$REPO_PATH/plain'
cd '$REPO_PATH'
git init -b main
git config user.name 'TreeDB Smoke'
git config user.email 'smoke@example.invalid'
cat > docs/readme.md <<'DOC'
---
title: Smoke
status: published
---
# Smoke

phase ten provenance smoke fixture
DOC
echo 'phase ten provenance plain fixture' > plain/search.txt
git add .
git commit -m 'Initial smoke fixture'
"

repo_json="$(
  curl -fsS -X POST "$TREEDB_URL/api/v1/repos/register" \
    "${AUTH[@]}" \
    -d "{\"name\":\"phase10-smoke\",\"localPath\":\"$REPO_PATH\"}"
)"
repo_id="$(json_get '.repo.repoId' <<<"$repo_json")"

workspace_json="$(
  curl -fsS -X POST "$TREEDB_URL/api/v1/repos/$repo_id/workspaces" \
    "${AUTH[@]}" \
    -d '{"baseRef":"refs/heads/main","branchName":"refs/heads/agent/phase10-smoke","mode":"writable","allowedPaths":["docs/**","plain/**"]}'
)"
workspace_id="$(json_get '.workspaceId' <<<"$workspace_json")"

curl -fsS -X POST "$TREEDB_URL/api/v1/repos/$repo_id/files/search" \
  "${AUTH[@]}" \
  -d '{"paths":["docs/**","plain/**"],"query":"phase ten provenance"}' >/dev/null

curl -fsS -X PUT "$TREEDB_URL/api/v1/workspaces/$workspace_id/files?path=docs/readme.md" \
  "${AUTH[@]}" \
  -d '{"content":"---\ntitle: Smoke Updated\nstatus: published\n---\n# Smoke Updated\n\nphase ten committed smoke update\n"}' >/dev/null

commit_json="$(
  curl -fsS -X POST "$TREEDB_URL/api/v1/workspaces/$workspace_id/commit" \
    "${AUTH[@]}" \
    -d '{"message":"Phase 10 smoke update","author":{"name":"TreeDB Smoke","email":"smoke@example.invalid"}}'
)"
commit_sha="$(json_get '.commitSha' <<<"$commit_json")"
branch_name="$(json_get '.branchName' <<<"$commit_json")"

graph_json="$(
  curl -fsS -X POST "$TREEDB_URL/api/v1/repos/$repo_id/graph/refresh" \
    "${AUTH[@]}" \
    -d "{\"ref\":\"$branch_name\",\"paths\":[\"docs/**\",\"plain/**\"]}"
)"
graph_version="$(json_get '.graphVersion' <<<"$graph_json")"

snapshot_json="$(
  curl -fsS -X POST "$TREEDB_URL/api/v1/repos/$repo_id/snapshots/build" \
    "${AUTH[@]}" \
    -d "{\"ref\":\"$branch_name\",\"kind\":\"repository_snapshot\",\"paths\":[\"docs/**\"],\"includeGraph\":true}"
)"
snapshot_id="$(json_get '.snapshot.snapshotId' <<<"$snapshot_json")"

artifact_json="$(
  curl -fsS -X POST "$TREEDB_URL/api/v1/repos/$repo_id/artifacts/export" \
    "${AUTH[@]}" \
    -d "{\"snapshotId\":\"$snapshot_id\"}"
)"
artifact_checksum="$(json_get '.artifact.checksum' <<<"$artifact_json")"

curl -fsS "$TREEDB_URL/api/v1/audit/events?repoId=$repo_id&limit=50" "${AUTH[@]}" >/dev/null

cat <<SUMMARY
Phase 10 smoke passed
repo_id=$repo_id
workspace_id=$workspace_id
commit_sha=$commit_sha
graph_version=$graph_version
snapshot_id=$snapshot_id
artifact_checksum=$artifact_checksum
SUMMARY
