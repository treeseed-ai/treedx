use base64::Engine;
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
fn put_workspace_file<'a>(env: Env<'a>, data_dir: String, input_json: String) -> Term<'a> {
    match parse_json::<WorkspaceFileInput>(input_json) {
        Ok(input) => match treedb_store::put_workspace_file(Path::new(&data_dir), input) {
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
    match treedb_store::get_workspace_file(Path::new(&data_dir), &workspace_id, &path) {
        Ok(record) => ok_json(env, record),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn list_workspace_files<'a>(env: Env<'a>, data_dir: String, workspace_id: String) -> Term<'a> {
    match treedb_store::list_workspace_files(Path::new(&data_dir), &workspace_id) {
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
            match treedb_store::read_workspace_file_content(Path::new(&data_dir), &record) {
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
        Ok(input) => match treedb_store::mark_workspace_committed(Path::new(&data_dir), input) {
            Ok(record) => ok_json(env, record),
            Err(error) => err_json(env, error.code(), error),
        },
        Err(error) => err_json(env, "invalid_json", format!("{error:?}")),
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

#[rustler::nif(schedule = "DirtyIo")]
fn list_tree_recursive<'a>(
    env: Env<'a>,
    path: String,
    ref_name: String,
    tree_path: Option<String>,
) -> Term<'a> {
    match treedb_git::list_tree_recursive(Path::new(&path), &ref_name, tree_path.as_deref()) {
        Ok(record) => ok_json(env, record),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn changed_paths<'a>(env: Env<'a>, path: String, base_ref: String, head_ref: String) -> Term<'a> {
    match treedb_git::changed_paths(Path::new(&path), &base_ref, &head_ref) {
        Ok(record) => ok_json(env, record),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn commit_overlay<'a>(env: Env<'a>, input_json: String) -> Term<'a> {
    let _ = input_json;
    err_json(
        env,
        "not_implemented",
        "commit_overlay uses the external treedb_git_worker process",
    )
}

#[rustler::nif(schedule = "DirtyIo")]
fn build_graph_index<'a>(env: Env<'a>, input_json: String) -> Term<'a> {
    match parse_json::<treedb_graph::GraphIndexInput>(input_json) {
        Ok(input) => match treedb_graph::build_graph_index(input) {
            Ok(index) => ok_json(env, index),
            Err(error) => err_json(env, error.code(), error),
        },
        Err(error) => err_json(env, "invalid_json", format!("{error:?}")),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn write_graph_segments<'a>(env: Env<'a>, data_dir: String, index_json: String) -> Term<'a> {
    match parse_json::<treedb_graph::GraphIndex>(index_json) {
        Ok(index) => match treedb_graph::write_graph_segments(Path::new(&data_dir), &index) {
            Ok(manifest) => ok_json(env, manifest),
            Err(error) => err_json(env, error.code(), error),
        },
        Err(error) => err_json(env, "invalid_json", format!("{error:?}")),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn read_graph_segments<'a>(
    env: Env<'a>,
    data_dir: String,
    repo_id: String,
    graph_version: String,
) -> Term<'a> {
    match treedb_graph::read_graph_segments(Path::new(&data_dir), &repo_id, &graph_version) {
        Ok(index) => ok_json(env, index),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn read_latest_graph_manifest<'a>(
    env: Env<'a>,
    data_dir: String,
    repo_id: String,
    ref_name: String,
) -> Term<'a> {
    match treedb_graph::read_latest_graph_manifest(Path::new(&data_dir), &repo_id, &ref_name) {
        Ok(manifest) => ok_json(env, manifest),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn search_graph<'a>(env: Env<'a>, index_json: String, request_json: String) -> Term<'a> {
    match (
        parse_json::<treedb_graph::GraphIndex>(index_json),
        parse_json::<treedb_graph::GraphSearchRequest>(request_json),
    ) {
        (Ok(index), Ok(request)) => match treedb_graph::search_graph(index, request) {
            Ok(results) => ok_json(env, results),
            Err(error) => err_json(env, error.code(), error),
        },
        _ => err_json(env, "invalid_json", "invalid graph search input"),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn query_graph<'a>(env: Env<'a>, index_json: String, request_json: String) -> Term<'a> {
    match (
        parse_json::<treedb_graph::GraphIndex>(index_json),
        parse_json::<treedb_graph::GraphQueryRequest>(request_json),
    ) {
        (Ok(index), Ok(request)) => match treedb_graph::query_graph(index, request) {
            Ok(result) => ok_json(env, result),
            Err(error) => err_json(env, error.code(), error),
        },
        _ => err_json(env, "invalid_json", "invalid graph query input"),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn related_nodes<'a>(
    env: Env<'a>,
    index_json: String,
    seed_id: String,
    request_json: String,
) -> Term<'a> {
    match (
        parse_json::<treedb_graph::GraphIndex>(index_json),
        parse_json::<treedb_graph::GraphQueryRequest>(request_json),
    ) {
        (Ok(index), Ok(request)) => match treedb_graph::related_nodes(index, &seed_id, request) {
            Ok(result) => ok_json(env, result),
            Err(error) => err_json(env, error.code(), error),
        },
        _ => err_json(env, "invalid_json", "invalid graph related input"),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn subgraph<'a>(
    env: Env<'a>,
    index_json: String,
    seed_ids_json: String,
    request_json: String,
) -> Term<'a> {
    match (
        parse_json::<treedb_graph::GraphIndex>(index_json),
        parse_json::<Vec<String>>(seed_ids_json),
        parse_json::<treedb_graph::GraphQueryRequest>(request_json),
    ) {
        (Ok(index), Ok(seed_ids), Ok(request)) => {
            match treedb_graph::subgraph(index, seed_ids, request) {
                Ok(result) => ok_json(env, result),
                Err(error) => err_json(env, error.code(), error),
            }
        }
        _ => err_json(env, "invalid_json", "invalid graph subgraph input"),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn build_context_pack<'a>(env: Env<'a>, index_json: String, request_json: String) -> Term<'a> {
    match (
        parse_json::<treedb_graph::GraphIndex>(index_json),
        parse_json::<treedb_graph::ContextPackRequest>(request_json),
    ) {
        (Ok(index), Ok(request)) => match treedb_graph::build_context_pack(index, request) {
            Ok(result) => ok_json(env, result),
            Err(error) => err_json(env, error.code(), error),
        },
        _ => err_json(env, "invalid_json", "invalid context input"),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn parse_ctx_dsl<'a>(env: Env<'a>, source: String) -> Term<'a> {
    ok_json(env, treedb_graph::parse_ctx_dsl(&source))
}

#[rustler::nif]
fn hash_token<'a>(env: Env<'a>, token: String) -> Term<'a> {
    ok_json(env, treedb_store::hash_token(&token))
}

rustler::init!("Elixir.TreeDb.Native");
