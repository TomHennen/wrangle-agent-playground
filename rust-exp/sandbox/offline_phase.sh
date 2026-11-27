#!/usr/bin/env bash
# The "build offline" phase: runs the real cargo steps with NO network.
# Driven entirely by env (HOME/CARGO_HOME/RUSTUP_HOME/PATH/WORKDIR) so it works
# identically under every sandbox wrapper. Prints a clear banner + final RC.
set -uo pipefail

cd "${WORKDIR:?}" || exit 97
printf '::group::offline_phase identity\n'
printf 'id: %s\n' "$(id 2>&1)"
printf 'cargo: %s\n' "$(command -v cargo 2>&1)"
printf 'HOME=%s CARGO_HOME=%s RUSTUP_HOME=%s\n' "$HOME" "${CARGO_HOME:-}" "${RUSTUP_HOME:-}"
printf '::endgroup::\n'

rc=0
run() { printf '::group::%s\n' "$*"; "$@"; local r=$?; printf 'rc=%s\n::endgroup::\n' "$r"; [ "$r" -ne 0 ] && rc=$r; return 0; }

run cargo build --offline --locked
run cargo test  --offline --locked
run cargo package --offline --locked --allow-dirty

printf 'OFFLINE_PHASE_RC=%s\n' "$rc"
exit "$rc"
