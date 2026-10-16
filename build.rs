use std::env;
use std::fs;
use std::path::PathBuf;

fn main() {
    let home = env::var("HOME").expect("HOME environment variable not set");
    let loragw_path = format!("{}/sx1302_hal/libloragw", home);

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

    // The 2026 Rust Syntax Patch
    let mut code = fs::read_to_string(&out_path).expect("Failed to read bindings");
    code = code.replace("extern \"C\" {", "unsafe extern \"C\" {");
    fs::write(&out_path, code).expect("Failed to write patched bindings");
}
