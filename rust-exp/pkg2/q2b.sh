#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; source "$HERE/q2common.sh"
setup_src "$1" "$2"; cd "$ROOT"
cargo -V
DL="$W/dl"; ls -l "$DL"
echo "A digest: $(cut -d' ' -f1 "$DL/A.sha")"
echo "committed Cargo.lock: '$(git ls-files Cargo.lock)'; present: $(ls Cargo.lock 2>&1)"
sha() { sha256sum "$1" | cut -d' ' -f1; }
echo "######## B1: with extracted lock"
mkdir "$W/xb"; tar xzf "$DL/A.crate" -C "$W/xb"; cp "$W"/xb/*/Cargo.lock Cargo.lock
[[ -n "$(git status --short Cargo.lock)" ]] && { echo "Cargo.lock untracked+visible; adding to info/exclude"; echo Cargo.lock >> "$(git rev-parse --git-dir)/info/exclude"; }
cargo package --no-verify --locked 2>&1 | tail -3; C=$(ls target/package/*.crate | head -1); echo "B1 package: $(sha "$C")"
[[ $(sha "$C") == $(cut -d' ' -f1 "$DL/A.sha") ]] && echo "RESULT B1 package SAME as A" || echo "RESULT B1 package DIFFERENT from A"
cargo publish --dry-run --no-verify --locked 2>&1 | tail -4; echo "publish rc=${PIPESTATUS[0]}"
echo "B1 after publish --dry-run: $(sha "$C")"
[[ $(sha "$C") == $(cut -d' ' -f1 "$DL/A.sha") ]] && echo "RESULT B1 publish-dry SAME as A" || echo "RESULT B1 publish-dry DIFFERENT"
echo "######## B2: without lock, --locked"
rm -f Cargo.lock; rm -rf target/package
cargo package --no-verify --locked 2>&1 | tail -4; echo "rc=${PIPESTATUS[0]}"
echo "######## B3: without lock, fresh resolve (no age), no --locked"
cargo package --no-verify 2>&1 | tail -3; C=$(ls target/package/*.crate | head -1); echo "B3: $(sha "$C")"
[[ $(sha "$C") == $(cut -d' ' -f1 "$DL/A.sha") ]] && echo "RESULT B3 fresh SAME as A" || { echo "RESULT B3 fresh DIFFERENT from A"; rm -rf "$W/x3"; mkdir "$W/x3"; tar xzf "$C" -C "$W/x3"; diff "$W/xb"/*/Cargo.lock "$W"/x3/*/Cargo.lock | head -10; }
echo "######## B4: without lock, fresh resolve with 7-day age"
rm -f Cargo.lock; rm -rf target/package
CARGO_REGISTRY_GLOBAL_MIN_PUBLISH_AGE="7 days" cargo package --no-verify 2>&1 | tail -3; C=$(ls target/package/*.crate | head -1); echo "B4: $(sha "$C")"
[[ $(sha "$C") == $(cut -d' ' -f1 "$DL/A.sha") ]] && echo "RESULT B4 same as A" || echo "RESULT B4 different from A"
