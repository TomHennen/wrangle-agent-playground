fn main() {
    let out = std::path::PathBuf::from(std::env::var("OUT_DIR").unwrap());
    bindgen::Builder::default()
        .header("wrapper.h")
        .generate()
        .unwrap()
        .write_to_file(out.join("b.rs"))
        .unwrap();
}
