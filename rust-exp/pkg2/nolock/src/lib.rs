use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Debug)]
pub struct Point {
    pub x: i32,
    pub y: i32,
}

pub fn fmt(n: u64) -> String {
    itoa::Buffer::new().format(n).to_string()
}

pub fn pid() -> i32 {
    unsafe { libc::getpid() }
}
