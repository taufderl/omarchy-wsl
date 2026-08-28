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
#
# Why PROMPT_COMMAND and not inline in .bashrc: a second real-hardware round
# confirmed the real binary and the environment (TERM, terminal size) were
# both fine — running `omarchy-provision-owner` manually, by hand, after
# `wsl -d omarchy` had already dropped to a shell, worked perfectly and
# completed the entire real flow (account creation, all the real per-user
# install/user/*.sh setup). But invoked directly inline during .bashrc
# sourcing, it produced zero visible output and left the shell looking
# untouched every time. The most likely explanation: bash has not yet fully
# taken control of the terminal (job control / foreground process group)
# at that exact point during interactive shell initialization, which breaks
# a raw-terminal, animation-driving TUI like this one even though a plain
# shell works fine at the same point. PROMPT_COMMAND runs right before the
# first prompt is displayed, once the shell is fully up — matching the
# working manual-invocation case — and only exists in interactive shells to
# begin with, so it doubles as the interactivity guard v1/v2 of this hook
# each got wrong in a different way (see docs/install-audit.md for both).
set -euo pipefail

WSL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:?usage: arm-first-boot.sh <target-rootfs-path>}"

install -Dm755 "$WSL_DIR/apply-default-user.sh" \
  "$TARGET/usr/local/bin/omarchy-wsl-apply-default-user"

mkdir -p "$TARGET/var/lib/omarchy/provisioning"
: > "$TARGET/var/lib/omarchy/provisioning/pending"
: > "$TARGET/var/lib/omarchy/provisioning/.lock"

# flock-guarded: two `wsl -d` windows opened at once run this exactly once;
# the second just proceeds to a normal prompt. omarchy-provision-owner
# itself re-checks the pending sentinel on entry too (it's written to do
# that regardless of caller, for its own deferred-provisioning/factory-reset
# use cases), so this is safe even if PROMPT_COMMAND somehow fired twice.
# The function removes itself from PROMPT_COMMAND after running once, so a
# cancelled/failed attempt doesn't retry before every single subsequent
# prompt in the same session — just once per session, same as before.
HOOK='
# omarchy-wsl: first-boot owner provisioning (see wsl/arm-first-boot.sh)
omarchy_wsl_first_boot_check() {
  PROMPT_COMMAND="${PROMPT_COMMAND//omarchy_wsl_first_boot_check;/}"
  if [[ -f /var/lib/omarchy/provisioning/pending ]]; then
    flock -n /var/lib/omarchy/provisioning/.lock /usr/bin/omarchy-provision-owner
    /usr/local/bin/omarchy-wsl-apply-default-user
  fi
}
PROMPT_COMMAND="omarchy_wsl_first_boot_check;${PROMPT_COMMAND}"
'
mkdir -p "$TARGET/root"
printf '%s\n' "$HOOK" >> "$TARGET/root/.bashrc"
# root has no .bash_profile in a fresh pacstrap, so a login shell (the case
# `wsl -d <distro>` most likely hits) would otherwise skip .bashrc entirely.
cat > "$TARGET/root/.bash_profile" <<'EOF'
[[ -f ~/.bashrc ]] && source ~/.bashrc
EOF

echo "Armed first-boot provisioning (real omarchy-provision-owner) in $TARGET"
