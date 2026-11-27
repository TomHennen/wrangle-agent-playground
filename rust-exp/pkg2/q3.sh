#!/usr/bin/env bash
# usage: q3.sh <toolchain>
set -uo pipefail
TC="$1"; OUT="$GITHUB_WORKSPACE/out"; mkdir -p "$OUT"
rustup toolchain install "$TC" --profile minimal 2>&1 | tail -3 || true
cd "$GITHUB_WORKSPACE/rust-exp/pkg2/fixture"
export RUSTUP_TOOLCHAIN="$TC"
echo "RUSTUP_TOOLCHAIN=$RUSTUP_TOOLCHAIN"; cargo -V; rustc -V
for mode in noverify verify; do
  rm -rf target/package; f=(); [[ $mode == noverify ]] && f=(--no-verify)
  cargo package --locked "${f[@]}" 2>&1 | tail -4; echo "rc=${PIPESTATUS[0]} mode=$mode"
  C=target/package/wr-det-exp-0.1.0.crate
  [[ -f $C ]] && { sha256sum $C | tee "$OUT/$mode.sha"; cp $C "$OUT/$mode.crate"; }
done
cp Cargo.lock "$OUT/repo.Cargo.lock"; git diff --stat -- Cargo.lock
echo "######## rust-toolchain.toml override (file says: $(grep channel rust-toolchain.toml))"
cp rust-toolchain.toml /tmp/rtt.bak
printf '[toolchain]\nchannel = "stable"\n' > rust-toolchain.toml
echo "with RUSTUP_TOOLCHAIN=$TC, file=stable: $(cargo -V) | $(rustc -V)"
(unset RUSTUP_TOOLCHAIN; echo "without env, file=stable: $(cargo -V) | $(rustc -V)")
cp /tmp/rtt.bak rust-toolchain.toml
