use super::{LogEnvelope, RecordPosition};
use crate::error::StoreError;
use crate::ids::payload_hash;
use serde::{de::DeserializeOwned, Serialize};
use std::fs;
use std::io::{BufRead, BufReader, Seek, SeekFrom};
use std::path::Path;

pub(super) fn replay_envelopes_unlocked<T: DeserializeOwned + Serialize>(
    path: &Path,
    kind: &str,
) -> Result<Vec<LogEnvelope<T>>, StoreError> {
    let mut out = Vec::new();
    visit_envelopes_unlocked(path, kind, |envelope| out.push(envelope))?;
    Ok(out)
}

pub(super) fn visit_envelopes_unlocked<T: DeserializeOwned + Serialize>(
    path: &Path,
    kind: &str,
    mut visit: impl FnMut(LogEnvelope<T>),
) -> Result<(), StoreError> {
    visit_positioned_envelopes(
        path,
        kind,
        RecordPosition { offset: 0, line: 1 },
        |envelope, _| visit(envelope),
    )?;
    Ok(())
}

pub(super) fn visit_positioned_envelopes<T: DeserializeOwned + Serialize>(
    path: &Path,
    kind: &str,
    start: RecordPosition,
    mut visit: impl FnMut(LogEnvelope<T>, RecordPosition),
) -> Result<usize, StoreError> {
    let mut file = fs::File::open(path)?;
    file.seek(SeekFrom::Start(start.offset))?;
    let mut reader = BufReader::new(file);
    let mut position = start;
    let mut last_line = start.line.saturating_sub(1);
    let mut line = String::new();
    loop {
        line.clear();
        let bytes = reader.read_line(&mut line)?;
        if bytes == 0 {
            break;
        }
        last_line = position.line;
        if !(position.line == 1 && line.starts_with("# treedx:")) && !line.trim().is_empty() {
            let envelope: LogEnvelope<T> =
                serde_json::from_str(&line).map_err(|err| StoreError::InvalidRecord {
                    file: path.display().to_string(),
                    line: position.line,
                    message: err.to_string(),
                })?;
            validate_envelope(&envelope, path, position.line, kind)?;
            visit(envelope, position);
        }
        position.offset += bytes as u64;
        position.line += 1;
    }
    Ok(last_line)
}

pub(super) fn read_indexed_record(
    path: &Path,
    kind: &str,
    record_id: &str,
    position: RecordPosition,
) -> Result<Option<serde_json::Value>, StoreError> {
    let mut file = fs::File::open(path)?;
    file.seek(SeekFrom::Start(position.offset))?;
    let mut line = String::new();
    BufReader::new(file).read_line(&mut line)?;
    let envelope: LogEnvelope<serde_json::Value> =
        serde_json::from_str(&line).map_err(|err| StoreError::InvalidRecord {
            file: path.display().to_string(),
            line: position.line,
            message: err.to_string(),
        })?;
    validate_envelope(&envelope, path, position.line, kind)?;
    if envelope.record_id != record_id {
        return Err(StoreError::InvalidRecord {
            file: path.display().to_string(),
            line: position.line,
            message: "indexed record identity changed".to_string(),
        });
    }
    Ok(if envelope.op == "delete" {
        None
    } else {
        Some(envelope.payload)
    })
}

pub(crate) fn validate_envelope<T: Serialize>(
    envelope: &LogEnvelope<T>,
    path: &Path,
    line: usize,
    kind: &str,
) -> Result<(), StoreError> {
    #[cfg(test)]
    super::VALIDATED_RECORDS.with(|count| count.set(count.get() + 1));
    if envelope.record_kind != kind {
        return Err(StoreError::InvalidRecord {
            file: path.display().to_string(),
            line,
            message: format!("expected kind {kind}, got {}", envelope.record_kind),
        });
    }
    if payload_hash(&envelope.payload)? != envelope.payload_hash {
        return Err(StoreError::Checksum {
            file: path.display().to_string(),
            line,
        });
    }
    Ok(())
}
