#![allow(clippy::duplicate_mod)]

#[path = "unit/auth.rs"]
mod unit_auth;
#[path = "unit/binary.rs"]
mod unit_binary;
#[path = "unit/client.rs"]
mod unit_client;
#[path = "unit/error.rs"]
mod unit_error;
#[path = "unit/pagination.rs"]
mod unit_pagination;
#[path = "unit/transport.rs"]
mod unit_transport;

#[path = "adapters/storage/artifacts.rs"]
mod adapters_artifacts;
#[path = "adapters/storage/blobs.rs"]
mod adapters_blobs;
#[path = "adapters/context.rs"]
mod adapters_context;
#[path = "adapters/exec.rs"]
mod adapters_exec;
#[path = "adapters/federation/federation.rs"]
mod adapters_federation;
#[path = "adapters/storage/files.rs"]
mod adapters_files;
#[path = "adapters/graph.rs"]
mod adapters_graph;
#[path = "adapters/storage/migrations.rs"]
mod adapters_migrations;
#[path = "adapters/federation/mirrors.rs"]
mod adapters_mirrors;
#[path = "adapters/observability.rs"]
mod adapters_observability;
#[path = "adapters/query.rs"]
mod adapters_query;
#[path = "adapters/federation/registry.rs"]
mod adapters_registry;
#[path = "adapters/federation/repositories.rs"]
mod adapters_repositories;
#[path = "adapters/storage/snapshots.rs"]
mod adapters_snapshots;
#[path = "adapters/federation/workspaces.rs"]
mod adapters_workspaces;

#[path = "generated/exports.rs"]
mod generated_exports;
#[path = "generated/openapi_freshness.rs"]
mod generated_openapi_freshness;
#[path = "generated/openapi_types.rs"]
mod generated_openapi_types;

#[path = "conformance/sdk_conformance.rs"]
mod conformance_sdk_conformance;
#[path = "integration/live_api.rs"]
mod integration_live_api;
