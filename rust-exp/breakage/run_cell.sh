#!/usr/bin/env bash
# One matrix cell: online fetch, then sandboxed offline steps, then un-sandboxed reruns of failures.
# Env in: NAME REPO [TAGRE SUBDIR PKG LIB]
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${NAME:?}" "${REPO:?}"
TAGRE="${TAGRE:-^v?[0-9]+\.[0-9]+(\.[0-9]+)?$}"
SUBDIR="${SUBDIR:-.}"
PKG="${PKG:-}"
LIB="${LIB:-false}"
OUT="${OUT:-$PWD/out}"
BUDGET="${BUDGET:-6000}"
mkdir -p "$OUT/logs" "$OUT/steps"
SRC="$HOME/work/$NAME"; mkdir -p "$HOME/work"

TAG=""; TAGNOTE=""
if [[ "$REPO" == synth ]]; then
  cp -r "$HERE/synth/$NAME" "$SRC"; TAG=synthetic
else
  TAG="$(git ls-remote --tags --refs "https://github.com/$REPO" | awk '{sub("refs/tags/","",$2); print $2}' | grep -E "$TAGRE" | sort -V | tail -1)"
  if [[ -n "$TAG" ]]; then
    git clone -q --depth 1 --branch "$TAG" "https://github.com/$REPO" "$SRC"
  else
    TAGNOTE="no tag matched; default branch"; TAG=HEAD
    git clone -q --depth 1 "https://github.com/$REPO" "$SRC"
  fi
fi
WD="$SRC/$SUBDIR"; cd "$WD" || exit 1
COMMIT="$(git -C "$SRC" rev-parse --short HEAD 2>/dev/null || echo synth)"
LOCK_COMMITTED=false; [[ -f Cargo.lock ]] && LOCK_COMMITTED=true

# ---- ONLINE phase (network on)
t0=$SECONDS
{
  rustup update stable --no-self-update
  if ls rust-toolchain rust-toolchain.toml >/dev/null 2>&1; then rustup toolchain install; fi
  cargo --version; rustc --version; rustup show active-toolchain
  if [[ "$LOCK_COMMITTED" == false ]]; then cargo generate-lockfile || exit 11; fi
  cargo fetch --locked
} >"$OUT/logs/online.log" 2>&1
ONLINE_RC=$?
ONLINE_SECS=$((SECONDS - t0))
TOOLCHAIN="$(cargo --version 2>&1 | head -1)"

export CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}" RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}"
ENVF="$(mktemp /tmp/cell-env.XXXXXX.sh)"; chmod 0644 "$ENVF"
cat >"$ENVF" <<EOT
export HOME='$HOME'
export CARGO_HOME='$CARGO_HOME'
export RUSTUP_HOME='$RUSTUP_HOME'
export PATH='$PATH'
export LANG=C.UTF-8
export TERM=dumb
export USER='$(id -un)'
export LOGNAME='$(id -un)'
EOT
UID_N="$(id -u)"; GID_N="$(id -g)"

# mode: sb (sandbox: mechanism A), nosb (same scrubbed env, network on), full (inherited env, network on)
run_step() {
  local mode="$1" name="$2" tmo="$3"; shift 3
  local S; S="$(mktemp /tmp/cell-step.XXXXXX.sh)"; chmod 0644 "$S"
  { printf 'source %q\ncd %q || exit 97\nexec timeout -k 30 %s' "$ENVF" "$WD" "$tmo"; printf ' %q' "$@"; printf '\n'; } >"$S"
  local log="$OUT/logs/$name.$mode.log" t=$SECONDS rc
  case "$mode" in
    sb)
      sudo unshare -n bash -c '
        ip link set lo up
        exec setpriv --reuid '"$UID_N"' --regid '"$GID_N"' --clear-groups --no-new-privs \
          env -i bash '"$S"'' >"$log" 2>&1; rc=$? ;;
    nosb) env -i bash "$S" >"$log" 2>&1; rc=$? ;;
    full) ( cd "$WD" && timeout -k 30 "$tmo" "$@" ) >"$log" 2>&1; rc=$? ;;
  esac
  printf '%s' "$rc" >"$OUT/logs/$name.$mode.rc"
  printf '%s' "$((SECONDS - t))" >"$OUT/logs/$name.$mode.secs"
  printf '[%s] %s %s rc=%s (%ss)\n' "$NAME" "$mode" "$name" "$rc" "$((SECONDS - t))"
}

STEPS=(build testc testr)
declare -A CMD TMO
CMD[build]="cargo build --offline --locked --keep-going"; TMO[build]=2400
CMD[testc]="cargo test --offline --locked --no-run --keep-going"; TMO[testc]=2400
CMD[testr]="cargo test --offline --locked --no-fail-fast"; TMO[testr]=1200
if [[ "$LIB" == true ]]; then
  STEPS+=(pkg)
  CMD[pkg]="cargo package --offline --locked --allow-dirty${PKG:+ -p $PKG}"; TMO[pkg]=1200
fi

for s in "${STEPS[@]}"; do
  if ((SECONDS > BUDGET)); then printf 'skip' >"$OUT/logs/$s.sb.rc"; continue; fi
  # shellcheck disable=SC2086
  run_step sb "$s" "${TMO[$s]}" ${CMD[$s]}
done
for s in "${STEPS[@]}"; do
  rc="$(cat "$OUT/logs/$s.sb.rc" 2>/dev/null)"
  [[ "$rc" == 0 || "$rc" == 124 || "$rc" == skip || -z "$rc" ]] && continue
  if ((SECONDS > BUDGET + 1500)); then continue; fi
  # shellcheck disable=SC2086
  run_step nosb "$s" 900 ${CMD[$s]}
  if [[ "$(cat "$OUT/logs/$s.nosb.rc")" != 0 ]] && ((SECONDS < BUDGET + 1500)); then
    # shellcheck disable=SC2086
    run_step full "$s" 900 ${CMD[$s]}
  fi
done

# ---- classify + emit JSON
classify() { # logfile phase
  local f="$1" ph="$2"
  if grep -qiE "toolchain .* is not installed|component .* (is not installed|is unavailable)|rustup could not|no override and no default toolchain|can't find crate for .(core|std)" "$f"; then echo toolchain-not-installed
  elif grep -qiE "attempting to make an HTTP request, but --offline|you may need to run .cargo fetch|offline.*(not allowed|cannot)|no matching package named .* found" "$f"; then echo offline-resolution-gap
  elif grep -qiE "Permission denied|Read-only file system|os error 13" "$f"; then echo file-permission-home
  elif grep -qE "environment variable .* not defined|NotPresent|VarError|env var .* not set" "$f"; then echo env-var-scrubbed
  elif grep -qiE "Could not resolve|resolve address|name resolution|Network is unreachable|dns error|lookup address|error sending request|connect error|failed to connect|Name or service not known|Temporary failure|Connection refused|ConnectError" "$f"; then
    if [[ "$ph" == testr ]]; then echo test-network; else echo build-script-network; fi
  elif grep -qiE "docker|postgres|mysql|redis|DATABASE_URL" "$f"; then echo host-service
  elif grep -qiE "protoc|cmake|libclang|clang|python|perl|pkg-config|command not found|openssl.*not found" "$f"; then echo missing-system-prereq
  else echo unclassified; fi
}
failed_tests() { grep -E '^test .* \.\.\. FAILED$' "$1" 2>/dev/null | sort -u; }

echo '[]' >"$OUT/steps.json"
for s in build testc testr pkg; do
  rc="$(cat "$OUT/logs/$s.sb.rc" 2>/dev/null || echo na)"
  if [[ "$rc" == na ]]; then status="n/a"; cause=""; nrc=""; frc=""; only=""
  elif [[ "$rc" == skip ]]; then status="skipped-budget"; cause=""; nrc=""; frc=""; only=""
  elif [[ "$rc" == 0 ]]; then status=pass; cause=""; nrc=""; frc=""; only=""
  elif [[ "$rc" == 124 ]]; then status=timeout; cause=timeout; nrc=""; frc=""; only=""
  else
    nrc="$(cat "$OUT/logs/$s.nosb.rc" 2>/dev/null || echo "")"; frc="$(cat "$OUT/logs/$s.full.rc" 2>/dev/null || echo "")"
    only=""
    if [[ "$nrc" == 0 ]]; then status=fail-sandbox; cause="$(classify "$OUT/logs/$s.sb.log" "$s")"
    elif [[ "$nrc" != "" && "$frc" == 0 ]]; then status=fail-sandbox; cause=env-var-scrubbed
    else
      status=fail-preexisting; cause="$(classify "$OUT/logs/$s.nosb.log" "$s")"
      if [[ "$s" == testr ]]; then
        only="$(comm -23 <(failed_tests "$OUT/logs/$s.sb.log") <(failed_tests "$OUT/logs/$s.nosb.log") | head -40)"
        [[ -n "$only" ]] && status=fail-partial-sandbox && cause="$(classify "$OUT/logs/$s.sb.log" "$s")"
      fi
    fi
    [[ -z "$nrc" ]] && status=fail-unverified
  fi
  tail_txt=""; [[ -f "$OUT/logs/$s.sb.log" && "$status" != pass ]] && tail_txt="$(tail -n 60 "$OUT/logs/$s.sb.log" | tail -c 5000)"
  jq --arg step "$s" --arg status "$status" --arg cause "$cause" --arg rc "$rc" --arg nrc "$nrc" --arg frc "$frc" \
     --arg secs "$(cat "$OUT/logs/$s.sb.secs" 2>/dev/null || echo 0)" --arg only "$only" --arg tail "$tail_txt" \
     '. + [{step:$step,status:$status,cause:$cause,rc_sandbox:$rc,rc_nosandbox:$nrc,rc_full:$frc,secs_sandbox:($secs|tonumber),sandbox_only_failed_tests:($only|split("\n")|map(select(length>0))),tail:$tail}]' \
     "$OUT/steps.json" >"$OUT/steps.tmp" && mv "$OUT/steps.tmp" "$OUT/steps.json"
done
online_tail=""; [[ "$ONLINE_RC" != 0 ]] && online_tail="$(tail -n 60 "$OUT/logs/online.log" | tail -c 5000)"
jq -n --arg name "$NAME" --arg repo "$REPO" --arg tag "$TAG" --arg note "$TAGNOTE" --arg commit "$COMMIT" \
  --argjson lock "$LOCK_COMMITTED" --arg lib "$LIB" --arg toolchain "$TOOLCHAIN" --argjson orc "$ONLINE_RC" \
  --argjson osecs "$ONLINE_SECS" --arg otail "$online_tail" --slurpfile steps "$OUT/steps.json" \
  '{name:$name,repo:$repo,tag:$tag,note:$note,commit:$commit,lock_committed:$lock,lib:($lib=="true"),toolchain:$toolchain,online_rc:$orc,online_secs:$osecs,online_tail:$otail,steps:$steps[0]}' \
  >"$OUT/result.json"
cat "$OUT/result.json" | jq -c 'del(.steps[].tail)'
gzip -qf "$OUT"/logs/*.log
exit 0
