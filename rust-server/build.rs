use std::env;

fn main() {
    // Only build llama.cpp if the feature is enabled
    if cfg!(feature = "llama_cpp") {
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
