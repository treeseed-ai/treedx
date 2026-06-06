use thiserror::Error;

#[derive(Debug, Error)]
pub enum StoreError {
    #[error("io error: {0}")]
    Io(#[from] std::io::Error),
    #[error("json error: {0}")]
    Json(#[from] serde_json::Error),
    #[error("record checksum mismatch in {file} at line {line}")]
    Checksum { file: String, line: usize },
    #[error("invalid record in {file} at line {line}: {message}")]
    InvalidRecord {
        file: String,
        line: usize,
        message: String,
    },
    #[error("not found: {0}")]
    NotFound(String),
    #[error("validation error: {0}")]
    Validation(String),
    #[error("conflict: {0}")]
    Conflict(String),
}

impl StoreError {
    pub fn code(&self) -> &'static str {
        match self {
            StoreError::Io(_) => "io_error",
            StoreError::Json(_) => "json_error",
            StoreError::Checksum { .. } => "checksum_mismatch",
            StoreError::InvalidRecord { .. } => "invalid_record",
            StoreError::NotFound(_) => "not_found",
            StoreError::Validation(_) => "validation_error",
            StoreError::Conflict(_) => "conflict",
        }
    }
}
