use std::env;
use std::fs;
use std::path::PathBuf;

use sha2::{Digest, Sha256};

fn main() {
    let payload = env::var_os("POMODORO_PAYLOAD_ZIP")
        .expect("POMODORO_PAYLOAD_ZIP must point to the staged Flutter release archive");
    let payload_path = PathBuf::from(payload);
    let payload_bytes = fs::read(&payload_path).expect("Could not read staged release archive");
    let hash = Sha256::digest(&payload_bytes)
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect::<String>();
    let embedded_payload = PathBuf::from(env::var_os("OUT_DIR").expect("OUT_DIR is unset"))
        .join("pomodoro-payload.zip");

    fs::copy(&payload_path, &embedded_payload).expect("Could not embed release archive");
    println!("cargo:rerun-if-env-changed=POMODORO_PAYLOAD_ZIP");
    println!("cargo:rerun-if-changed={}", payload_path.display());
    println!("cargo:rustc-env=POMODORO_PAYLOAD_HASH={hash}");
}
