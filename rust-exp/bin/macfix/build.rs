//! Escape-probe build script: simulates a malicious dependency `build.rs`.
//!
//! It runs as the build user during `cargo build`/`test`/`package` and reports
//! the result of each escape attempt via `cargo:warning=`. Every attempt targets
//! only harmless endpoints (example.com, DNS, loopback) — no real exfiltration.
//! Results are also written to `$OUT_DIR/probe-results.txt`.

use std::io::Write as _;
use std::net::{TcpStream, ToSocketAddrs};
use std::process::Command;
use std::time::Duration;

fn warn(line: &str) {
    println!("cargo:warning=PROBE {line}");
}

const T: Duration = Duration::from_secs(4);

/// Try to open a TCP connection to a harmless public endpoint.
fn tcp_connect(hostport: &str) -> Result<String, String> {
    let addrs: Vec<_> = hostport
        .to_socket_addrs()
        .map_err(|e| format!("dns-fail: {e}"))?
        .collect();
    let addr = addrs.first().ok_or_else(|| "dns-empty".to_string())?;
    match TcpStream::connect_timeout(addr, T) {
        Ok(_) => Ok(format!("connected {addr}")),
        Err(e) => Err(format!("connect-fail: {e}")),
    }
}

/// Run a command with a bounded view of success; returns (ok, trimmed output).
fn run(cmd: &str, args: &[&str]) -> (bool, String) {
    match Command::new(cmd).args(args).output() {
        Ok(o) => {
            let mut s = String::from_utf8_lossy(&o.stdout).to_string();
            s.push_str(&String::from_utf8_lossy(&o.stderr));
            let s = s.split_whitespace().collect::<Vec<_>>().join(" ");
            (o.status.success(), s.chars().take(160).collect())
        }
        Err(e) => (false, format!("spawn-fail: {e}")),
    }
}

fn main() {
    let mut log: Vec<String> = Vec::new();
    let mut note = |l: String| {
        warn(&l);
        log.push(l);
    };

    // (a) direct DNS + TCP.
    match "example.com:80".to_socket_addrs() {
        Ok(a) => {
            let n = a.count();
            note(format!("a.dns: RESOLVED example.com ({n} addrs) [LEAK]"));
        }
        Err(e) => note(format!("a.dns: BLOCKED ({e})")),
    }
    match tcp_connect("example.com:80") {
        Ok(d) => note(format!("a.tcp: LEAK {d}")),
        Err(e) => note(format!("a.tcp: BLOCKED {e}")),
    }
    // Loopback should still work even in a net-isolated sandbox (lo up).
    match std::net::TcpListener::bind("127.0.0.1:0") {
        Ok(_) => note("a.loopback: OK bind 127.0.0.1".to_string()),
        Err(e) => note(format!("a.loopback: FAIL {e}")),
    }

    // (b) passwordless sudo -> re-enter host netns.
    let (sudo_ok, sudo_out) = run("sudo", &["-n", "true"]);
    if sudo_ok {
        note("b.sudo: AVAILABLE (sudo -n true) [ESCALATION]".to_string());
        let (ns_ok, ns_out) = run(
            "sudo",
            &["-n", "nsenter", "-t", "1", "-n", "getent", "hosts", "example.com"],
        );
        if ns_ok {
            note(format!("b.nsenter: LEAK host-netns dns ({ns_out})"));
        } else {
            note(format!("b.nsenter: BLOCKED ({ns_out})"));
        }
    } else {
        note(format!("b.sudo: BLOCKED ({sudo_out})"));
    }

    // (c) docker socket -> --network host container.
    let (dv_ok, dv_out) = run("docker", &["version", "--format", "{{.Server.Version}}"]);
    if dv_ok {
        note(format!("c.docker-sock: REACHABLE server={dv_out} [ESCALATION]"));
        // Only use an already-present image; never pull.
        let (img_ok, imgs) = run(
            "docker",
            &["images", "--format", "{{.Repository}}:{{.Tag}}", "--filter", "dangling=false"],
        );
        let image = if img_ok {
            imgs.split_whitespace()
                .find(|i| !i.contains("<none>") && !i.is_empty())
                .unwrap_or("")
                .to_string()
        } else {
            String::new()
        };
        if image.is_empty() {
            note("c.docker-run: SKIP (no cached image)".to_string());
        } else {
            let (r_ok, r_out) = run(
                "docker",
                &[
                    "run", "--rm", "--network", "host", &image, "sh", "-c",
                    "getent hosts example.com || nslookup example.com 2>/dev/null || true",
                ],
            );
            note(format!("c.docker-run: image={image} ok={r_ok} out={r_out}"));
        }
    } else {
        note(format!("c.docker-sock: BLOCKED ({dv_out})"));
    }

    // (d) host IPC crossing a netns.
    // abstract unix sockets live in the net namespace; /run/systemd, dbus, runner listeners.
    let systemd = std::path::Path::new("/run/systemd/system").exists();
    note(format!("d.run-systemd: /run/systemd/system exists={systemd}"));
    let dbus = std::path::Path::new("/run/dbus/system_bus_socket").exists();
    note(format!("d.dbus: /run/dbus/system_bus_socket exists={dbus}"));
    // scan a few common local listeners (runner/docker proxies) on loopback.
    let mut open_ports = Vec::new();
    for p in [22u16, 2375, 8080, 9100, 42424] {
        if TcpStream::connect_timeout(
            &format!("127.0.0.1:{p}").parse().unwrap(),
            Duration::from_millis(300),
        )
        .is_ok()
        {
            open_ports.push(p);
        }
    }
    note(format!("d.loopback-listeners: open={open_ports:?}"));
    // /proc visibility of PID 1 (shared pid namespace => host process table).
    let pid1 = std::fs::read_to_string("/proc/1/comm")
        .map(|s| s.trim().to_string())
        .unwrap_or_else(|_| "unreadable".to_string());
    note(format!("d.pid1-comm: {pid1}"));

    // (e) filesystem + token exfiltration surface.
    let outside = "/tmp/wrangle-escape-probe.txt";
    match std::fs::File::create(outside).and_then(|mut f| f.write_all(b"x")) {
        Ok(_) => note(format!("e.write-outside: WROTE {outside} [TAMPER]")),
        Err(e) => note(format!("e.write-outside: BLOCKED {e}")),
    }
    for var in [
        "GITHUB_ENV",
        "GITHUB_PATH",
        "GITHUB_OUTPUT",
        "ACTIONS_RUNTIME_TOKEN",
        "ACTIONS_ID_TOKEN_REQUEST_URL",
        "ACTIONS_ID_TOKEN_REQUEST_TOKEN",
        "GITHUB_TOKEN",
    ] {
        match std::env::var(var) {
            Ok(v) if !v.is_empty() => {
                note(format!("e.env[{var}]: PRESENT len={} [SECRET]", v.len()))
            }
            _ => note(format!("e.env[{var}]: absent")),
        }
    }
    // try to read the parent's environ for tokens cargo did not forward.
    let ppid = std::fs::read_to_string("/proc/self/stat")
        .ok()
        .and_then(|s| s.split_whitespace().nth(3).map(|x| x.to_string()))
        .unwrap_or_default();
    let parent_env = format!("/proc/{ppid}/environ");
    match std::fs::read(&parent_env) {
        Ok(b) => {
            let txt = String::from_utf8_lossy(&b);
            let hit = ["ACTIONS_RUNTIME_TOKEN", "ACTIONS_ID_TOKEN", "GITHUB_TOKEN"]
                .iter()
                .filter(|k| txt.contains(**k))
                .count();
            note(format!("e.parent-environ: readable={parent_env} token-hits={hit}"));
        }
        Err(e) => note(format!("e.parent-environ: BLOCKED {parent_env} {e}")),
    }

    // Persist a machine-readable copy next to the build output.
    if let Ok(dir) = std::env::var("OUT_DIR") {
        let _ = std::fs::write(format!("{dir}/probe-results.txt"), log.join("\n"));
    }
    println!("cargo:rerun-if-changed=build.rs");
}
