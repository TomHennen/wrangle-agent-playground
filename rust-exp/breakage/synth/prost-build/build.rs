fn main() {
    prost_build::compile_protos(&["proto/t.proto"], &["proto"]).unwrap();
}
