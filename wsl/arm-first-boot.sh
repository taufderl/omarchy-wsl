#!/usr/bin/env bash
# Arms first-boot owner provisioning inside the target rootfs. Run once, at
# build time, inside the chroot (build/_inside-container.sh calls this).
#
# Unlike v1, this does not install any provisioning logic of our own — the
# real /usr/bin/omarchy-provision-owner (shipped by the real `omarchy`
# package) is used completely unmodified. "Arming" here means only: create
# the pending sentinel it already expects (the same gating mechanism
# upstream's own deferred-provisioning/factory-reset paths use — see
# docs/install-audit.md), and hook root's shell startup to invoke it.
#
# Why a shell-startup hook and not the real omarchy-provision-owner.service:
# tried that first, on real hardware. journalctl showed the service actually
# start, then get killed by its own TTYVHangup=yes within ~6 seconds — that
# flag force-hangs-up /dev/tty1 to reclaim it from a previous session (a
# getty, or SDDM waiting to start); under WSL there is no previous session,
# so it just hung up its own just-started process. This is a WSL-vs-bare-metal
# environment difference, not a decision to not use the real binary — the
# binary itself is untouched, only how/when it's invoked differs. Full
# incident write-up in docs/install-audit.md.
set -euo pipefail

WSL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:?usage: arm-first-boot.sh <target-rootfs-path>}"

install -Dm755 "$WSL_DIR/apply-default-user.sh" \
  "$TARGET/usr/local/bin/omarchy-wsl-apply-default-user"

mkdir -p "$TARGET/var/lib/omarchy/provisioning"
: > "$TARGET/var/lib/omarchy/provisioning/pending"
: > "$TARGET/var/lib/omarchy/provisioning/.lock"

# Interactive-only (never fires for `wsl -d x -- some-script.sh` or a
# non-interactive Remote-WSL connection) and flock-guarded (two `wsl -d`
# windows opened at once run this exactly once; the second just proceeds to
# a normal prompt). omarchy-provision-owner itself re-checks the pending
# sentinel on entry (it's written to do that regardless of caller, for its
# own deferred-provisioning/factory-reset use cases), so this is safe to
# call unconditionally once the interactive+lock guard passes.
HOOK='
# omarchy-wsl: first-boot owner provisioning (see wsl/arm-first-boot.sh)
if [[ $- == *i* ]] && [[ -f /var/lib/omarchy/provisioning/pending ]]; then
  flock -n /var/lib/omarchy/provisioning/.lock /usr/bin/omarchy-provision-owner
  /usr/local/bin/omarchy-wsl-apply-default-user
fi
'
mkdir -p "$TARGET/root"
printf '%s\n' "$HOOK" >> "$TARGET/root/.bashrc"
# root has no .bash_profile in a fresh pacstrap, so a login shell (the case
# `wsl -d <distro>` most likely hits) would otherwise skip .bashrc entirely.
cat > "$TARGET/root/.bash_profile" <<'EOF'
[[ -f ~/.bashrc ]] && source ~/.bashrc
EOF

echo "Armed first-boot provisioning (real omarchy-provision-owner) in $TARGET"
