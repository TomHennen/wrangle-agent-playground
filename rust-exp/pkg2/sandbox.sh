#!/usr/bin/env bash
# usage: sandbox.sh <dir> <cmd...>   — run cmd in dir with no network, dropped privileges, scrubbed env
set -uo pipefail
DIR="${1:?}"; shift
ENVF="$(mktemp /tmp/sbx-env.XXXXXX.sh)"; chmod 0644 "$ENVF"
cat >"$ENVF" <<E2
export HOME='$HOME' CARGO_HOME='$CARGO_HOME' RUSTUP_HOME='${RUSTUP_HOME:-$HOME/.rustup}' PATH='$PATH'
export RUSTUP_TOOLCHAIN='${RUSTUP_TOOLCHAIN:-}'
export CARGO_TARGET_DIR='${CARGO_TARGET_DIR:-}'
[ -n "\$RUSTUP_TOOLCHAIN" ] || unset RUSTUP_TOOLCHAIN
[ -n "\$CARGO_TARGET_DIR" ] || unset CARGO_TARGET_DIR
cd '$DIR'
E2
CMD="$(printf '%q ' "$@")"
sudo unshare -n bash -c '
  ip link set lo up
  exec setpriv --reuid '"$(id -u)"' --regid '"$(id -g)"' --clear-groups --no-new-privs \
    bash -c "source '"$ENVF"'; echo sandbox-net: \$(cat /proc/net/dev | tail -n +3 | cut -d: -f1 | tr -d \" \" | tr \"\n\" \",\"); (curl -sS -m 5 -o /dev/null https://index.crates.io/config.json && echo NET-REACHABLE) || echo net-blocked; id; '"$CMD"'"'
