use thiserror::Error;

#[derive(Debug, Error)]
pub enum GitError {
    #[error("io error: {0}")]
    Io(#[from] std::io::Error),
    #[error("git error: {0}")]
    Git(String),
    #[error("not found: {0}")]
    NotFound(String),
    #[error("validation error: {0}")]
    Validation(String),
    #[error("conflict: {0}")]
    Conflict(String),
    #[error("unsupported transport: {0}")]
    UnsupportedTransport(String),
}

impl GitError {
    pub fn code(&self) -> &'static str {
        match self {
            GitError::Io(_) => "io_error",
            GitError::Git(_) => "git_error",
            GitError::NotFound(_) => "not_found",
            GitError::Validation(_) => "validation_error",
            GitError::Conflict(_) => "conflict",
            GitError::UnsupportedTransport(_) => "unsupported_transport",
        }
    }
}
