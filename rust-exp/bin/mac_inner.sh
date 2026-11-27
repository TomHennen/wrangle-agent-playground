#!/usr/bin/env bash
# Runs inside sandbox-exec: build + test offline, then extra probes.
set -u
cd "$WORKDIR" || exit 97
cargo clean 2>&1 | tail -1
rc=0
printf '== cargo build --offline --locked\n'; cargo build --offline --locked 2>&1 | grep -E 'PROBE a\.|PROBE b\.|error|Finished|warning: unused' ; [ "${PIPESTATUS[0]}" -eq 0 ] || rc=1
printf '== cargo test --offline --locked\n'; cargo test --offline --locked 2>&1 | grep -E 'test |test result|error' ; [ "${PIPESTATUS[0]}" -eq 0 ] || rc=1
bash "$(dirname "$0")/mac_probes.sh"
printf 'INNER_RC=%s\n' "$rc"
