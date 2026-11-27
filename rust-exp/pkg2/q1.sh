#!/usr/bin/env bash
# usage: q1.sh <repo|fixture> <member>   (run from workspace root; env: CRATESIO_NAME)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$1"; M="$2"; W="$RUNNER_TEMP"; OUT="$GITHUB_WORKSPACE/out"; mkdir -p "$OUT"
export RUSTUP_TOOLCHAIN=stable
cargo -V; rustc -V
ncrates() { find "$1/registry/cache" -name '*.crate' 2>/dev/null | wc -l; }
if [[ "$SRC" == fixture ]]; then
  ROOT="$GITHUB_WORKSPACE/rust-exp/pkg2/fixture"; PKG=(); NAME=wr-det-exp
else
  VER=$(curl -sS -A "wrangle-exp (github actions)" "https://crates.io/api/v1/crates/$M" | jq -r .crate.max_stable_version)
  TAG=$(git ls-remote --tags "https://github.com/$SRC" | awk '{print $2}' | sed 's#refs/tags/##' | grep -v '\^{}' | grep -E "(^|[-/v])${VER//./\\.}\$" | head -3 | tr '\n' ' ')
  echo "crates.io max_stable=$VER candidate tags: $TAG"
  T=$(echo "$TAG" | awk '{for(i=1;i<=NF;i++) if($i ~ /^'"$M"'-/ ) {print $i; exit}} END{}')
  [[ -n "$T" ]] || T=$(echo "$TAG" | tr ' ' '\n' | grep -E "^v?${VER//./\\.}\$" | head -1)
  [[ -n "$T" ]] || T=$(echo "$TAG" | awk '{print $1}')
  echo "using tag $T"
  git clone --depth 1 -b "$T" "https://github.com/$SRC" "$W/repo" 2>&1 | tail -1
  ROOT="$W/repo"; PKG=(-p "$M"); NAME="$M"
  echo "tag=$T commit=$(git -C "$ROOT" rev-parse HEAD)"
fi
cd "$ROOT"
echo "toolchain files: $(ls rust-toolchain* 2>/dev/null)"; echo "committed Cargo.lock: $(git ls-files Cargo.lock)"
echo "######## BASELINE: plain verifying 'cargo package --locked'"
export CARGO_HOME="$W/ch-base"; mkdir -p "$CARGO_HOME"
cargo package --locked "${PKG[@]}" 2>&1 | tail -5; echo "rc=${PIPESTATUS[0]}"
CR=$(ls target/package/*.crate 2>/dev/null | head -1); echo "crate: $CR"
echo "Cargo.lock after baseline: $(ls Cargo.lock 2>&1) ; git-ignored: $(git check-ignore Cargo.lock || echo no)"
[[ -n "$CR" ]] && { sha256sum "$CR" | tee "$OUT/base.sha"; cp "$CR" "$OUT/base.crate"; }
rm -rf target/package
echo "######## STEP 1: cargo package --no-verify --locked (empty CARGO_HOME, network on)"
export CARGO_HOME="$W/ch-s1"; mkdir -p "$CARGO_HOME"
echo "before: crates in cache=$(ncrates "$CARGO_HOME")"
cargo package --no-verify --locked -v "${PKG[@]}" 2>&1 | tee "$OUT/step1.log" | tail -25; echo "rc=${PIPESTATUS[0]}"
echo "after: crates in cache=$(ncrates "$CARGO_HOME") ; index: $(ls "$CARGO_HOME/registry/index" 2>/dev/null | tr '\n' ' ')"
echo "Compiling/Running lines: $(grep -cE '^\s*(Compiling|Running|Fresh)' "$OUT/step1.log"); Downloading lines: $(grep -c Downloading "$OUT/step1.log")"
echo "target dirs after step1: $(ls target)"
CR=$(ls target/package/*.crate | head -1); sha256sum "$CR" | tee "$OUT/step1.sha"; cp "$CR" "$OUT/step1.crate"
if [[ -f "$OUT/base.sha" ]]; then [[ $(cut -d' ' -f1 "$OUT/base.sha") == $(cut -d' ' -f1 "$OUT/step1.sha") ]] && echo "RESULT step1==baseline: SAME" || echo "RESULT step1==baseline: DIFFERENT"; fi
echo "######## STEP 2: extract + cargo fetch --locked (network on, fresh CARGO_HOME)"
EX="$W/ex"; rm -rf "$EX"; mkdir -p "$EX"; tar xzf "$CR" -C "$EX"; D=$(ls -d "$EX"/*/); cd "$D"; pwd
ls; echo "embedded lock: $(wc -l < Cargo.lock) lines; toolchain file: $(ls rust-toolchain* 2>/dev/null)"
export CARGO_HOME="$W/ch-s2"; mkdir -p "$CARGO_HOME"
cargo fetch --locked 2>&1 | tail -5; echo "rc=${PIPESTATUS[0]}"
echo "after fetch: crates in cache=$(ncrates "$CARGO_HOME")"
cp -a "$CARGO_HOME" "$W/ch-s2-snapshot"
echo "######## STEP 3: sandbox: cargo build --offline --locked"
export CARGO_TARGET_DIR="$W/tgt3"
"$HERE/sandbox.sh" "$D" cargo build --offline --locked 2>&1 | tail -15; echo "rc=${PIPESTATUS[0]}"
echo "crates in cache after step3: $(ncrates "$CARGO_HOME") (fetched: $(ncrates "$W/ch-s2-snapshot"))"
diff <(cd "$W/ch-s2-snapshot/registry" && find . -type f | sort) <(cd "$CARGO_HOME/registry" && find . -type f | sort) | head -10 || true
