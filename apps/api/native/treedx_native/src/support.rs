use rustler::{Encoder, Env, Error as NifError, Term};
use serde::de::DeserializeOwned;
use serde::Serialize;

mod atoms {
    rustler::atoms! {
        ok,
        error
    }
}

pub(crate) fn ok_json<'a, T: Serialize>(env: Env<'a>, value: T) -> Term<'a> {
    let json = serde_json::to_string(&value).unwrap_or_else(|_| "{}".to_string());
    (atoms::ok(), json).encode(env)
}

pub(crate) fn err_json<'a, E: std::fmt::Display>(env: Env<'a>, code: &str, error: E) -> Term<'a> {
    let payload = serde_json::json!({
        "code": code,
        "message": error.to_string(),
        "details": {}
    });
    (atoms::error(), payload.to_string()).encode(env)
}

pub(crate) fn parse_json<T: DeserializeOwned>(input: String) -> Result<T, NifError> {
    serde_json::from_str(&input).map_err(|_| NifError::BadArg)
}
