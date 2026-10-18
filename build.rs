use std::env;
use std::fs;
use std::path::PathBuf;

fn main() {
    // Dynamically locate the vendored HAL relative to the project root
    let manifest_dir = env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR not set");
    let loragw_path = format!("{}/sx1302_hal/libloragw", manifest_dir);

    println!("cargo:rustc-link-search=native={}", loragw_path);
    println!("cargo:rustc-link-lib=static=loragw");
    println!("cargo:rustc-link-lib=m");
    println!("cargo:rustc-link-lib=rt");

    let bindings = bindgen::Builder::default()
        .header(format!("{}/inc/loragw_hal.h", loragw_path))
        .generate()
        .expect("Unable to generate bindings");

    let out_path = PathBuf::from(env::var("OUT_DIR").unwrap()).join("bindings.rs");
    bindings.write_to_file(&out_path).expect("Couldn't write bindings!");

    // Rust 2026 FFI Syntax Compatibility Patch
    let mut code = fs::read_to_string(&out_path).expect("Failed to read bindings");
    code = code.replace("extern \"C\" {", "unsafe extern \"C\" {");
    fs::write(&out_path, code).expect("Failed to write patched bindings");
}
