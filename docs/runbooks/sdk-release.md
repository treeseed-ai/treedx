# SDK Release Runbook

## Scope

SDK release readiness covers `packages/sdk-spec` plus the generic TreeDB
language SDK packages:

- `packages/ts-sdk`
- `packages/python-sdk`
- `packages/rust-sdk`
- `packages/elixir-sdk`

SDK release readiness does not replace root TreeDB service release readiness.
The root `TreeDB Release Gate` remains responsible for the service, native
crates used by the service, storage, security, OpenAPI service checks,
containers, and operational smoke checks.

`packages/trsd-sdk` is a downstream TreeSeed consumer/reference. It is useful
for focused compatibility regression, but it is not an SDK architecture
authority.

## Required Checks

SDK-affecting release candidates should pass the package-level release gate for
the affected package:

- `SDK Spec Release Gate`
- `TypeScript SDK Release Gate`
- `Python SDK Release Gate`
- `Rust SDK Release Gate`
- `Elixir SDK Release Gate`

Also run the SDK documentation gate, the root OpenAPI gate, and focused
TreeSeed regression when TypeScript SDK changes affect package dependency
behavior.

Package release gates build and upload package artifacts. They do not publish
to npm, PyPI, crates.io, or Hex in this pass.

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
  test/utils/treedb-backends.test.ts
npm run build
```

`packages/trsd-sdk` is standalone and downstream-only. Do not add local file links from `packages/trsd-sdk` to sibling SDK packages during focused regression.

If `python3 -m pip` is unavailable locally, install Python packaging tooling
before running `scripts/test-sdk-packages.sh`. The lighter dependency-free
Python checks used during earlier bootstrap phases are not a complete Phase 14
SDK gate.

## GitHub Workflow Verification

Required SDK workflow checks for SDK-affecting changes:

- `SDK Spec Release Gate / SDK Spec Release Gate`
- `TypeScript SDK Release Gate / TypeScript SDK Release Gate`
- `Python SDK Release Gate / Python SDK Release Gate`
- `Rust SDK Release Gate / Rust SDK Release Gate`
- `Elixir SDK Release Gate / Elixir SDK Release Gate`

Package release gates use the same branch/tag strategy as the root service gate:
pull requests and branch pushes are path-filtered, while tag pushes run release
gates without custom tag-diff filtering.

Produced artifacts:

- TypeScript: npm tarball uploaded as `ts-sdk-npm-package`
- Python: wheel and source distribution uploaded as `python-sdk-dist`
- Rust: crate archive uploaded as `rust-sdk-crate`
- Elixir: Hex tarball uploaded as `elixir-sdk-hex-package`

Publishing remains manual or future work.

See `docs/runbooks/sdk-conformance.md` for shared scenario catalog rules and
current adapter behavior.

## Optional Live Integration

Optional external live integration reads:

- `TREEDB_SDK_BASE_URL`
- `TREEDB_SDK_TOKEN`

If a future optional live workflow is run manually, a `base_url` input should
override the base URL secret. If no base URL is configured, SDK integration
tests pass by reporting or skipping not-configured behavior.

Current conformance adapters validate scenario catalog loading and execute live dispatch when the local harness configures TreeDB. Optional integration tests still pass cleanly without external service config.

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
python3 scripts/check_treedb_generated_types.py
python3 -m compileall -q src tests
```

Record final SDK baseline results in
`docs/research/sdk-final-verification.md`.

## Release Candidate Readiness

A full release candidate is ready when:

- Root `TreeDB Release Gate` passes.
- Relevant package-level SDK release gates pass.
- Package artifacts are uploaded for affected SDK packages.
- Optional live integration is either not configured and cleanly reports not
  configured, or configured and passes.
- `scripts/test-sdk-packages.sh` passes locally or in release candidate
  automation.
- `scripts/check-sdk-docs.sh` passes.
- `./scripts/openapi-check.sh` passes.

## Troubleshooting

Python reports `No module named pip`: install `pip` or virtualenv tooling for
the local Python interpreter. CI uses `actions/setup-python` and upgrades pip.

TypeScript or TreeSeed reports missing `dist` from `@treedb/ts-sdk`: run
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
