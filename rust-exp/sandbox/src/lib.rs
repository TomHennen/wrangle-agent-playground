//! Fixture library for the Rust build-sandbox experiment.

/// Trivial pure function so `cargo test`/`cargo build` have real work to do.
pub fn add(a: u64, b: u64) -> u64 {
    a + b
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::TcpListener;

    #[test]
    fn arithmetic() {
        assert_eq!(add(2, 2), 4);
    }

    /// Loopback must keep working inside the sandbox: a network-isolation
    /// mechanism that also kills 127.0.0.1 would break ordinary test suites.
    #[test]
    fn loopback_bind_works() {
        let l = TcpListener::bind("127.0.0.1:0").expect("bind 127.0.0.1:0");
        let port = l.local_addr().unwrap().port();
        assert!(port > 0, "got an ephemeral port: {port}");
    }
}
