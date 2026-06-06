# TreeDX SDK Conformance

This directory contains the shared black-box conformance scenario catalog for
TreeDX SDKs. TypeScript, Python, Rust, and Elixir SDKs must run these scenarios
through their public SDK facades once language package conformance adapters
exist.

## Layout

- `scenarios/`: domain-grouped scenario metadata and behavioral assertions.
- `fixtures/repos/`: repository fixtures for future executable scenarios.
- `fixtures/requests/`: request fixtures for future executable scenarios.
- `fixtures/expected/`: expected response fixtures for future executable scenarios.

## Scenario Format

Each scenario file has `version`, `status`, and a `scenarios` array. Each
scenario defines:

- `id`: unique lowercase dotted scenario id.
- `capabilityId`: capability from `../spec/capabilities.yaml`.
- `kind`: `black_box`.
- `required`: whether every TreeDX language SDK must support the behavior.
- `serverRequired`: `true`, `false`, or `conditional`.
- `endpointRefs`: OpenAPI endpoint strings owned by the capability.
- `fixtures`: `repos`, `requests`, and `expected` arrays.
- `steps`: public SDK facade actions to exercise.
- `assertions`: behavior each SDK must satisfy.

## Capability Ownership

Every scenario id must be listed in the owning capability's
`conformanceScenarios`. Every capability scenario id must be defined exactly
once in this catalog. `npm run validate` enforces scenario uniqueness,
capability ownership, endpoint references, fixture hygiene, and required
steps/assertions.

## Fixture Rules

Fixture references must stay inside:

- `conformance/fixtures/repos`
- `conformance/fixtures/requests`
- `conformance/fixtures/expected`

Absolute paths and `..` segments are forbidden. Empty fixture arrays are valid
while the catalog remains metadata/assertion oriented.

## SDK Adapters

Future language SDK conformance adapters should load this catalog and execute
scenario steps through the SDK public facade. Generated OpenAPI clients and
private adapters are not the direct conformance surface.

`packages/trsd-sdk` compatibility tests are downstream TreeSeed migration
safety tests. They do not define TreeDX SDK conformance.
