use thiserror::Error;

#[derive(Debug, Error)]
pub enum GraphError {
    #[error("validation error: {0}")]
    Validation(String),
    #[error("graph not ready")]
    NotReady,
    #[error("not found: {0}")]
    NotFound(String),
    #[error("invalid graph record in {file} at line {line}: {message}")]
    InvalidRecord {
        file: String,
        line: usize,
        message: String,
    },
    #[error("checksum mismatch in {file} at line {line}")]
    Checksum { file: String, line: usize },
    #[error(transparent)]
    Io(#[from] std::io::Error),
    #[error(transparent)]
    Json(#[from] serde_json::Error),
}

impl GraphError {
    pub fn code(&self) -> &'static str {
        match self {
            GraphError::Validation(_) => "validation_error",
            GraphError::NotReady => "graph_not_ready",
            GraphError::NotFound(_) => "not_found",
            GraphError::InvalidRecord { .. } | GraphError::Checksum { .. } => "invalid_record",
            GraphError::Io(_) | GraphError::Json(_) => "internal_error",
        }
    }
}
