# SDK Release Runbook

## Scope

SDK release readiness covers `packages/sdk-spec` plus the generic TreeDX
language SDK packages:

- `packages/ts-sdk`
- `packages/python-sdk`
- `packages/rust-sdk`
- `packages/elixir-sdk`

SDK release readiness is part of root TreeDX service release readiness. The
single `TreeDX Release Gate` validates the service, native crates used by the
service, storage, security, OpenAPI service checks, containers, operational
profile gates, `packages/sdk-spec`, and all four generic language SDKs.

`packages/trsd-sdk` is a downstream TreeSeed consumer/reference. It is useful
for focused compatibility regression, but it is not an SDK architecture
authority.

## Required Checks

SDK-affecting release candidates should pass the integrated `TreeDX Release
Gate` SDK checks:

- `SDK Spec`
- `TypeScript SDK Test (amd64)`
- `TypeScript SDK Test (arm64)`
- `Python SDK Test (amd64)`
- `Python SDK Test (arm64)`
- `Rust SDK Test (amd64)`
- `Rust SDK Test (arm64)`
- `Elixir SDK Test (amd64)`
- `Elixir SDK Test (arm64)`

Also run the SDK documentation gate, the root OpenAPI gate, and focused
TreeSeed regression when TypeScript SDK changes affect package dependency
behavior.

On release-path pushes, the integrated workflow builds and uploads package
artifacts after the required service profile gates pass. On semantic version
tag pushes, the same jobs publish packages to npm, PyPI, crates.io, and Hex
through the GitHub `production` environment.

## Local Verification

Run the full local SDK gate from the repository root:

```bash
./scripts/test-sdk-packages.sh
```

Run the SDK documentation gate:

```bash
./scripts/check-sdk-docs.sh
```

Run the root OpenAPI gate:

```bash
./scripts/openapi-check.sh
```

When TypeScript SDK changes can affect the downstream TreeSeed package, run the
focused TreeSeed regression:

```bash
cd packages/ts-sdk
npm ci
npm run build

cd ../trsd-sdk
npm ci
npx vitest run --config ./vitest.config.ts \
  test/utils/sdk.test.ts \
  test/utils/graph.test.ts \
  test/utils/treedx-backends.test.ts
npm run build
```

`packages/trsd-sdk` is standalone and downstream-only. Do not add local file links from `packages/trsd-sdk` to sibling SDK packages during focused regression.

If `python3 -m pip` is unavailable locally, install Python packaging tooling
before running `scripts/test-sdk-packages.sh`. The lighter dependency-free
Python checks used during earlier bootstrap phases are not a complete Phase 14
SDK gate.

## GitHub Workflow Verification

Required SDK checks live in the `TreeDX Release Gate` workflow:

- `TreeDX Release Gate / SDK Spec`
- `TreeDX Release Gate / TypeScript SDK Test (amd64)`
- `TreeDX Release Gate / TypeScript SDK Test (arm64)`
- `TreeDX Release Gate / Python SDK Test (amd64)`
- `TreeDX Release Gate / Python SDK Test (arm64)`
- `TreeDX Release Gate / Rust SDK Test (amd64)`
- `TreeDX Release Gate / Rust SDK Test (arm64)`
- `TreeDX Release Gate / Elixir SDK Test (amd64)`
- `TreeDX Release Gate / Elixir SDK Test (arm64)`

Release-path package jobs:

- `TreeDX Release Gate / Publish TypeScript SDK`
- `TreeDX Release Gate / Publish Python SDK`
- `TreeDX Release Gate / Publish Rust SDK`
- `TreeDX Release Gate / Publish Elixir SDK`

The workflow is path-filtered for pull requests and branch pushes, while tag
pushes run release gates without custom tag-diff filtering.

Produced artifacts:

- TypeScript: npm tarball uploaded as `ts-sdk-npm-package`
- Python: wheel and source distribution uploaded as `python-sdk-dist`
- Rust: crate archive uploaded as `rust-sdk-crate`
- Elixir: Hex tarball uploaded as `elixir-sdk-hex-package`

Registry publishing runs only on git tag pushes whose semantic version tag
matches the package version. Branch pushes build and upload artifacts but do
not publish immutable package versions. The integrated release gate uses tags
without a `v` prefix, matching the Docker publishing policy.

## Release Version Bump

Git does not provide a native hook that runs before `git tag`, so use the
checked-in release helper instead of creating tags by hand:

```bash
scripts/release-tag.sh 0.1.2
git push origin HEAD
git push origin 0.1.2
```

The helper updates the service version and all public SDK package versions,
creates a release commit, and then creates the matching tag. It refuses to run
from a dirty worktree so unrelated edits do not land in the release commit.

To install a local shorthand:

```bash
git config alias.release-tag '!scripts/release-tag.sh'
```

Then run:

```bash
git release-tag 0.1.2
```

If a worktree already contains intentional release fixes, update only the
version files and commit everything together:

```bash
scripts/bump-release-version.ts 0.1.2
```

## Package Registry Setup

Create a GitHub environment named `production`. Add these environment secrets:

- `NPM_TOKEN`: npm automation token with publish access to the `@treeseed`
  scope. The TypeScript package publishes as `@treeseed/treedx` with public
  access.
- `PYPI_API_TOKEN`: PyPI API token. Use username `__token__`; the workflow
  supplies it automatically. For the first release, use an account token if a
  project-scoped token cannot exist yet, then replace it with a project-scoped
  token for `treedx`.
- `CARGO_REGISTRY_TOKEN`: crates.io API token with publish permission for the
  `treedx` crate.
- `HEX_API_KEY`: Hex.pm API key with publish permission for `treedx`.
- `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN`: Docker Hub credentials for
  publishing `treeseed/treedx` and `treeseed/treedx-profiler`.

Before the first tagged release, reserve or create the package identities where
the registry allows it:

- npm: ensure the `@treeseed` scope exists and the token can publish public scoped
  packages.
- PyPI: confirm `treedx` is available. The first publish may need an
  account-wide token; after that, use a project-scoped token.
- crates.io: confirm `treedx` is available and the token owner should be
  the long-term crate owner.
- Hex.pm: confirm `treedx` is available and the token owner should be the
  long-term package owner.

See `docs/runbooks/sdk-conformance.md` for shared scenario catalog rules and
current adapter behavior.

## Optional Live Integration

Optional external live integration reads:

- `TREEDX_SDK_BASE_URL`
- `TREEDX_SDK_TOKEN`

If a future optional live workflow is run manually, a `base_url` input should
override the base URL secret. If no base URL is configured, SDK integration
tests pass by reporting or skipping not-configured behavior.

Current conformance adapters validate scenario catalog loading and execute live dispatch when the local harness configures TreeDX. Optional integration tests still pass cleanly without external service config.

## Final Baseline Verification

For the implemented SDK baseline, final readiness means all four language SDKs validate as `implemented` manifests with full OpenAPI endpoint ownership and local-harness live conformance.

Run:

```bash
./scripts/check-sdk-docs.sh
./scripts/test-sdk-packages.sh
./scripts/openapi-check.sh
```

Python packaging tooling is required for the complete implemented SDK gate. If it is unavailable on a developer machine, record the local environment blocker and run dependency-free Python checks only as a diagnostic fallback:

```bash
cd packages/python-sdk
python3 scripts/check_treedx_generated_types.py
python3 -m compileall -q src tests
```

Record final SDK baseline results in
`docs/research/sdk-final-verification.md`.

## Release Candidate Readiness

A full release candidate is ready when:

- Root `TreeDX Release Gate` passes.
- Integrated SDK spec and language SDK test jobs pass.
- Package artifacts are uploaded for affected SDK packages.
- On semantic version tag pushes, SDK packages publish to npm, PyPI, crates.io,
  and Hex.
- Optional live integration is either not configured and cleanly reports not
  configured, or configured and passes.
- `scripts/test-sdk-packages.sh` passes locally or in release candidate
  automation.
- `scripts/check-sdk-docs.sh` passes.
- `./scripts/openapi-check.sh` passes.

## Troubleshooting

Python reports `No module named pip`: install `pip` or virtualenv tooling for
the local Python interpreter. CI uses `actions/setup-python` and upgrades pip.

TypeScript or TreeSeed reports missing `dist` from `@treeseed/treedx`: run
`npm run build` in `packages/ts-sdk` before focused `packages/trsd-sdk`
regression.

Rust commands run against the wrong crate: run Cargo commands inside
`packages/rust-sdk`.

Elixir dependencies are missing: run `mix deps.get` inside
`packages/elixir-sdk`.

Generated OpenAPI metadata is stale: run the package-specific generator, then
rerun the package-specific generated metadata check.

## Cleanup

Remove local dependency and build artifacts when verification is complete:

```bash
rm -rf packages/sdk-spec/node_modules
rm -rf packages/ts-sdk/node_modules packages/ts-sdk/dist
rm -rf packages/trsd-sdk/node_modules packages/trsd-sdk/dist
rm -rf packages/rust-sdk/target
rm -rf packages/elixir-sdk/_build packages/elixir-sdk/deps
rm -rf packages/python-sdk/.pytest_cache packages/python-sdk/build packages/python-sdk/dist packages/python-sdk/*.egg-info packages/python-sdk/src/*.egg-info
find packages/python-sdk -type d -name __pycache__ -prune -exec rm -rf {} +
```
