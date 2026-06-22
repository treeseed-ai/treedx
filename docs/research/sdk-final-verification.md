# SDK Final Verification

## Summary

Phase 16 final verification records the generic TreeDX SDK baseline across
`packages/sdk-spec`, TypeScript, Python, Rust, and Elixir SDK packages.

The baseline is complete as a cross-language partial SDK foundation. It is not a
live-conformance-complete release. All SDK manifests intentionally report
`partial` while executable live conformance dispatch remains deferred.

## Local Environment

- Repository root: `/home/adrian/Projects/treedx`
- OpenAPI source: `docs/api/openapi.yaml`
- Canonical SDK plan:
  `docs/architecture/treedx-spec-implementation-plan.md`
- Python packaging tooling: local `python3 -m pip` is unavailable in this
  environment, so Python install/build/pytest checks are environment-blocked
  locally.

## Commands Run

Documentation gate:

```bash
./scripts/check-sdk-docs.sh
```

SDK package gate:

```bash
./scripts/test-sdk-packages.sh
```

Python dependency-free fallback:

```bash
cd packages/python-sdk
python3 scripts/check_treedx_generated_types.py
python3 -m compileall -q src tests
```

Individual non-Python full checks when the SDK package gate is blocked by local
Python packaging tooling:

```bash
cd packages/sdk-spec
npm ci
npm run validate
npm run check-openapi-coverage
npm run check-sdk-manifests
npm run render-capability-matrix
npm test

cd packages/treedx
npm ci
npm run treedx:check-generated
npm run build
npm test

cd packages/rust-sdk
tsx scripts/check_treedx_generated_types.ts
cargo fmt --all -- --check
cargo clippy --all-targets -- -D warnings
cargo test

cd packages/elixir-sdk
mix deps.get
mix run scripts/check_treedx_generated_types.exs
mix format --check-formatted
mix test
```

Focused downstream TreeSeed regression:

```bash
cd packages/treedx
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

Root OpenAPI gate:

```bash
./scripts/openapi-check.sh
```

Repository-id guard:

```bash
forbidden="TREESEED_TREEDX_""REPO_ID"
rg "$forbidden" . -S || true
```

## Results

- SDK documentation gate passed.
- `sdk-spec` validation passed.
- SDK manifest validation passed for four manifests.
- Capability matrix showed TypeScript, Python, Rust, and Elixir as `partial`.
- TypeScript generated metadata check, build, and tests passed.
- Python generated metadata and source/test compile checks passed.
- Rust generated metadata check, format check, clippy, and tests passed.
- Elixir generated metadata check, format check, and tests passed.
- Focused TreeSeed downstream regression passed.
- Root OpenAPI gate passed with `4 tests, 0 failures`.
- The forbidden TreeSeed TreeDX repository-id environment variable was absent.

OpenAPI coverage remained:

```text
Declared SDK endpoint count: 66
OpenAPI operation count: 113
Advisory uncovered OpenAPI operation count: 47
```

## Known Local Tooling Blockers

Local Python package install/build/pytest checks are blocked because
`python3 -m pip` is unavailable:

```text
/usr/bin/python3: No module named pip
```

This is a local environment blocker, not a Python SDK implementation failure.
CI uses Python setup tooling and should run the package install/build/pytest
path.

## Final Baseline State

Generic SDK packages exist:

- `packages/treedx`
- `packages/python-sdk`
- `packages/rust-sdk`
- `packages/elixir-sdk`

`packages/sdk-spec` is the shared architecture, capability, endpoint, test
framework, and conformance source.

`packages/trsd-sdk` is downstream only, remains standalone, and does not define generic TreeDX SDK architecture.

All SDK manifests now report `implemented` for required modules, required test roots, and required capabilities. OpenAPI ownership covers all 113 `/api/v1` operations.

Current conformance adapters load shared scenario records and report
not-configured behavior. They do not fake live conformance success.

## Cleanup

After verification, local dependency and build artifacts should be removed while
preserving lockfiles, manifests, generated source metadata, and workflow files:

```bash
rm -rf packages/sdk-spec/node_modules
rm -rf packages/treedx/node_modules packages/treedx/dist
rm -rf packages/trsd-sdk/node_modules packages/trsd-sdk/dist
rm -rf packages/rust-sdk/target
rm -rf packages/elixir-sdk/_build packages/elixir-sdk/deps
rm -rf packages/python-sdk/.pytest_cache packages/python-sdk/build packages/python-sdk/dist packages/python-sdk/*.egg-info packages/python-sdk/src/*.egg-info
find packages/python-sdk -type d -name __pycache__ -prune -exec rm -rf {} +
```
