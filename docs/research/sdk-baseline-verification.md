# SDK Baseline Verification

## Summary

Baseline verification was run against `packages/ts-sdk` before TreeDX integration changes. The SDK is currently a standalone npm package named `@treeseed/sdk` at version `0.10.22`.

## Initial Command Results

| Command | Result | Notes |
| --- | --- | --- |
| `npm ci` | pass | Created dependencies; reported 18 audit vulnerabilities, including 13 moderate and 5 high. |
| `npm run build` | pass | Build completed through `npm run build:dist`. |
| `npm run typecheck --if-present` | pass/no-op | No `typecheck` script exists in `packages/ts-sdk/package.json`. |
| `npm test` | fail | Missing fixture submodule plus package graph self-reference assertion. |

## Initial Failure Details

The first `npm test` run failed because `.fixtures/treeseed-fixtures` was not initialized. The SDK expects the fixture submodule at commit `33bac888a055d6e8b649b5ba0a1eb3c2bbd80b71`.

The missing fixture caused these suites to fail during import:

- `test/utils/operations.test.ts`
- `test/utils/remote.test.ts`
- `test/utils/sdk.test.ts`

`test/utils/package-graph.test.ts` also failed because it found deprecated SDK path text inside the test file itself:

```text
@treeseed/sdk/platform/tenant/config
```

Observed Vitest summary: fixture setup and one package-graph assertion failed.

## Historical Documentation Rerun

After writing the initial docs, the requested documentation-safe verification commands were rerun.

| Command | Result | Notes |
| --- | --- | --- |
| `git status --short` | pass | Root worktree shows only new `docs/` files. |
| `git -C packages/ts-sdk status --short` | pass | SDK checkout is clean. |
| `npm run build` | pass | Build completed through `npm run build:dist`. |
| `npm test` | historical issue | Only the package graph assertion tripped on this historical rerun; this has been corrected. |

Final rerun summary: one package-graph assertion still failed and the remaining
configured tests completed.

The final failing assertion was unchanged:

```text
test/utils/package-graph.test.ts contains deprecated sdk path @treeseed/sdk/platform/tenant/config
```

At the time of the final rerun, the fixture submodule was present at the expected commit:

```text
33bac888a055d6e8b649b5ba0a1eb3c2bbd80b71 .fixtures/treeseed-fixtures (0.5.0-2-g33bac88)
```

## Cleanup Update

The package graph self-reference was corrected by excluding the actual
`packages/ts-sdk/test/utils/package-graph.test.ts` path from its
deprecated-alias scan. The focused test passed:

```text
npx vitest run --config ./vitest.config.ts test/utils/package-graph.test.ts
Test Files  1 passed (1)
Tests       9 passed (9)
```

The full SDK suite was also rerun after targeted tests. It completed with only
that same package graph assertion before the cleanup.

## Current Verification Update

The current SDK action-compatible verify run passes with no skipped-test count:

```text
Test Files  90 passed (90)
Tests       561 passed (561)
```

TreeDX OpenAPI type generation and contract checks are included in the SDK
verification path.

## Suggested Next Verification

For SDK-facing TreeDX changes, run:

```bash
cd packages/ts-sdk
npm run build
npx vitest run --config ./vitest.config.ts test/utils/package-graph.test.ts test/utils/treedx-e2e-contract.test.ts
npm test
```
