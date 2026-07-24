use crate::catalog::{get_record, list_records, put_record};
use crate::error::StoreError;
use crate::ids::mirror_id;
use crate::types::{
    FederationPeerRecord, FederationRouteRecord, IdempotencyRecord, MirrorAssignmentRecord,
    MirrorRecord, NodeCapacityRecord, RepositoryAdvertisementRecord, RepositoryPlacementRecord,
    WorkspaceRouteRecord,
};
use std::path::Path;

pub fn put_repository_placement(
    data_dir: &Path,
    record: RepositoryPlacementRecord,
) -> Result<RepositoryPlacementRecord, StoreError> {
    put_record(
        data_dir,
        "federation/repository_placements.tdb",
        "repository_placement",
        &record.repository_id,
        &record,
    )?;
    Ok(record)
}

pub fn get_repository_placement(
    data_dir: &Path,
    repo_id: &str,
) -> Result<Option<RepositoryPlacementRecord>, StoreError> {
    get_record(
        data_dir,
        "federation/repository_placements.tdb",
        "repository_placement",
        repo_id,
    )
}

pub fn put_mirror(data_dir: &Path, mut record: MirrorRecord) -> Result<MirrorRecord, StoreError> {
    if record.id.is_empty() {
        record.id = mirror_id(
            &record.repository_id,
            &record.source_node_id,
            &record.target_node_id,
            &record.mode,
        );
    }
    put_record(
        data_dir,
        "federation/mirrors.tdb",
        "mirror",
        &record.id,
        &record,
    )?;
    Ok(record)
}

pub fn list_mirrors(data_dir: &Path, repo_id: &str) -> Result<Vec<MirrorRecord>, StoreError> {
    Ok(
        list_records::<MirrorRecord>(data_dir, "federation/mirrors.tdb", "mirror")?
            .into_iter()
            .filter(|record| record.repository_id == repo_id)
            .collect(),
    )
}

pub fn put_federation_peer(
    data_dir: &Path,
    record: FederationPeerRecord,
) -> Result<FederationPeerRecord, StoreError> {
    put_record(
        data_dir,
        "federation/peers.tdb",
        "federation_peer",
        &record.id,
        &record,
    )?;
    Ok(record)
}

pub fn list_federation_peers(data_dir: &Path) -> Result<Vec<FederationPeerRecord>, StoreError> {
    list_records(data_dir, "federation/peers.tdb", "federation_peer")
}

pub fn get_federation_peer(
    data_dir: &Path,
    node_id: &str,
) -> Result<Option<FederationPeerRecord>, StoreError> {
    get_record(data_dir, "federation/peers.tdb", "federation_peer", node_id)
}

pub fn put_repository_advertisement(
    data_dir: &Path,
    record: RepositoryAdvertisementRecord,
) -> Result<RepositoryAdvertisementRecord, StoreError> {
    let id = format!("{}:{}", record.advertised_by_node_id, record.repository_id);
    put_record(
        data_dir,
        "federation/repository_advertisements.tdb",
        "repository_advertisement",
        &id,
        &record,
    )?;
    Ok(record)
}

pub fn list_repository_advertisements(
    data_dir: &Path,
) -> Result<Vec<RepositoryAdvertisementRecord>, StoreError> {
    list_records(
        data_dir,
        "federation/repository_advertisements.tdb",
        "repository_advertisement",
    )
}

pub fn put_federation_route(
    data_dir: &Path,
    record: FederationRouteRecord,
) -> Result<FederationRouteRecord, StoreError> {
    put_record(
        data_dir,
        "federation/routes.tdb",
        "federation_route",
        &record.repository_id,
        &record,
    )?;
    Ok(record)
}

pub fn list_federation_routes(data_dir: &Path) -> Result<Vec<FederationRouteRecord>, StoreError> {
    list_records(data_dir, "federation/routes.tdb", "federation_route")
}

pub fn get_federation_route(
    data_dir: &Path,
    repo_id: &str,
) -> Result<Option<FederationRouteRecord>, StoreError> {
    get_record(
        data_dir,
        "federation/routes.tdb",
        "federation_route",
        repo_id,
    )
}

pub fn put_node_capacity(
    data_dir: &Path,
    record: NodeCapacityRecord,
) -> Result<NodeCapacityRecord, StoreError> {
    put_record(
        data_dir,
        "federation/node_capacity.tdb",
        "node_capacity",
        &record.node_id,
        &record,
    )?;
    Ok(record)
}

pub fn list_node_capacity(data_dir: &Path) -> Result<Vec<NodeCapacityRecord>, StoreError> {
    list_records(data_dir, "federation/node_capacity.tdb", "node_capacity")
}

pub fn put_mirror_assignment(
    data_dir: &Path,
    record: MirrorAssignmentRecord,
) -> Result<MirrorAssignmentRecord, StoreError> {
    put_record(
        data_dir,
        "federation/mirror_assignments.tdb",
        "mirror_assignment",
        &record.id,
        &record,
    )?;
    Ok(record)
}

pub fn list_mirror_assignments(
    data_dir: &Path,
    repo_id: &str,
) -> Result<Vec<MirrorAssignmentRecord>, StoreError> {
    Ok(list_records::<MirrorAssignmentRecord>(
        data_dir,
        "federation/mirror_assignments.tdb",
        "mirror_assignment",
    )?
    .into_iter()
    .filter(|record| record.repository_id == repo_id)
    .collect())
}

pub fn put_workspace_route(
    data_dir: &Path,
    record: WorkspaceRouteRecord,
) -> Result<WorkspaceRouteRecord, StoreError> {
    put_record(
        data_dir,
        "federation/workspace_routes.tdb",
        "workspace_route",
        &record.workspace_id,
        &record,
    )?;
    Ok(record)
}

pub fn get_workspace_route(
    data_dir: &Path,
    workspace_id: &str,
) -> Result<Option<WorkspaceRouteRecord>, StoreError> {
    get_record(
        data_dir,
        "federation/workspace_routes.tdb",
        "workspace_route",
        workspace_id,
    )
}

pub fn put_idempotency_record(
    data_dir: &Path,
    record: IdempotencyRecord,
) -> Result<IdempotencyRecord, StoreError> {
    put_record(
        data_dir,
        "federation/idempotency.tdb",
        "idempotency",
        &record.id,
        &record,
    )?;
    Ok(record)
}

pub fn get_idempotency_record(
    data_dir: &Path,
    id: &str,
) -> Result<Option<IdempotencyRecord>, StoreError> {
    get_record(data_dir, "federation/idempotency.tdb", "idempotency", id)
}
