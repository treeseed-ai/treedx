# Environment Research

This document is historical background from the first repository audit. The
current operational source of truth is the root `README.md`, `Dockerfile`,
`compose.yaml`, `compose.prod.yaml`, `Cargo.toml`, `apps/api`, `crates`, and the
runbooks under `docs/runbooks`.

## Repository Layout

The current repository includes the Phoenix API service, Rust crates, Docker
runtime, Compose manifests, OpenAPI contract, runbooks, and the SDK package.
`packages/treedx` remains separately verifiable and also participates in the
root release gate.

## Tooling

Detected local host tools during the original audit:

| Tool | Version |
| --- | --- |
| Node | `v24.15.0` |
| npm | `11.12.1` |
| Git | `2.43.0` |
| Rust | `rustc 1.95.0 (59807616e 2026-04-14)` |
| Cargo | `cargo 1.95.0 (f2d3ce0bd 2026-03-21)` |
| Erlang/OTP | `27` |
| Elixir | `1.17.3` |

These host versions were audit context only. Docker remains the canonical way
to run the service for contributors who do not already have the full toolchain.

## Package Manager And Scripts

The root TreeDX repository uses Cargo, Mix, Docker, and shell verification
scripts. The SDK package uses npm and remains independently verifiable.

`packages/treedx` uses npm, evidenced by `packages/treedx/package-lock.json`. Its package metadata is:

| Field | Value |
| --- | --- |
| Package name | `@treeseed/sdk` |
| Version | `0.10.22` |
| Module type | `module` |
| Node engine | `>=22` |
| Test framework | Vitest |
| Build target | `npm run build` -> `npm run build:dist` |
| Typecheck script | none |

SDK scripts recorded for compatibility:

| Script | Command |
| --- | --- |
| `setup` | `npm install` |
| `setup:ci` | `npm ci` |
| `build` | `npm run build:dist` |
| `build:dist` | `tsx ./scripts/build-dist.ts` |
| `test` | `npm run test:unit` |
| `test:unit` | `vitest run --config ./vitest.config.ts` |
| `test:unit:fast` | `vitest run --config ./vitest.fast.config.ts` |
| `lint` | `npm run fixtures:check && npm run build:dist` |
| `verify` | `tsx ./scripts/verify-driver.ts` |
| `release:verify` | `tsx ./scripts/release-verify.ts` |

## Runtime Assumptions

The canonical runtime path is `docker compose up treedx-api`, with the
container owning language runtime and native dependency complexity. Host-local
commands are supported for maintainers with Rust, Elixir/OTP, Node, Git, Docker,
and scanner tools installed.

## Current Environment Risks

1. `packages/treedx` can be checked out and verified independently, so contract
   generation must continue to support package-local OpenAPI files.
2. Strict release scanning requires external tools (`cargo-audit`, `syft`,
   `trivy`, and Docker) that may not be installed on every developer machine.
3. Live TreeDX and federation checks are optional environment-backed checks and
   must report `not configured` rather than appearing as skipped tests.
