use std::path::Path;
use treedx_store::recovery::log_tail::recover;

fn main() {
    let arguments: Vec<String> = std::env::args().skip(1).collect();
    let result = match arguments.as_slice() {
        [directory, log] => recover(Path::new(directory), log, None),
        [directory, log, apply, expected] if apply == "--apply" => {
            recover(Path::new(directory), log, Some(expected))
        }
        _ => {
            eprintln!(
                "Usage: treedx_store_recover DATA_DIR REGISTERED_LOG [--apply EXACT_PLAN_DIGEST]"
            );
            std::process::exit(2);
        }
    };
    match result {
        Ok(report) => println!(
            "{}",
            serde_json::to_string(&report).expect("Recovery metadata serializes")
        ),
        // No record payload or token material is emitted.
        Err(error) => {
            eprintln!("Log-tail recovery refused ({}): {error}", error.code());
            std::process::exit(1);
        }
    }
}
