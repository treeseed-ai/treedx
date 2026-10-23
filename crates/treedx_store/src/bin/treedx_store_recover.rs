use std::path::Path;
use treedx_store::recovery::connected_token_tail::recover;

fn main() {
    let arguments: Vec<String> = std::env::args().skip(1).collect();
    let result = match arguments.as_slice() {
        [directory] => recover(Path::new(directory), None),
        [directory, apply, expected] if apply == "--apply" => {
            recover(Path::new(directory), Some(expected))
        }
        _ => {
            eprintln!("Usage: treedx_store_recover DATA_DIR [--apply EXACT_PLAN_DIGEST]");
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
            eprintln!("Seen-token recovery refused ({}): {error}", error.code());
            std::process::exit(1);
        }
    }
}
