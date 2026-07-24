#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/release/release-tag.sh VERSION [--force-tag]

Creates a release commit and git tag after updating the service and SDK package
versions. VERSION must be a semantic version without a v prefix, for example:

  scripts/release/release-tag.sh 0.1.2

This script intentionally refuses to run from a dirty worktree so release
commits do not accidentally include unrelated changes. Use
scripts/release/bump-release-version.ts VERSION directly when you only want to update
the files.
USAGE
}

version="${1:-}"
force_tag=false

if [[ -z "$version" || "$version" == "-h" || "$version" == "--help" ]]; then
  usage
  exit 0
fi
shift || true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force-tag)
      force_tag=true
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

if [[ "$version" == v* ]]; then
  echo "Release versions must not include a v prefix." >&2
  exit 1
fi

if [[ "$version" == *+* ]]; then
  echo "Release versions must not include build metadata." >&2
  exit 1
fi

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?$ ]]; then
  echo "Unsupported release version: $version" >&2
  exit 1
fi

if [[ -n "$(git status --short)" ]]; then
  echo "Refusing to create a release tag from a dirty worktree." >&2
  echo "Commit or stash existing changes, or run scripts/release/bump-release-version.ts $version directly." >&2
  exit 1
fi

if git rev-parse -q --verify "refs/tags/$version" >/dev/null; then
  if [[ "$force_tag" == true ]]; then
    git tag -d "$version"
  else
    echo "Tag $version already exists. Pass --force-tag to replace the local tag." >&2
    exit 1
  fi
fi

scripts/release/bump-release-version.ts "$version"

git add \
  apps/api/lib/treedx/version.ex \
  apps/api/mix.exs \
  apps/api/test/treedx_web/runtime/health_controller_test.exs \
  packages/ts-sdk/package.json \
  packages/ts-sdk/package-lock.json \
  packages/ts-sdk/sdk-manifest.yaml \
  packages/python-sdk/pyproject.toml \
  packages/python-sdk/sdk-manifest.yaml \
  packages/rust-sdk/Cargo.toml \
  packages/rust-sdk/Cargo.lock \
  packages/rust-sdk/sdk-manifest.yaml \
  packages/elixir-sdk/mix.exs \
  packages/elixir-sdk/sdk-manifest.yaml

git commit -m "build(release): bump version to $version"
git tag "$version"

echo "Created release commit and tag $version."
echo "Push with:"
echo "  git push origin HEAD"
echo "  git push origin $version"
