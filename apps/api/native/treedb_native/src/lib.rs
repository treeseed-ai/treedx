use rustler::{Encoder, Env, Error as NifError, Term};
use serde::de::DeserializeOwned;
use serde::Serialize;
use std::path::Path;
use treedb_store::*;

mod atoms {
    rustler::atoms! {
        ok,
        error
    }
}

fn ok_json<'a, T: Serialize>(env: Env<'a>, value: T) -> Term<'a> {
    let json = serde_json::to_string(&value).unwrap_or_else(|_| "{}".to_string());
    (atoms::ok(), json).encode(env)
}

fn err_json<'a, E: std::fmt::Display>(env: Env<'a>, code: &str, error: E) -> Term<'a> {
    let payload = serde_json::json!({
        "code": code,
        "message": error.to_string(),
        "details": {}
    });
    (atoms::error(), payload.to_string()).encode(env)
}

fn parse_json<T: DeserializeOwned>(input: String) -> Result<T, NifError> {
    serde_json::from_str(&input).map_err(|_| NifError::BadArg)
}

#[rustler::nif(schedule = "DirtyIo")]
fn init_data_dir<'a>(env: Env<'a>, data_dir: String, opts_json: String) -> Term<'a> {
    match parse_json::<InitOptions>(opts_json) {
        Ok(opts) => match treedb_store::init_data_dir(Path::new(&data_dir), opts) {
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
    match treedb_store::seed_dev_records(Path::new(&data_dir), &node_id, &base_url) {
        Ok(report) => ok_json(env, report),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn put_repository<'a>(env: Env<'a>, data_dir: String, input_json: String) -> Term<'a> {
    match parse_json::<RepositoryInput>(input_json) {
        Ok(input) => match treedb_store::put_repository(Path::new(&data_dir), input) {
            Ok(record) => ok_json(env, record),
            Err(error) => err_json(env, error.code(), error),
        },
        Err(error) => err_json(env, "invalid_json", format!("{error:?}")),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn list_repositories<'a>(env: Env<'a>, data_dir: String) -> Term<'a> {
    match treedb_store::list_repositories(Path::new(&data_dir)) {
        Ok(records) => ok_json(env, records),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn get_repository<'a>(env: Env<'a>, data_dir: String, repo_id: String) -> Term<'a> {
    match treedb_store::get_repository(Path::new(&data_dir), &repo_id) {
        Ok(record) => ok_json(env, record),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn get_repository_placement<'a>(env: Env<'a>, data_dir: String, repo_id: String) -> Term<'a> {
    match treedb_store::get_repository_placement(Path::new(&data_dir), &repo_id) {
        Ok(record) => ok_json(env, record),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn put_repository_placement<'a>(env: Env<'a>, data_dir: String, input_json: String) -> Term<'a> {
    match parse_json::<RepositoryPlacementRecord>(input_json) {
        Ok(input) => match treedb_store::put_repository_placement(Path::new(&data_dir), input) {
            Ok(record) => ok_json(env, record),
            Err(error) => err_json(env, error.code(), error),
        },
        Err(error) => err_json(env, "invalid_json", format!("{error:?}")),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn list_nodes<'a>(env: Env<'a>, data_dir: String) -> Term<'a> {
    match treedb_store::list_nodes(Path::new(&data_dir)) {
        Ok(records) => ok_json(env, records),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn get_node<'a>(env: Env<'a>, data_dir: String, node_id: String) -> Term<'a> {
    match treedb_store::get_node(Path::new(&data_dir), &node_id) {
        Ok(record) => ok_json(env, record),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn list_mirrors<'a>(env: Env<'a>, data_dir: String, repo_id: String) -> Term<'a> {
    match treedb_store::list_mirrors(Path::new(&data_dir), &repo_id) {
        Ok(records) => ok_json(env, records),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn put_mirror<'a>(env: Env<'a>, data_dir: String, input_json: String) -> Term<'a> {
    match parse_json::<MirrorRecord>(input_json) {
        Ok(input) => match treedb_store::put_mirror(Path::new(&data_dir), input) {
            Ok(record) => ok_json(env, record),
            Err(error) => err_json(env, error.code(), error),
        },
        Err(error) => err_json(env, "invalid_json", format!("{error:?}")),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn put_dev_token<'a>(env: Env<'a>, data_dir: String, input_json: String) -> Term<'a> {
    match parse_json::<DevTokenRecord>(input_json) {
        Ok(input) => match treedb_store::put_dev_token(Path::new(&data_dir), input) {
            Ok(()) => ok_json(env, serde_json::json!({"ok": true})),
            Err(error) => err_json(env, error.code(), error),
        },
        Err(error) => err_json(env, "invalid_json", format!("{error:?}")),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn get_dev_token_by_hash<'a>(env: Env<'a>, data_dir: String, token_hash: String) -> Term<'a> {
    match treedb_store::get_dev_token_by_hash(Path::new(&data_dir), &token_hash) {
        Ok(record) => ok_json(env, record),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn resolve_effective_scope<'a>(
    env: Env<'a>,
    data_dir: String,
    actor_id: String,
    repo_id: Option<String>,
) -> Term<'a> {
    match treedb_store::resolve_effective_scope(Path::new(&data_dir), &actor_id, repo_id.as_deref())
    {
        Ok(scope) => ok_json(env, scope),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn append_audit_event<'a>(env: Env<'a>, data_dir: String, input_json: String) -> Term<'a> {
    match parse_json::<AuditEventInput>(input_json) {
        Ok(input) => match treedb_store::append_audit_event(Path::new(&data_dir), input) {
            Ok(record) => ok_json(env, record),
            Err(error) => err_json(env, error.code(), error),
        },
        Err(error) => err_json(env, "invalid_json", format!("{error:?}")),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn put_workspace<'a>(env: Env<'a>, data_dir: String, input_json: String) -> Term<'a> {
    match parse_json::<WorkspaceInput>(input_json) {
        Ok(input) => match treedb_store::put_workspace(Path::new(&data_dir), input) {
            Ok(record) => ok_json(env, record),
            Err(error) => err_json(env, error.code(), error),
        },
        Err(error) => err_json(env, "invalid_json", format!("{error:?}")),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn get_workspace<'a>(env: Env<'a>, data_dir: String, workspace_id: String) -> Term<'a> {
    match treedb_store::get_workspace(Path::new(&data_dir), &workspace_id) {
        Ok(record) => ok_json(env, record),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn close_workspace<'a>(env: Env<'a>, data_dir: String, workspace_id: String) -> Term<'a> {
    match treedb_store::close_workspace(Path::new(&data_dir), &workspace_id) {
        Ok(record) => ok_json(env, record),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn cleanup_expired_workspaces<'a>(env: Env<'a>, data_dir: String) -> Term<'a> {
    match treedb_store::cleanup_expired_workspaces(Path::new(&data_dir)) {
        Ok(report) => ok_json(env, report),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn inspect_repository<'a>(env: Env<'a>, path: String) -> Term<'a> {
    match treedb_git::inspect_repository(Path::new(&path)) {
        Ok(record) => ok_json(env, record),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn list_refs<'a>(env: Env<'a>, path: String) -> Term<'a> {
    match treedb_git::list_refs(Path::new(&path)) {
        Ok(record) => ok_json(env, record),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn list_remotes<'a>(env: Env<'a>, path: String) -> Term<'a> {
    match treedb_git::list_remotes(Path::new(&path)) {
        Ok(record) => ok_json(env, record),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn resolve_ref<'a>(env: Env<'a>, path: String, ref_name: String) -> Term<'a> {
    match treedb_git::resolve_ref(Path::new(&path), &ref_name) {
        Ok(record) => ok_json(env, record),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn list_tree<'a>(
    env: Env<'a>,
    path: String,
    ref_name: String,
    tree_path: Option<String>,
) -> Term<'a> {
    match treedb_git::list_tree(Path::new(&path), &ref_name, tree_path.as_deref()) {
        Ok(record) => ok_json(env, record),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn read_blob<'a>(env: Env<'a>, path: String, ref_name: String, blob_path: String) -> Term<'a> {
    match treedb_git::read_blob(Path::new(&path), &ref_name, &blob_path) {
        Ok(record) => ok_json(env, record),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif]
fn hash_token<'a>(env: Env<'a>, token: String) -> Term<'a> {
    ok_json(env, treedb_store::hash_token(&token))
}

rustler::init!("Elixir.TreeDb.Native");
