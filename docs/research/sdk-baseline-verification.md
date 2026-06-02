# SDK Baseline Verification

## Summary

Baseline verification was run against `packages/ts-sdk` before TreeDB integration changes. The SDK is currently a standalone npm package named `@treeseed/sdk` at version `0.10.22`.

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

Observed Vitest summary:

```text
Test Files  4 failed | 61 passed | 1 skipped (66)
Tests       1 failed | 441 passed | 7 skipped (449)
```

## Final Phase 0 Rerun

After writing the Phase 0 docs, the requested documentation-safe verification commands were rerun.

| Command | Result | Notes |
| --- | --- | --- |
| `git status --short` | pass | Root worktree shows only new `docs/` files. |
| `git -C packages/ts-sdk status --short` | pass | SDK checkout is clean. |
| `npm run build` | pass | Build completed through `npm run build:dist`. |
| `npm test` | fail | Only the package graph assertion failed on this rerun. |

Final rerun Vitest summary:

```text
Test Files  1 failed | 64 passed | 1 skipped (66)
Tests       1 failed | 479 passed | 7 skipped (487)
```

The final failing assertion was unchanged:

```text
test/utils/package-graph.test.ts contains deprecated sdk path @treeseed/sdk/platform/tenant/config
```

At the time of the final rerun, the fixture submodule was present at the expected commit:

```text
33bac888a055d6e8b649b5ba0a1eb3c2bbd80b71 .fixtures/treeseed-fixtures (0.5.0-2-g33bac88)
```

## Phase 9 Cleanup Update

The package graph self-reference was corrected during Phase 9 cleanup by excluding the actual `packages/ts-sdk/test/utils/package-graph.test.ts` path from its deprecated-alias scan. The focused test now passes:

```text
npx vitest run --config ./vitest.config.ts test/utils/package-graph.test.ts
Test Files  1 passed (1)
Tests       9 passed (9)
```

The full SDK suite was also rerun after Phase 9 targeted tests. It completed with only that same package graph assertion before the cleanup:

```text
Test Files  1 failed | 70 passed | 1 skipped (72)
Tests       1 failed | 499 passed | 7 skipped (507)
```

After the cleanup, use the package graph focused run above, targeted TreeDB SDK tests, and a fresh full-suite run as the current baseline.

## Baseline Debt

These failures are copied-state baseline debt and should not be fixed as part of Phase 0:

1. Preserve the fixture submodule state before using the full SDK test suite as a compatibility gate.
2. Add an explicit `typecheck` script if TypeScript checking should be part of the SDK baseline.

## Suggested Next Verification

After Phase 0, initialize the SDK fixture submodule and rerun the baseline:

```bash
git -C packages/ts-sdk submodule update --init --recursive
cd packages/ts-sdk
npm test
```

Do not use the current failing SDK test run as evidence of a TreeDB regression. It is the pre-integration baseline.
