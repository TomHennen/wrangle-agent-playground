#!/usr/bin/env bash
# usage: mac_run.sh <profile-name>; profiles defined below.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
export WORKDIR="$HERE/macfix"
LO='(allow network* (local ip "localhost:*")) (allow network* (remote ip "localhost:*"))'
case "$1" in
  P0-deny-all)        PROF='(version 1)(allow default)(deny network*)' ;;
  P1-localhost)       PROF="(version 1)(allow default)(deny network*) $LO" ;;
  P2-localhost+unix)  PROF="(version 1)(allow default)(deny network*) $LO (allow network* (remote unix-socket))" ;;
  P3-localhost+bindunix) PROF="(version 1)(allow default)(deny network*) $LO (allow network-bind (local unix-socket))" ;;
  P4-split-rules)     PROF='(version 1)(allow default)(deny network*)(allow network-bind (local ip "localhost:*"))(allow network-inbound (local ip "localhost:*"))(allow network-outbound (remote ip "localhost:*"))' ;;
  *) echo unknown; exit 2 ;;
esac
printf '########## PROFILE %s\n%s\n' "$1" "$PROF"
sandbox-exec -p "$PROF" bash "$HERE/mac_inner.sh" 2>&1
echo "SANDBOX_EXEC_RC=$?"
