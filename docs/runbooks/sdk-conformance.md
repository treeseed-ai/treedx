# SDK Conformance Runbook

## Scope

TreeDX SDK conformance is a shared black-box scenario catalog. Language adapters load scenario metadata and, when `TREEDX_BASE_URL` is configured by the local harness, dispatch scenarios through public SDK methods. Without a configured server they still report clean `not_configured` behavior for optional local checks.

Conformance always runs through public SDK facades. Generated clients and
private adapters are not the direct conformance surface.

## Scenario Catalog

Scenario files live in:

```text
packages/sdk-spec/conformance/scenarios
```

Each scenario has:

- unique lowercase dotted `id`;
- `capabilityId` from `packages/sdk-spec/spec/capabilities.yaml`;
- `kind: black_box`;
- `endpointRefs` owned by the capability;
- fixture arrays for `repos`, `requests`, and `expected`;
- public-facade steps;
- behavioral assertions.

Every `capabilities.yaml.conformanceScenarios[]` entry must be defined exactly
once. `npm run validate` in `packages/sdk-spec` enforces scenario uniqueness,
capability ownership, endpoint ownership, fixture hygiene, and non-empty
steps/assertions.

## Language Adapter Commands

TypeScript:

```bash
cd packages/ts-sdk
npm run test:treedx-conformance
```

Python:

```bash
cd packages/python-sdk
python -m pytest tests/conformance
```

Rust currently runs conformance tests through the full test target:

```bash
cd packages/rust-sdk
cargo test
```

Elixir:

```bash
cd packages/elixir-sdk
mix test test/conformance
```

Run the documentation gate after conformance documentation changes:

```bash
./scripts/check-sdk-docs.sh
```

## Adding A Scenario

1. Add a scenario record under `packages/sdk-spec/conformance/scenarios`.
2. Add the scenario id to the owning capability in
   `packages/sdk-spec/spec/capabilities.yaml`.
3. Keep `endpointRefs` limited to endpoints owned by that capability.
4. Keep fixture references under `conformance/fixtures/repos`,
   `conformance/fixtures/requests`, or `conformance/fixtures/expected`.
5. Run:

```bash
cd packages/sdk-spec
npm run validate
```

## Not Configured Behavior

Conformance adapters must return or report `not_configured` when no live TreeDX server is configured. When the local harness provides live configuration, required scenarios must dispatch through public SDK module methods and must not fake success.

## Local Live Conformance Harness

Live conformance uses the local TreeDX harness script:

```bash
./scripts/test-sdk-live-conformance.sh
```

The harness owns temporary repositories, credentials, storage paths, and destructive admin safety flags. It defines:

- TreeDX server lifecycle or connection requirements;
- credential and fixture setup;
- request/response fixture payloads;
- per-language dispatch from scenario actions to public SDK facade calls;
- failure reporting that preserves `TreeDxApiError`-compatible fields.

## Implemented Baseline

The implemented SDK baseline means scenario catalog loading plus live dispatch under the local harness. Optional integration tests may still report `not_configured` when no server is configured.
