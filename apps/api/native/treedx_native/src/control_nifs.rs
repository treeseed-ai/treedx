use crate::support::{err_json, ok_json, parse_json};
use base64::Engine;
use rustler::{Env, Term};
use std::path::Path;
use treedx_store::*;

#[rustler::nif(schedule = "DirtyIo")]
fn put_graph_refresh_job<'a>(env: Env<'a>, data_dir: String, input_json: String) -> Term<'a> {
    match parse_json::<GraphRefreshJobRecord>(input_json) {
        Ok(input) => match treedx_store::put_graph_refresh_job(Path::new(&data_dir), input) {
            Ok(record) => ok_json(env, record),
            Err(error) => err_json(env, error.code(), error),
        },
        Err(error) => err_json(env, "invalid_json", format!("{error:?}")),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn get_graph_refresh_job<'a>(
    env: Env<'a>,
    data_dir: String,
    repo_id: String,
    job_id: String,
) -> Term<'a> {
    match treedx_store::get_graph_refresh_job(Path::new(&data_dir), &repo_id, &job_id) {
        Ok(record) => ok_json(env, record),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn put_search_index_manifest<'a>(env: Env<'a>, data_dir: String, input_json: String) -> Term<'a> {
    match parse_json::<SearchIndexManifestRecord>(input_json) {
        Ok(input) => match treedx_store::put_search_index_manifest(Path::new(&data_dir), input) {
            Ok(record) => ok_json(env, record),
            Err(error) => err_json(env, error.code(), error),
        },
        Err(error) => err_json(env, "invalid_json", format!("{error:?}")),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn get_search_index_manifest<'a>(
    env: Env<'a>,
    data_dir: String,
    repo_id: String,
    ref_name: String,
) -> Term<'a> {
    match treedx_store::get_search_index_manifest(Path::new(&data_dir), &repo_id, &ref_name) {
        Ok(record) => ok_json(env, record),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn put_search_index_segment<'a>(env: Env<'a>, data_dir: String, input_json: String) -> Term<'a> {
    match parse_json::<SearchIndexSegmentRecord>(input_json) {
        Ok(input) => match treedx_store::put_search_index_segment(Path::new(&data_dir), input) {
            Ok(record) => ok_json(env, record),
            Err(error) => err_json(env, error.code(), error),
        },
        Err(error) => err_json(env, "invalid_json", format!("{error:?}")),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn list_search_index_segments<'a>(
    env: Env<'a>,
    data_dir: String,
    repo_id: String,
    ref_name: String,
) -> Term<'a> {
    match treedx_store::list_search_index_segments(Path::new(&data_dir), &repo_id, &ref_name) {
        Ok(records) => ok_json(env, records),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn compact_search_index<'a>(env: Env<'a>, data_dir: String, input_json: String) -> Term<'a> {
    match parse_json::<SearchIndexCompactInput>(input_json) {
        Ok(input) => match treedx_store::compact_search_index(Path::new(&data_dir), input) {
            Ok(result) => ok_json(env, result),
            Err(error) => err_json(env, error.code(), error),
        },
        Err(error) => err_json(env, "invalid_json", format!("{error:?}")),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn put_mirror_sync<'a>(env: Env<'a>, data_dir: String, input_json: String) -> Term<'a> {
    match parse_json::<MirrorSyncRecord>(input_json) {
        Ok(input) => match treedx_store::put_mirror_sync(Path::new(&data_dir), input) {
            Ok(record) => ok_json(env, record),
            Err(error) => err_json(env, error.code(), error),
        },
        Err(error) => err_json(env, "invalid_json", format!("{error:?}")),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn get_mirror_sync<'a>(env: Env<'a>, data_dir: String, sync_id: String) -> Term<'a> {
    match treedx_store::get_mirror_sync(Path::new(&data_dir), &sync_id) {
        Ok(record) => ok_json(env, record),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn list_mirror_syncs<'a>(env: Env<'a>, data_dir: String, input_json: String) -> Term<'a> {
    match parse_json::<serde_json::Value>(input_json) {
        Ok(input) => match treedx_store::list_mirror_syncs(
            Path::new(&data_dir),
            input
                .get("repoId")
                .and_then(|value| value.as_str())
                .unwrap_or(""),
            input.get("mirrorId").and_then(|value| value.as_str()),
        ) {
            Ok(records) => ok_json(env, records),
            Err(error) => err_json(env, error.code(), error),
        },
        Err(error) => err_json(env, "invalid_json", format!("{error:?}")),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn put_migration<'a>(env: Env<'a>, data_dir: String, input_json: String) -> Term<'a> {
    match parse_json::<MigrationRecord>(input_json) {
        Ok(input) => match treedx_store::put_migration(Path::new(&data_dir), input) {
            Ok(record) => ok_json(env, record),
            Err(error) => err_json(env, error.code(), error),
        },
        Err(error) => err_json(env, "invalid_json", format!("{error:?}")),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn get_migration<'a>(
    env: Env<'a>,
    data_dir: String,
    repo_id: String,
    migration_id: String,
) -> Term<'a> {
    match treedx_store::get_migration(Path::new(&data_dir), &repo_id, &migration_id) {
        Ok(record) => ok_json(env, record),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn put_dev_token<'a>(env: Env<'a>, data_dir: String, input_json: String) -> Term<'a> {
    match parse_json::<DevTokenRecord>(input_json) {
        Ok(input) => match treedx_store::put_dev_token(Path::new(&data_dir), input) {
            Ok(()) => ok_json(env, serde_json::json!({"ok": true})),
            Err(error) => err_json(env, error.code(), error),
        },
        Err(error) => err_json(env, "invalid_json", format!("{error:?}")),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn get_dev_token_by_hash<'a>(env: Env<'a>, data_dir: String, token_hash: String) -> Term<'a> {
    match treedx_store::get_dev_token_by_hash(Path::new(&data_dir), &token_hash) {
        Ok(record) => ok_json(env, record),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn put_capability_grant<'a>(env: Env<'a>, data_dir: String, input_json: String) -> Term<'a> {
    match parse_json::<CapabilityGrantRecord>(input_json) {
        Ok(input) => match treedx_store::put_capability_grant(Path::new(&data_dir), input) {
            Ok(record) => ok_json(env, record),
            Err(error) => err_json(env, error.code(), error),
        },
        Err(error) => err_json(env, "invalid_json", format!("{error:?}")),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn list_capability_grants<'a>(env: Env<'a>, data_dir: String, input_json: String) -> Term<'a> {
    match parse_json::<serde_json::Value>(input_json) {
        Ok(input) => match treedx_store::list_capability_grants(
            Path::new(&data_dir),
            input.get("actorId").and_then(|value| value.as_str()),
            input.get("repoId").and_then(|value| value.as_str()),
        ) {
            Ok(records) => ok_json(env, records),
            Err(error) => err_json(env, error.code(), error),
        },
        Err(error) => err_json(env, "invalid_json", format!("{error:?}")),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn put_connected_token<'a>(env: Env<'a>, data_dir: String, input_json: String) -> Term<'a> {
    match parse_json::<ConnectedTokenRecord>(input_json) {
        Ok(input) => match treedx_store::put_connected_token(Path::new(&data_dir), input) {
            Ok(()) => ok_json(env, serde_json::json!({"ok": true})),
            Err(error) => err_json(env, error.code(), error),
        },
        Err(error) => err_json(env, "invalid_json", format!("{error:?}")),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn get_connected_token<'a>(env: Env<'a>, data_dir: String, jti: String) -> Term<'a> {
    match treedx_store::get_connected_token(Path::new(&data_dir), &jti) {
        Ok(record) => ok_json(env, record),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn put_policy_refresh<'a>(env: Env<'a>, data_dir: String, input_json: String) -> Term<'a> {
    match parse_json::<PolicyRefreshRecord>(input_json) {
        Ok(input) => match treedx_store::put_policy_refresh(Path::new(&data_dir), input) {
            Ok(record) => ok_json(env, record),
            Err(error) => err_json(env, error.code(), error),
        },
        Err(error) => err_json(env, "invalid_json", format!("{error:?}")),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn list_audit_events<'a>(env: Env<'a>, data_dir: String, input_json: String) -> Term<'a> {
    match parse_json::<AuditQuery>(input_json) {
        Ok(input) => match treedx_store::list_audit_events(Path::new(&data_dir), input) {
            Ok(records) => ok_json(env, records),
            Err(error) => err_json(env, error.code(), error),
        },
        Err(error) => err_json(env, "invalid_json", format!("{error:?}")),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn resolve_effective_scope<'a>(
    env: Env<'a>,
    data_dir: String,
    actor_id: String,
    repo_id: Option<String>,
) -> Term<'a> {
    match treedx_store::resolve_effective_scope(Path::new(&data_dir), &actor_id, repo_id.as_deref())
    {
        Ok(scope) => ok_json(env, scope),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn append_audit_event<'a>(env: Env<'a>, data_dir: String, input_json: String) -> Term<'a> {
    match parse_json::<AuditEventInput>(input_json) {
        Ok(input) => match treedx_store::append_audit_event(Path::new(&data_dir), input) {
            Ok(record) => ok_json(env, record),
            Err(error) => err_json(env, error.code(), error),
        },
        Err(error) => err_json(env, "invalid_json", format!("{error:?}")),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn append_audit_events<'a>(env: Env<'a>, data_dir: String, input_json: String) -> Term<'a> {
    match parse_json::<Vec<AuditEventInput>>(input_json) {
        Ok(input) => match treedx_store::append_audit_events(Path::new(&data_dir), input) {
            Ok(record) => ok_json(env, record),
            Err(error) => err_json(env, error.code(), error),
        },
        Err(error) => err_json(env, "invalid_json", format!("{error:?}")),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn put_workspace<'a>(env: Env<'a>, data_dir: String, input_json: String) -> Term<'a> {
    match parse_json::<WorkspaceInput>(input_json) {
        Ok(input) => match treedx_store::put_workspace(Path::new(&data_dir), input) {
            Ok(record) => ok_json(env, record),
            Err(error) => err_json(env, error.code(), error),
        },
        Err(error) => err_json(env, "invalid_json", format!("{error:?}")),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn get_workspace<'a>(env: Env<'a>, data_dir: String, workspace_id: String) -> Term<'a> {
    match treedx_store::get_workspace(Path::new(&data_dir), &workspace_id) {
        Ok(record) => ok_json(env, record),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn close_workspace<'a>(env: Env<'a>, data_dir: String, workspace_id: String) -> Term<'a> {
    match treedx_store::close_workspace(Path::new(&data_dir), &workspace_id) {
        Ok(record) => ok_json(env, record),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn cleanup_expired_workspaces<'a>(env: Env<'a>, data_dir: String) -> Term<'a> {
    match treedx_store::cleanup_expired_workspaces(Path::new(&data_dir)) {
        Ok(report) => ok_json(env, report),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn quarantine_workspace<'a>(env: Env<'a>, data_dir: String, input_json: String) -> Term<'a> {
    match parse_json::<WorkspaceQuarantineInput>(input_json) {
        Ok(input) => match treedx_store::quarantine_workspace(Path::new(&data_dir), input) {
            Ok(record) => ok_json(env, record),
            Err(error) => err_json(env, error.code(), error),
        },
        Err(error) => err_json(env, "invalid_json", format!("{error:?}")),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn update_workspace_policy<'a>(env: Env<'a>, data_dir: String, input_json: String) -> Term<'a> {
    match parse_json::<WorkspacePolicyUpdateInput>(input_json) {
        Ok(input) => match treedx_store::update_workspace_policy(Path::new(&data_dir), input) {
            Ok(record) => ok_json(env, record),
            Err(error) => err_json(env, error.code(), error),
        },
        Err(error) => err_json(env, "invalid_json", format!("{error:?}")),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn list_quarantined_workspaces<'a>(
    env: Env<'a>,
    data_dir: String,
    _input_json: String,
) -> Term<'a> {
    match treedx_store::list_quarantined_workspaces(Path::new(&data_dir)) {
        Ok(records) => ok_json(env, records),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn put_workspace_file<'a>(env: Env<'a>, data_dir: String, input_json: String) -> Term<'a> {
    match parse_json::<WorkspaceFileInput>(input_json) {
        Ok(input) => match treedx_store::put_workspace_file(Path::new(&data_dir), input) {
            Ok(record) => ok_json(env, record),
            Err(error) => err_json(env, error.code(), error),
        },
        Err(error) => err_json(env, "invalid_json", format!("{error:?}")),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn get_workspace_file<'a>(
    env: Env<'a>,
    data_dir: String,
    workspace_id: String,
    path: String,
) -> Term<'a> {
    match treedx_store::get_workspace_file(Path::new(&data_dir), &workspace_id, &path) {
        Ok(record) => ok_json(env, record),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn list_workspace_files<'a>(env: Env<'a>, data_dir: String, workspace_id: String) -> Term<'a> {
    match treedx_store::list_workspace_files(Path::new(&data_dir), &workspace_id) {
        Ok(record) => ok_json(env, record),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn read_workspace_file_content<'a>(
    env: Env<'a>,
    data_dir: String,
    record_json: String,
) -> Term<'a> {
    match parse_json::<WorkspaceFileRecord>(record_json) {
        Ok(record) => {
            match treedx_store::read_workspace_file_content(Path::new(&data_dir), &record) {
                Ok(Some(bytes)) => ok_json(
                    env,
                    serde_json::json!({
                        "contentBase64": base64::engine::general_purpose::STANDARD.encode(bytes)
                    }),
                ),
                Ok(None) => ok_json(env, serde_json::json!({"contentBase64": null})),
                Err(error) => err_json(env, error.code(), error),
            }
        }
        Err(error) => err_json(env, "invalid_json", format!("{error:?}")),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn mark_workspace_committed<'a>(env: Env<'a>, data_dir: String, input_json: String) -> Term<'a> {
    match parse_json::<WorkspaceCommitMarkInput>(input_json) {
        Ok(input) => match treedx_store::mark_workspace_committed(Path::new(&data_dir), input) {
            Ok(record) => ok_json(env, record),
            Err(error) => err_json(env, error.code(), error),
        },
        Err(error) => err_json(env, "invalid_json", format!("{error:?}")),
    }
}
