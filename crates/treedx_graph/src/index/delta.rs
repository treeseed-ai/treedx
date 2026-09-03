use crate::types::{GraphDelta, GraphDocument, GraphManifest};
use std::collections::BTreeMap;

pub(super) fn compute_delta(
    previous: Option<&GraphManifest>,
    previous_docs: &[GraphDocument],
    docs: &[GraphDocument],
) -> GraphDelta {
    let current: BTreeMap<&str, &GraphDocument> =
        docs.iter().map(|doc| (doc.path.as_str(), doc)).collect();
    if previous.is_none() {
        return GraphDelta {
            added: current.keys().map(|path| (*path).to_string()).collect(),
            modified: Vec::new(),
            removed: Vec::new(),
        };
    }
    if previous_docs.is_empty() {
        return GraphDelta::default();
    }
    let prior: BTreeMap<&str, &GraphDocument> = previous_docs
        .iter()
        .map(|doc| (doc.path.as_str(), doc))
        .collect();
    GraphDelta {
        added: current
            .keys()
            .filter(|path| !prior.contains_key(**path))
            .map(|path| (*path).to_string())
            .collect(),
        modified: current
            .iter()
            .filter(|(path, doc)| {
                prior
                    .get(**path)
                    .is_some_and(|old| old.object_id != doc.object_id)
            })
            .map(|(path, _)| (*path).to_string())
            .collect(),
        removed: prior
            .keys()
            .filter(|path| !current.contains_key(**path))
            .map(|path| (*path).to_string())
            .collect(),
    }
}
