use crate::support::{err_json, ok_json, parse_json};
use base64::Engine;
use rustler::{Env, Term};
use std::path::Path;

#[rustler::nif(schedule = "DirtyIo")]
fn inspect_repository<'a>(env: Env<'a>, path: String) -> Term<'a> {
    match treedx_git::inspect_repository(Path::new(&path)) {
        Ok(record) => ok_json(env, record),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn list_refs<'a>(env: Env<'a>, path: String) -> Term<'a> {
    match treedx_git::list_refs(Path::new(&path)) {
        Ok(record) => ok_json(env, record),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn list_remotes<'a>(env: Env<'a>, path: String) -> Term<'a> {
    match treedx_git::list_remotes(Path::new(&path)) {
        Ok(record) => ok_json(env, record),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn resolve_ref<'a>(env: Env<'a>, path: String, ref_name: String) -> Term<'a> {
    match treedx_git::resolve_ref(Path::new(&path), &ref_name) {
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
    match treedx_git::list_tree(Path::new(&path), &ref_name, tree_path.as_deref()) {
        Ok(record) => ok_json(env, record),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn read_blob<'a>(env: Env<'a>, path: String, ref_name: String, blob_path: String) -> Term<'a> {
    match treedx_git::read_blob(Path::new(&path), &ref_name, &blob_path) {
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
    match treedx_git::list_tree_recursive(Path::new(&path), &ref_name, tree_path.as_deref()) {
        Ok(record) => ok_json(env, record),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn changed_paths<'a>(env: Env<'a>, path: String, base_ref: String, head_ref: String) -> Term<'a> {
    match treedx_git::changed_paths(Path::new(&path), &base_ref, &head_ref) {
        Ok(record) => ok_json(env, record),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn fetch_remote<'a>(env: Env<'a>, input_json: String) -> Term<'a> {
    match parse_json::<treedx_git::FetchRemoteInput>(input_json) {
        Ok(input) => match treedx_git::fetch_remote(input) {
            Ok(record) => ok_json(env, record),
            Err(error) => err_json(env, error.code(), error),
        },
        Err(error) => err_json(env, "invalid_json", format!("{error:?}")),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn push_remote<'a>(env: Env<'a>, input_json: String) -> Term<'a> {
    match parse_json::<treedx_git::PushRemoteInput>(input_json) {
        Ok(input) => match treedx_git::push_remote(input) {
            Ok(record) => ok_json(env, record),
            Err(error) => err_json(env, error.code(), error),
        },
        Err(error) => err_json(env, "invalid_json", format!("{error:?}")),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn commit_overlay<'a>(env: Env<'a>, input_json: String) -> Term<'a> {
    let _ = input_json;
    err_json(
        env,
        "not_implemented",
        "commit_overlay uses the external treedx_git_worker process",
    )
}

#[rustler::nif(schedule = "DirtyIo")]
fn build_graph_index<'a>(env: Env<'a>, input_json: String) -> Term<'a> {
    match parse_json::<treedx_graph::GraphIndexInput>(input_json) {
        Ok(input) => match treedx_graph::build_graph_index(input) {
            Ok(index) => ok_json(env, index),
            Err(error) => err_json(env, error.code(), error),
        },
        Err(error) => err_json(env, "invalid_json", format!("{error:?}")),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn write_graph_segments<'a>(env: Env<'a>, data_dir: String, index_json: String) -> Term<'a> {
    match parse_json::<treedx_graph::GraphIndex>(index_json) {
        Ok(index) => match treedx_graph::write_graph_segments(Path::new(&data_dir), &index) {
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
    match treedx_graph::read_graph_segments(Path::new(&data_dir), &repo_id, &graph_version) {
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
    match treedx_graph::read_latest_graph_manifest(Path::new(&data_dir), &repo_id, &ref_name) {
        Ok(manifest) => ok_json(env, manifest),
        Err(error) => err_json(env, error.code(), error),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn search_graph<'a>(env: Env<'a>, index_json: String, request_json: String) -> Term<'a> {
    match (
        parse_json::<treedx_graph::GraphIndex>(index_json),
        parse_json::<treedx_graph::GraphSearchRequest>(request_json),
    ) {
        (Ok(index), Ok(request)) => match treedx_graph::search_graph(index, request) {
            Ok(results) => ok_json(env, results),
            Err(error) => err_json(env, error.code(), error),
        },
        _ => err_json(env, "invalid_json", "invalid graph search input"),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn query_graph<'a>(env: Env<'a>, index_json: String, request_json: String) -> Term<'a> {
    match (
        parse_json::<treedx_graph::GraphIndex>(index_json),
        parse_json::<treedx_graph::GraphQueryRequest>(request_json),
    ) {
        (Ok(index), Ok(request)) => match treedx_graph::query_graph(index, request) {
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
        parse_json::<treedx_graph::GraphIndex>(index_json),
        parse_json::<treedx_graph::GraphQueryRequest>(request_json),
    ) {
        (Ok(index), Ok(request)) => match treedx_graph::related_nodes(index, &seed_id, request) {
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
        parse_json::<treedx_graph::GraphIndex>(index_json),
        parse_json::<Vec<String>>(seed_ids_json),
        parse_json::<treedx_graph::GraphQueryRequest>(request_json),
    ) {
        (Ok(index), Ok(seed_ids), Ok(request)) => {
            match treedx_graph::subgraph(index, seed_ids, request) {
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
        parse_json::<treedx_graph::GraphIndex>(index_json),
        parse_json::<treedx_graph::ContextPackRequest>(request_json),
    ) {
        (Ok(index), Ok(request)) => match treedx_graph::build_context_pack(index, request) {
            Ok(result) => ok_json(env, result),
            Err(error) => err_json(env, error.code(), error),
        },
        _ => err_json(env, "invalid_json", "invalid context input"),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn parse_ctx_dsl<'a>(env: Env<'a>, source: String) -> Term<'a> {
    ok_json(env, treedx_graph::parse_ctx_dsl(&source))
}

#[rustler::nif]
fn hash_token<'a>(env: Env<'a>, token: String) -> Term<'a> {
    ok_json(env, treedx_store::hash_token(&token))
}

#[rustler::nif]
fn hash_bytes_base64<'a>(env: Env<'a>, content_base64: String) -> Term<'a> {
    match base64::engine::general_purpose::STANDARD.decode(content_base64) {
        Ok(bytes) => ok_json(env, treedx_store::hash_bytes(&bytes)),
        Err(error) => err_json(
            env,
            "validation_error",
            format!("invalid contentBase64: {error}"),
        ),
    }
}
