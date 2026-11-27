#!/usr/bin/env bash
# Run offline_phase.sh under a chosen network-isolation mechanism and report
# whether it (1) blocked the escape probe and (2) still let the build succeed.
# Usage: wrap.sh <mechanism>
# Env in: HOME CARGO_HOME RUSTUP_HOME PATH WORKDIR   (set by the workflow step)
set -uo pipefail

MECH="${1:?mechanism}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE="$HERE/offline_phase.sh"
: "${WORKDIR:?}" "${CARGO_HOME:?}" "${RUSTUP_HOME:?}"

# A world-readable env file so a dropped-privilege child can reconstruct env.
ENVF="$(mktemp /tmp/probe-env.XXXXXX.sh)"
chmod 0644 "$ENVF"
cat >"$ENVF" <<EOF
export HOME='$HOME'
export CARGO_HOME='$CARGO_HOME'
export RUSTUP_HOME='$RUSTUP_HOME'
export PATH='$PATH'
export WORKDIR='$WORKDIR'
EOF

UID_N="$(id -u)"; GID_N="$(id -g)"
printf '### mechanism=%s uid=%s\n' "$MECH" "$UID_N"

case "$MECH" in
  baseline)
    bash "$PHASE" ;;

  A-unshare-setpriv)
    # sudo to get CLONE_NEWNET, bring lo up, then drop fully back to the build
    # user with groups cleared (drops the docker group) and no-new-privs (kills
    # any sudo re-escalation from inside).
    sudo unshare -n bash -c '
      ip link set lo up
      exec setpriv --reuid '"$UID_N"' --regid '"$GID_N"' --clear-groups --no-new-privs \
        bash -c "source '"$ENVF"'; exec bash '"$PHASE"'"' ;;

  B-docker-rust)
    # Self-contained official toolchain image, no socket mounted, no network.
    # Host-fetched registry mounted read-only; a tmpfs CARGO_HOME over it holds
    # cargo's lock files. Runs as the build uid so target/ stays writable.
    IMG="${RUST_IMAGE:?set RUST_IMAGE}"
    docker run --rm --network none \
      --security-opt no-new-privileges \
      -u "$UID_N:$GID_N" \
      --tmpfs /cargo:exec \
      -v "$CARGO_HOME/registry":/cargo/registry:ro \
      -v "$WORKDIR":/work \
      -e HOME=/work -e CARGO_HOME=/cargo -e CARGO_TARGET_DIR=/work/target \
      -e WORKDIR=/work/rust-exp/sandbox \
      -w /work \
      "$IMG" bash /work/rust-exp/sandbox/offline_phase.sh ;;

  C-bwrap)
    # Unprivileged user namespace + net unshare. May fail if
    # kernel.apparmor_restrict_unprivileged_userns blocks unpriv userns.
    source "$ENVF"
    bwrap --unshare-net --dev-bind / / --die-with-parent \
      bash -c 'ip link set lo up 2>/dev/null; exec bash '"$PHASE" ;;

  C-bwrap-sudo)
    # Fallback when unprivileged userns is blocked: root creates the net ns and
    # raises lo, then setpriv drops back to the build user (groups cleared).
    sudo bwrap --unshare-net --dev-bind / / --die-with-parent \
      bash -c 'ip link set lo up 2>/dev/null
        source '"$ENVF"'
        exec setpriv --reuid '"$UID_N"' --regid '"$GID_N"' --clear-groups --no-new-privs bash '"$PHASE" ;;

  D-nft-uid)
    # No namespace: a dedicated uid with an egress-drop rule (loopback allowed).
    # The uid is not in the docker group, so the socket path is closed too.
    sudo useradd -m builder 2>/dev/null || true
    BUID="$(id -u builder)"
    sudo nft -f - <<NFT
table inet probe {
  chain out {
    type filter hook output priority 0; policy accept;
    oif "lo" accept
    meta skuid $BUID ip daddr != 127.0.0.0/8 drop
    meta skuid $BUID ip6 daddr != ::1 drop
  }
}
NFT
    # Give builder a writable CARGO_HOME (hardlink the fetched registry) + target.
    sudo mkdir -p /home/builder/.cargo
    sudo cp -al "$CARGO_HOME/registry" /home/builder/.cargo/registry 2>/dev/null \
      || sudo cp -a "$CARGO_HOME/registry" /home/builder/.cargo/registry
    sudo chown -R builder:builder /home/builder/.cargo
    sudo chmod -R a+rwX "$WORKDIR"
    sudo -u builder env \
      HOME=/home/builder CARGO_HOME=/home/builder/.cargo \
      RUSTUP_HOME="$RUSTUP_HOME" PATH="$PATH" WORKDIR="$WORKDIR" \
      bash "$PHASE"
    r=$?
    sudo nft delete table inet probe 2>/dev/null || true
    exit "$r" ;;

  D-systemd-run)
    # Transient unit: private net + no-new-privs + no supplementary groups.
    sudo systemd-run --pipe --wait --collect \
      -p PrivateNetwork=yes -p NoNewPrivileges=yes \
      -p User="$(id -un)" -p SupplementaryGroups= \
      -p "WorkingDirectory=$WORKDIR" \
      --setenv=HOME="$HOME" --setenv=CARGO_HOME="$CARGO_HOME" \
      --setenv=RUSTUP_HOME="$RUSTUP_HOME" --setenv=PATH="$PATH" \
      --setenv=WORKDIR="$WORKDIR" \
      bash "$PHASE" ;;

  *) printf 'unknown mechanism %s\n' "$MECH"; exit 2 ;;
esac
