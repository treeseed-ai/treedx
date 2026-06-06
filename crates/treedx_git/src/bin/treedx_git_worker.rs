use std::io::Read;

fn main() {
    let mut args = std::env::args().skip(1);
    let command = args.next().unwrap_or_default();
    let input_path = args.next();
    let result = match command.as_str() {
        "commit-overlay" => commit_overlay(input_path.as_deref()),
        _ => Err(error(
            "validation_error",
            format!("unknown treedx_git_worker command: {command}"),
        )),
    };

    match result {
        Ok(value) => println!("{}", serde_json::to_string(&value).unwrap()),
        Err(error) => {
            eprintln!("{}", serde_json::to_string(&error).unwrap());
            std::process::exit(1);
        }
    }
}

fn commit_overlay(input_path: Option<&str>) -> Result<serde_json::Value, serde_json::Value> {
    let input = if let Some(input_path) = input_path {
        std::fs::read_to_string(input_path).map_err(|err| error("io_error", err.to_string()))?
    } else {
        let mut input = String::new();
        std::io::stdin()
            .read_to_string(&mut input)
            .map_err(|err| error("io_error", err.to_string()))?;
        input
    };
    let input: treedx_git::CommitOverlayInput =
        serde_json::from_str(&input).map_err(|err| error("invalid_json", err.to_string()))?;
    treedx_git::commit_overlay(input)
        .map(|result| serde_json::to_value(result).unwrap())
        .map_err(|err| error(err.code(), err.to_string()))
}

fn error(code: &str, message: String) -> serde_json::Value {
    serde_json::json!({
        "code": code,
        "message": message,
        "details": {}
    })
}
