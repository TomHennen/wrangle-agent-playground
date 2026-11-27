# sourced: sets ROOT, NAME, PKG from $1 (nolock|owner/repo) $2 (crate name)
W="$RUNNER_TEMP"; OUT="$GITHUB_WORKSPACE/out"; mkdir -p "$OUT"
export RUSTUP_TOOLCHAIN=stable
setup_src() {
  if [[ "$1" == nolock ]]; then ROOT="$GITHUB_WORKSPACE/rust-exp/pkg2/nolock"; NAME=wr-pkg2-nolock
  else
    VER=$(curl -sS -A "wrangle-exp (github actions)" "https://crates.io/api/v1/crates/$2" | jq -r .crate.max_stable_version)
    T=$(git ls-remote --tags "https://github.com/$1" | awk '{print $2}' | sed 's#refs/tags/##' | grep -v '\^{}' | grep -E "(^|[-/v])${VER//./\\.}\$" | head -1)
    echo "crates.io max_stable=$VER tag=$T"
    git clone --depth 1 -b "$T" "https://github.com/$1" "$W/repo" 2>&1 | tail -1; ROOT="$W/repo"; NAME="$2"
  fi
}
