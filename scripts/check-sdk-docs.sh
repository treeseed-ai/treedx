#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'sdk docs check failed: %s\n' "$1" >&2
  exit 1
}

require_file() {
  test -f "$1" || fail "missing required file $1"
}

search_q() {
  local pattern="$1"
  shift

  if command -v rg >/dev/null 2>&1; then
    rg -q "$pattern" "$@"
  else
    grep -ERq "$pattern" "$@"
  fi
}

require_text() {
  local file="$1"
  local pattern="$2"
  search_q "$pattern" "$file" || fail "missing '$pattern' in $file"
}

for file in \
  packages/sdk-spec/README.md \
  packages/sdk-spec/spec/treedx-sdk-standard.md \
  packages/ts-sdk/README.md \
  packages/python-sdk/README.md \
  packages/rust-sdk/README.md \
  packages/elixir-sdk/README.md \
  docs/architecture/sdk-integration.md \
  docs/runbooks/sdk-conformance.md \
  docs/runbooks/sdk-release.md \
  docs/runbooks/sdk-remote-mode.md \
  docs/api/compatibility-notes.md
do
  require_file "$file"
done

stale_repo_env="TREESEED_TREEDX_""REPO_ID"
stale_missing_repo="missing_""repo_id"
stale_set_repo="set repo""Id"
stale_opt_in="treeDx"'\.'"enabled"
stale_pattern="${stale_repo_env}|${stale_missing_repo}|${stale_set_repo}|${stale_opt_in}"

if search_q "$stale_pattern" \
  packages/sdk-spec \
  packages/ts-sdk/README.md \
  packages/python-sdk/README.md \
  packages/rust-sdk/README.md \
  packages/elixir-sdk/README.md \
  docs/architecture/sdk-integration.md \
  docs/runbooks/sdk-conformance.md \
  docs/runbooks/sdk-release.md \
  docs/runbooks/sdk-remote-mode.md \
  docs/api/compatibility-notes.md; then
  fail "stale TreeDX repository-id or opt-in wording found"
fi

if search_q "Repository ID" docs/runbooks/sdk-remote-mode.md; then
  fail "stale Repository ID wording found in sdk-remote-mode runbook"
fi

for readme in \
  packages/ts-sdk/README.md \
  packages/python-sdk/README.md \
  packages/rust-sdk/README.md \
  packages/elixir-sdk/README.md
do
  for topic in \
    "Install" \
    "Configure" \
    "Health" \
    "Repository Query" \
    "Workspace" \
    "Blob" \
    "Graph" \
    "Context" \
    "Federation" \
    "Pagination" \
    "Conformance" \
    "Integration"
  do
    require_text "$readme" "$topic"
  done

  if ! search_q "Authenticate|Auth" "$readme"; then
    fail "missing auth topic in $readme"
  fi

  if ! search_q "TreeDxApiError|TreeDxSdk\\.Error" "$readme"; then
    fail "missing language error type in $readme"
  fi
done

for file in \
  packages/sdk-spec/README.md \
  docs/runbooks/sdk-release.md \
  docs/runbooks/sdk-conformance.md
do
  require_text "$file" "./scripts/check-sdk-docs.sh"
done

require_text packages/sdk-spec/README.md "./scripts/test-sdk-packages.sh"
require_text packages/ts-sdk/README.md "npm run treedx:check-generated"
require_text packages/python-sdk/README.md "python scripts/check_treedx_generated_types.py"
require_text packages/rust-sdk/README.md "node scripts/check_treedx_generated_types.mjs"
require_text packages/elixir-sdk/README.md "mix run scripts/check_treedx_generated_types.exs"
require_text docs/architecture/treedx-sdk-spec-implementation-plan.md "implemented"
for term in Admin Audit Policy SearchIndex FederationInternal "Live conformance" implemented; do
  require_text docs/architecture/treedx-sdk-spec-implementation-plan.md "$term"
done

printf 'sdk docs check passed\n'
