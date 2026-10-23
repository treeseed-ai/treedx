//! Explicit offline repair of interrupted registered logs. Never used by readers.
use crate::error::StoreError;
use crate::log::{validate_envelope, LogEnvelope};
use serde::Serialize;
use std::fs::{self, File, OpenOptions};
use std::io::{BufRead, BufReader, Read};
use std::os::unix::fs::OpenOptionsExt;
use std::path::Path;

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Recovery {
    pub log: String,
    pub source_digest: String,
    pub original_bytes: u64,
    pub retained_bytes: u64,
    pub retained_records: u64,
    pub incomplete_bytes: u64,
    pub applied: bool,
    pub backup: Option<String>,
}

fn invalid(message: &str) -> StoreError {
    StoreError::InvalidRecord {
        file: "registered TreeDX log".into(),
        line: 0,
        message: message.into(),
    }
}

fn regular(path: &Path) -> Result<(), StoreError> {
    if !fs::symlink_metadata(path)?.file_type().is_file() {
        return Err(invalid(
            "Recovery requires an ordinary file, never a symlink.",
        ));
    }
    Ok(())
}

fn scan(path: &Path, log: &str, kind: &str) -> Result<Recovery, StoreError> {
    regular(path)?;
    let size = fs::metadata(path)?.len();
    let mut reader = BufReader::new(File::open(path)?);
    let mut bytes = Vec::new();
    let mut hash = blake3::Hasher::new();
    let mut offset = 0;
    let mut retained = 0;
    let mut records = 0;
    let mut line = 0;
    loop {
        bytes.clear();
        // Refuse oversized records instead of allocating an unbounded corrupt
        // line during offline repair. Ordinary readers retain their own policy.
        let count = reader
            .by_ref()
            .take(1_048_577)
            .read_until(b'\n', &mut bytes)?;
        if count == 0 {
            break;
        }
        if count > 1_048_576 {
            return Err(invalid("Log record exceeds recovery's 1 MiB bound."));
        }
        line += 1;
        hash.update(&bytes);
        offset += count as u64;
        if line == 1 {
            if bytes != format!("# treedx:{kind}:v1\n").as_bytes() {
                return Err(invalid("Exact registered log header required."));
            }
        } else if !bytes.iter().all(u8::is_ascii_whitespace) {
            match serde_json::from_slice::<LogEnvelope<serde_json::Value>>(&bytes) {
                Ok(record) => {
                    validate_envelope(&record, path, line, kind)?;
                    records += 1;
                }
                Err(error) if error.is_eof() && !bytes.ends_with(b"\n") && offset == size => {
                    return Ok(Recovery {
                        log: log.into(),
                        source_digest: format!("blake3:{}", hash.finalize()),
                        original_bytes: size,
                        retained_bytes: retained,
                        retained_records: records,
                        incomplete_bytes: count as u64,
                        applied: false,
                        backup: None,
                    });
                }
                Err(_) => {
                    return Err(invalid(
                        "Corruption is not an interrupted final record; no repair allowed.",
                    ))
                }
            }
        }
        retained = offset;
    }
    if line == 0 {
        return Err(invalid("Exact registered log header required."));
    }
    Ok(Recovery {
        log: log.into(),
        source_digest: format!("blake3:{}", hash.finalize()),
        original_bytes: size,
        retained_bytes: retained,
        retained_records: records,
        incomplete_bytes: 0,
        applied: false,
        backup: None,
    })
}

fn digest(path: &Path) -> Result<String, StoreError> {
    regular(path)?;
    let mut reader = File::open(path)?;
    let mut hash = blake3::Hasher::new();
    let mut buffer = [0; 65_536];
    loop {
        let count = reader.read(&mut buffer)?;
        if count == 0 {
            break;
        }
        hash.update(&buffer[..count]);
    }
    Ok(format!("blake3:{}", hash.finalize()))
}

/// `expected` is omitted for a read-only plan and required to apply that exact plan.
/// The normal runtime entrypoint holds the same lock for its entire lifetime.
pub fn recover(data_dir: &Path, log: &str, expected: Option<&str>) -> Result<Recovery, StoreError> {
    let (relative, kind) = crate::catalog::log_files()
        .into_iter()
        .find(|(path, _)| path == Path::new(log))
        .ok_or_else(|| invalid("Select an exact log registered by the original store."))?;
    let root = fs::canonicalize(data_dir)?;
    let lock_path = root.join(".treedx.lock");
    if lock_path.exists() {
        regular(&lock_path)?;
    }
    let lock = OpenOptions::new().read(true).open(lock_path)?;
    lock.try_lock()
        .map_err(|_| invalid("Stop the TreeDX service before offline recovery."))?;
    let path = root.join(&relative);
    if fs::canonicalize(path.parent().unwrap())? != root.join(relative.parent().unwrap()) {
        return Err(invalid(
            "Log must remain inside its original data directory.",
        ));
    }
    let mut report = scan(&path, log, kind)?;
    let Some(expected) = expected else {
        return Ok(report);
    };
    if expected != report.source_digest {
        return Err(invalid("Source changed after the read-only plan."));
    }
    if report.incomplete_bytes == 0 {
        return Ok(report);
    }
    let id = report.source_digest.strip_prefix("blake3:").unwrap();
    let backup_dir = root.join("recovery/backups").join(format!("log-tail-{id}"));
    let mut directory = root.clone();
    for component in ["recovery", "backups", &format!("log-tail-{id}")] {
        directory.push(component);
        if !directory.exists() {
            fs::create_dir(&directory)?;
        }
        if fs::canonicalize(&directory)? != directory {
            return Err(invalid(
                "Backup must remain inside the original data directory.",
            ));
        }
    }
    let backup = backup_dir.join("original.tdb");
    if !backup.exists() {
        let pending = backup_dir.join(format!("{}.pending", uuid::Uuid::new_v4()));
        let mut saved = OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&pending)?;
        std::io::copy(&mut File::open(&path)?, &mut saved)?;
        saved.sync_all()?;
        if digest(&pending)? != expected {
            return Err(invalid("Complete backup copy must match the exact plan."));
        }
        fs::rename(&pending, &backup)?;
        File::open(&backup_dir)?.sync_all()?;
    }
    if digest(&backup)? != expected || digest(&path)? != expected {
        return Err(invalid(
            "Original and complete retained backup must match the exact plan.",
        ));
    }
    let temporary = path.with_extension(format!("recovering-{}", uuid::Uuid::new_v4()));
    let mut output = OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(&temporary)?;
    let copied = std::io::copy(
        &mut File::open(&backup)?.take(report.retained_bytes),
        &mut output,
    )?;
    if copied != report.retained_bytes {
        return Err(invalid("Incomplete recovery prefix copy."));
    }
    output.sync_all()?;
    let verified = scan(&temporary, log, kind)?;
    if verified.incomplete_bytes != 0 || verified.retained_records != report.retained_records {
        return Err(invalid("Recovered prefix failed exact read-back."));
    }
    // A stale/interrupted repair never overwrites a changed original.
    if digest(&path)? != expected {
        return Err(invalid("Source changed before atomic replacement."));
    }
    fs::rename(&temporary, &path)?;
    File::open(path.parent().unwrap())?.sync_all()?;
    report.applied = true;
    report.backup = Some(format!("treedx://backup/log-tail-{id}/original.tdb"));
    Ok(report)
}
