use crate::support::{err_json, ok_json, parse_json};
use base64::Engine;
use rustler::{Env, Term};
use std::path::Path;
use treedx_store::*;

#[rustler::nif(schedule = "DirtyIo")]
fn init_data_dir<'a>(env: Env<'a>, data_dir: String, opts_json: String) -> Term<'a> {
    match parse_json::<InitOptions>(opts_json) {
        Ok(opts) => match treedx_store::init_data_dir(Path::new(&data_dir), opts) {
            Ok(report) => ok_json(env, report),
            Err(error) => err_json(env, error.code(), error),
        },
        Err(error) => err_json(env, "invalid_json", format!("{error:?}")),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn seed_dev_records<'a>(
    env: Env<'a>,
    data_dir: String,
    node_id: String,
    base_url: String,
) -> Term<'a> {
    match treedx_store::seed_dev_records(Path::new(&data_dir), &node_id, &base_url) {
        Ok(report) => ok_json(env, report),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn seed_local_records<'a>(
    env: Env<'a>,
    data_dir: String,
    node_id: String,
    base_url: String,
) -> Term<'a> {
    match treedx_store::seed_local_records(Path::new(&data_dir), &node_id, &base_url) {
        Ok(report) => ok_json(env, report),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn put_repository<'a>(env: Env<'a>, data_dir: String, input_json: String) -> Term<'a> {
    match parse_json::<RepositoryInput>(input_json) {
        Ok(input) => match treedx_store::put_repository(Path::new(&data_dir), input) {
            Ok(record) => ok_json(env, record),
            Err(error) => err_json(env, error.code(), error),
        },
        Err(error) => err_json(env, "invalid_json", format!("{error:?}")),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn list_repositories<'a>(env: Env<'a>, data_dir: String) -> Term<'a> {
    match treedx_store::list_repositories(Path::new(&data_dir)) {
        Ok(records) => ok_json(env, records),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn get_repository<'a>(env: Env<'a>, data_dir: String, repo_id: String) -> Term<'a> {
    match treedx_store::get_repository(Path::new(&data_dir), &repo_id) {
        Ok(record) => ok_json(env, record),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn get_repository_placement<'a>(env: Env<'a>, data_dir: String, repo_id: String) -> Term<'a> {
    match treedx_store::get_repository_placement(Path::new(&data_dir), &repo_id) {
        Ok(record) => ok_json(env, record),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn put_repository_placement<'a>(env: Env<'a>, data_dir: String, input_json: String) -> Term<'a> {
    match parse_json::<RepositoryPlacementRecord>(input_json) {
        Ok(input) => match treedx_store::put_repository_placement(Path::new(&data_dir), input) {
            Ok(record) => ok_json(env, record),
            Err(error) => err_json(env, error.code(), error),
        },
        Err(error) => err_json(env, "invalid_json", format!("{error:?}")),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn list_nodes<'a>(env: Env<'a>, data_dir: String) -> Term<'a> {
    match treedx_store::list_nodes(Path::new(&data_dir)) {
        Ok(records) => ok_json(env, records),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn get_node<'a>(env: Env<'a>, data_dir: String, node_id: String) -> Term<'a> {
    match treedx_store::get_node(Path::new(&data_dir), &node_id) {
        Ok(record) => ok_json(env, record),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn list_mirrors<'a>(env: Env<'a>, data_dir: String, repo_id: String) -> Term<'a> {
    match treedx_store::list_mirrors(Path::new(&data_dir), &repo_id) {
        Ok(records) => ok_json(env, records),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn put_federation_peer<'a>(env: Env<'a>, data_dir: String, input_json: String) -> Term<'a> {
    match parse_json::<FederationPeerRecord>(input_json) {
        Ok(input) => match treedx_store::put_federation_peer(Path::new(&data_dir), input) {
            Ok(record) => ok_json(env, record),
            Err(error) => err_json(env, error.code(), error),
        },
        Err(error) => err_json(env, "invalid_json", format!("{error:?}")),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn list_federation_peers<'a>(env: Env<'a>, data_dir: String) -> Term<'a> {
    match treedx_store::list_federation_peers(Path::new(&data_dir)) {
        Ok(records) => ok_json(env, records),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn get_federation_peer<'a>(env: Env<'a>, data_dir: String, node_id: String) -> Term<'a> {
    match treedx_store::get_federation_peer(Path::new(&data_dir), &node_id) {
        Ok(record) => ok_json(env, record),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn put_repository_advertisement<'a>(
    env: Env<'a>,
    data_dir: String,
    input_json: String,
) -> Term<'a> {
    match parse_json::<RepositoryAdvertisementRecord>(input_json) {
        Ok(input) => {
            match treedx_store::put_repository_advertisement(Path::new(&data_dir), input) {
                Ok(record) => ok_json(env, record),
                Err(error) => err_json(env, error.code(), error),
            }
        }
        Err(error) => err_json(env, "invalid_json", format!("{error:?}")),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn list_repository_advertisements<'a>(env: Env<'a>, data_dir: String) -> Term<'a> {
    match treedx_store::list_repository_advertisements(Path::new(&data_dir)) {
        Ok(records) => ok_json(env, records),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn put_federation_route<'a>(env: Env<'a>, data_dir: String, input_json: String) -> Term<'a> {
    match parse_json::<FederationRouteRecord>(input_json) {
        Ok(input) => match treedx_store::put_federation_route(Path::new(&data_dir), input) {
            Ok(record) => ok_json(env, record),
            Err(error) => err_json(env, error.code(), error),
        },
        Err(error) => err_json(env, "invalid_json", format!("{error:?}")),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn list_federation_routes<'a>(env: Env<'a>, data_dir: String) -> Term<'a> {
    match treedx_store::list_federation_routes(Path::new(&data_dir)) {
        Ok(records) => ok_json(env, records),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn get_federation_route<'a>(env: Env<'a>, data_dir: String, repo_id: String) -> Term<'a> {
    match treedx_store::get_federation_route(Path::new(&data_dir), &repo_id) {
        Ok(record) => ok_json(env, record),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn put_node_capacity<'a>(env: Env<'a>, data_dir: String, input_json: String) -> Term<'a> {
    match parse_json::<NodeCapacityRecord>(input_json) {
        Ok(input) => match treedx_store::put_node_capacity(Path::new(&data_dir), input) {
            Ok(record) => ok_json(env, record),
            Err(error) => err_json(env, error.code(), error),
        },
        Err(error) => err_json(env, "invalid_json", format!("{error:?}")),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn list_node_capacity<'a>(env: Env<'a>, data_dir: String) -> Term<'a> {
    match treedx_store::list_node_capacity(Path::new(&data_dir)) {
        Ok(records) => ok_json(env, records),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn put_mirror_assignment<'a>(env: Env<'a>, data_dir: String, input_json: String) -> Term<'a> {
    match parse_json::<MirrorAssignmentRecord>(input_json) {
        Ok(input) => match treedx_store::put_mirror_assignment(Path::new(&data_dir), input) {
            Ok(record) => ok_json(env, record),
            Err(error) => err_json(env, error.code(), error),
        },
        Err(error) => err_json(env, "invalid_json", format!("{error:?}")),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn list_mirror_assignments<'a>(env: Env<'a>, data_dir: String, repo_id: String) -> Term<'a> {
    match treedx_store::list_mirror_assignments(Path::new(&data_dir), &repo_id) {
        Ok(records) => ok_json(env, records),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn put_workspace_route<'a>(env: Env<'a>, data_dir: String, input_json: String) -> Term<'a> {
    match parse_json::<WorkspaceRouteRecord>(input_json) {
        Ok(input) => match treedx_store::put_workspace_route(Path::new(&data_dir), input) {
            Ok(record) => ok_json(env, record),
            Err(error) => err_json(env, error.code(), error),
        },
        Err(error) => err_json(env, "invalid_json", format!("{error:?}")),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn get_workspace_route<'a>(env: Env<'a>, data_dir: String, workspace_id: String) -> Term<'a> {
    match treedx_store::get_workspace_route(Path::new(&data_dir), &workspace_id) {
        Ok(record) => ok_json(env, record),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn put_idempotency_record<'a>(env: Env<'a>, data_dir: String, input_json: String) -> Term<'a> {
    match parse_json::<IdempotencyRecord>(input_json) {
        Ok(input) => match treedx_store::put_idempotency_record(Path::new(&data_dir), input) {
            Ok(record) => ok_json(env, record),
            Err(error) => err_json(env, error.code(), error),
        },
        Err(error) => err_json(env, "invalid_json", format!("{error:?}")),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn get_idempotency_record<'a>(env: Env<'a>, data_dir: String, id: String) -> Term<'a> {
    match treedx_store::get_idempotency_record(Path::new(&data_dir), &id) {
        Ok(record) => ok_json(env, record),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn put_mirror<'a>(env: Env<'a>, data_dir: String, input_json: String) -> Term<'a> {
    match parse_json::<MirrorRecord>(input_json) {
        Ok(input) => match treedx_store::put_mirror(Path::new(&data_dir), input) {
            Ok(record) => ok_json(env, record),
            Err(error) => err_json(env, error.code(), error),
        },
        Err(error) => err_json(env, "invalid_json", format!("{error:?}")),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn build_snapshot_artifact<'a>(env: Env<'a>, data_dir: String, input_json: String) -> Term<'a> {
    match parse_json::<SnapshotBuildInput>(input_json) {
        Ok(input) => match treedx_store::build_snapshot_artifact(Path::new(&data_dir), input) {
            Ok(record) => ok_json(env, record),
            Err(error) => err_json(env, error.code(), error),
        },
        Err(error) => err_json(env, "invalid_json", format!("{error:?}")),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn get_snapshot_manifest<'a>(env: Env<'a>, data_dir: String, snapshot_id: String) -> Term<'a> {
    match treedx_store::get_snapshot_manifest(Path::new(&data_dir), &snapshot_id) {
        Ok(record) => ok_json(env, record),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn get_artifact<'a>(env: Env<'a>, data_dir: String, snapshot_id: String) -> Term<'a> {
    match treedx_store::get_artifact(Path::new(&data_dir), &snapshot_id) {
        Ok(record) => ok_json(env, record),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn read_artifact_bytes<'a>(env: Env<'a>, data_dir: String, snapshot_id: String) -> Term<'a> {
    match treedx_store::read_artifact_bytes(Path::new(&data_dir), &snapshot_id) {
        Ok(bytes) => ok_json(
            env,
            serde_json::json!({
                "contentBase64": base64::engine::general_purpose::STANDARD.encode(bytes)
            }),
        ),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn compact_storage<'a>(env: Env<'a>, data_dir: String, input_json: String) -> Term<'a> {
    match parse_json::<treedx_store::StorageCompactInput>(input_json) {
        Ok(input) => match treedx_store::compact_storage(Path::new(&data_dir), input) {
            Ok(result) => ok_json(env, result),
            Err(error) => err_json(env, error.code(), error),
        },
        Err(error) => err_json(env, "invalid_json", format!("{error:?}")),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn create_backup<'a>(env: Env<'a>, data_dir: String, input_json: String) -> Term<'a> {
    match parse_json::<treedx_store::StorageBackupInput>(input_json) {
        Ok(input) => match treedx_store::create_backup(Path::new(&data_dir), input) {
            Ok(result) => ok_json(env, result),
            Err(error) => err_json(env, error.code(), error),
        },
        Err(error) => err_json(env, "invalid_json", format!("{error:?}")),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn list_tdb_logs<'a>(env: Env<'a>, data_dir: String) -> Term<'a> {
    match treedx_store::list_tdb_logs(Path::new(&data_dir)) {
        Ok(result) => ok_json(env, result),
        Err(error) => err_json(env, error.code(), error),
    }
}
