use std::env;
use std::path::Path;

fn main() {
    // Only build llama.cpp if the feature is enabled
    if cfg!() {
        // Set build settings for llama.cpp
        println!(
            "cargo:rustc-link-search=native={}/llama.cpp",
            env::var("OUT_DIR").unwrap()
        );
        println!("cargo:rustc-link-lib=static=llama");

        // Print rebuild conditions
        println!("cargo:rerun-if-changed=build.rs");
    }
}
