#!/usr/bin/env bash
# Run on ubuntu: scan scenarios with syft exactly as wrangle's adapter does.
# env: SYFT_RUN = command prefix producing the adapter invocation: we use `adapter` mode.
set -u
ROOT="$PWD/scan"; rm -rf "$ROOT"; mkdir -p "$ROOT"
A="$PWD/aud-out"   # contains auditable/ plain/ (+ macos/ windows/ if present)
summ() { # sbom.json name
  jq -r --arg n "$2" '
    [.packages[]? | select(.name!="" )] as $p
    | "RESULT \($n): packages=\($p|length)"' "$1"
}
run() { # name dir
  local name="$1" dir="$2" out="$ROOT/$1"; mkdir -p "$out"
  bash "$PWD/rust-exp/bin/syft_adapter.sh" "$dir" "$out" >"$out/log" 2>&1; echo "RESULT $name adapter_rc=$?"
  summ "$out/sbom.spdx.json" "$name"
  jq -r '[.packages[]|.name+"@"+(.versionInfo//"")]|sort|join(" ")' "$out/sbom.spdx.json" | fold -w 200 | sed "s/^/  PKGS[$name] /"
  # native syft json for foundBy
  syft "dir:$dir" -o syft-json 2>/dev/null > "$out/native.json"
  jq -r '[.artifacts[]|.foundBy]|group_by(.)|map("\(.[0])=\(length)")|join(", ")' "$out/native.json" | sed "s/^/  FOUNDBY[$name] /"
  jq -r '[.artifacts[]|select(.type=="rust-crate")|.name]|sort|join(" ")' "$out/native.json" | fold -w 200 | sed "s/^/  CRATES[$name] /"
}
mkdir -p "$ROOT/in-aud" "$ROOT/in-plain" "$ROOT/in-aud-tgz" "$ROOT/in-both-tgz" "$ROOT/in-src"
cp "$A/auditable/audprobe" "$ROOT/in-aud/"
cp "$A/plain/audprobe" "$ROOT/in-plain/"
tar -C "$A/auditable" -czf "$ROOT/in-aud-tgz/audprobe-linux.tar.gz" audprobe
tar -C "$A/plain" -czf "$ROOT/in-both-tgz/audprobe-plain.tar.gz" audprobe
cp -r rust-exp/bin/aud/. "$ROOT/in-src/"
run i-auditable-bin   "$ROOT/in-aud"
run ii-plain-bin      "$ROOT/in-plain"
run iii-auditable-tgz "$ROOT/in-aud-tgz"
run iii-plain-tgz     "$ROOT/in-both-tgz"
run iv-source-tree    "$ROOT/in-src"
for f in macos windows; do
  if [ -d "$A/$f" ]; then mkdir -p "$ROOT/in-$f"; cp "$A/$f"/audprobe* "$ROOT/in-$f/"; run d-$f-auditable "$ROOT/in-$f"; fi
done
# sanity: binary's own audit section
printf 'LDSECTION: '; objdump -h "$A/auditable/audprobe" 2>/dev/null | grep -c '.dep-v0' || true
