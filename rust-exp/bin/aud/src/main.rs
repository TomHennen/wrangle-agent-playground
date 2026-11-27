use clap::Parser;

#[derive(Parser)]
struct Args {
    #[arg(long, default_value = "{\"a\":1}")]
    json: String,
}

fn main() {
    let a = Args::parse();
    let v: serde_json::Value = serde_json::from_str(&a.json).unwrap();
    let z = unsafe { std::ffi::CStr::from_ptr(libz_sys::zlibVersion()) };
    println!("{v} zlib={}", z.to_string_lossy());
}

#[cfg(test)]
mod tests {
    #[test]
    fn t() {
        let _d = tempfile::tempdir().unwrap();
    }
}
