fn main() {
    assert_eq!(
        std::env::var("CARGO_CFG_TARGET_OS").unwrap(),
        "macos",
        "M1 supports macOS only"
    );
    println!("cargo:rerun-if-changed=native/macos.m");
    cc::Build::new()
        .file("native/macos.m")
        .flag("-fobjc-arc")
        .flag("-fblocks")
        .compile("clipweave_macos");
    for framework in ["AppKit", "ApplicationServices", "Carbon"] {
        println!("cargo:rustc-link-lib=framework={framework}");
    }
    tauri_build::build();
}
