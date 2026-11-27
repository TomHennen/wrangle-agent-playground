#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; source "$HERE/q2common.sh"
setup_src "$1" "$2"; cd "$ROOT"
cargo -V; echo "git-tracked Cargo.lock: '$(git ls-files Cargo.lock)'  ignored?: $(git check-ignore -v Cargo.lock || echo no)"
rm -f Cargo.lock
echo "######## 2a: generate-lockfile variants"
gl() { # label env-value
  rm -f Cargo.lock
  if [[ -n "$2" ]]; then CARGO_REGISTRY_GLOBAL_MIN_PUBLISH_AGE="$2" cargo generate-lockfile 2>&1 | tail -4; rc=${PIPESTATUS[0]}; else cargo generate-lockfile 2>&1 | tail -4; rc=${PIPESTATUS[0]}; fi
  echo "[$1] rc=$rc"; [[ -f Cargo.lock ]] && cp Cargo.lock "$W/lock.$1" && grep -c '^name' "$W/lock.$1"
}
gl none ""
# dates of resolved packages
echo "--- publish dates of resolved registry packages (unrestricted lock)"
awk '/^name/{gsub(/"/,"",$3);n=$3} /^version/{gsub(/"/,"",$3);v=$3} /^source = "registry/{print n, v}' "$W/lock.none" > "$W/pk.txt"
: > "$W/dates.txt"
while read -r n v; do
  d=$(curl -sS -A "wrangle-exp (github actions)" "https://crates.io/api/v1/crates/$n/$v" | jq -r .version.created_at); echo "$d $n $v" >> "$W/dates.txt"; sleep 1.1
done < "$W/pk.txt"
sort "$W/dates.txt" | tail -5
YOUNG=$(sort "$W/dates.txt" | tail -1); echo "youngest: $YOUNG"
YS=$(date -d "$(echo "$YOUNG" | cut -d' ' -f1)" +%s); AGE_H=$(( ( $(date +%s) - YS ) / 3600 ))
echo "youngest age hours: $AGE_H"
for age in "7 days" "400 days" "$((AGE_H+1)) hours" "$((AGE_H-1)) hours" "100000 days"; do
  lbl=$(echo "$age" | tr -d ' ')
  gl "$lbl" "$age"
  [[ -f "$W/lock.$lbl" ]] && { echo "diff none vs $lbl:"; diff "$W/lock.none" "$W/lock.$lbl" | head -12; }
done
echo "--- config key spelling check: CARGO_REGISTRY_GLOBAL_MIN_PUBLISH_AGE vs bogus var"
gl bogus "" 
CARGO_REGISTRY_GLOBAL_MIN_PUBLISH_AGE="banana" cargo generate-lockfile 2>&1 | tail -3
cargo --config 'registry.global-min-publish-age="400 days"' generate-lockfile 2>&1 | tail -3; echo "config-flag rc=$? ; lock same as env 400d?"; cmp Cargo.lock "$W/lock.400days" && echo SAME-AS-ENV
echo "######## 2b: dirty-tree check with untracked generated lock (7 days)"
gl 7days "7 days"; cp "$W/lock.7days" Cargo.lock
git status --short | head; echo "status of lock: $(git status --short Cargo.lock)"
for mode in "--no-verify" ""; do
  echo "--- cargo package --locked $mode (no --allow-dirty)"
  rm -rf target/package; cargo package --locked $mode 2>&1 | tail -6; echo "rc=${PIPESTATUS[0]}"
  C=$(ls target/package/*.crate 2>/dev/null | head -1)
  [[ -n "$C" ]] && { sha256sum "$C"; [[ -z "$mode" ]] && cp "$C" "$OUT/verify.crate" && sha256sum "$C" > "$OUT/verify.sha"; }
done
rm -rf target/package; cargo package --locked --no-verify 2>&1 | tail -3
C=$(ls target/package/*.crate | head -1); cp "$C" "$OUT/A.crate"; sha256sum "$C" | tee "$OUT/A.sha"
rm -rf "$W/xa"; mkdir "$W/xa"; tar xzf "$C" -C "$W/xa"; cmp "$W/xa"/*/Cargo.lock Cargo.lock && echo "RESULT embedded Cargo.lock IDENTICAL to generated"
cat "$W"/xa/*/.cargo_vcs_info.json; echo
cp Cargo.lock "$OUT/generated.Cargo.lock"
