#!/usr/bin/env bash
# Installs and arms the first-boot owner-provisioning flow inside the target
# rootfs. Run once, at build time, inside the chroot (build/build.sh calls
# this) — never at runtime.
#
# "Arming" means: install the driver script, create the pending sentinel that
# gates it, and hook root's shell startup so the very first interactive
# `wsl -d <distro>` session runs it. This mirrors upstream Omarchy's own
# gating pattern (deferred-provisioning ISO installs / omarchy-system-factory-reset
# write the same sentinel file for the same reason — see docs/install-audit.md)
# but NOT its trigger mechanism.
#
# History: the first real `wsl --import` + boot test used a systemd service
# bound to TTYPath=/dev/tty1 with TTYReset=yes/TTYVHangup=yes (copied from
# upstream's real unit, vendored at patches/omarchy-provision-owner.service.upstream).
# It failed outright — journalctl showed the process killed by SIGHUP within
# ~6 seconds of starting. TTYVHangup=yes forces a vhangup(2) on the tty to
# reclaim it from a previous session (a getty, or SDDM); on bare metal there
# is one, under WSL there isn't, so it just hung up its own just-started
# process. Even fixed, there was no guarantee WSL's actual interactive
# session is what's attached to /dev/tty1 in the first place — WSL's console
# attachment isn't the classic VT/getty model that unit was written for.
# Rather than guess further at systemd/tty semantics this project has no way
# to test against upstream WSL source, this runs synchronously from root's
# own shell startup instead: whatever terminal `wsl -d <distro>` actually
# attaches you to, that's the shell whose .bashrc/.bash_profile runs.
set -euo pipefail

WSL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:?usage: arm-first-boot.sh <target-rootfs-path>}"

install -Dm755 "$WSL_DIR/omarchy-wsl-provision-owner" \
  "$TARGET/usr/local/bin/omarchy-wsl-provision-owner"

install -Dm644 "$WSL_DIR/../patches/setup-form.sh" \
  "$TARGET/usr/share/omarchy-wsl/setup-form.sh"

mkdir -p "$TARGET/var/lib/omarchy/provisioning"
: > "$TARGET/var/lib/omarchy/provisioning/pending"
: > "$TARGET/var/lib/omarchy/provisioning/.lock"

# The hook itself: guarded on (a) being an interactive shell — so this never
# fires for non-interactive invocations like `wsl -d x -- some-script.sh` or
# a VS Code Remote-WSL connection — and (b) the pending sentinel still being
# there. `flock -n` on a dedicated lock file (not the sentinel itself, so a
# concurrent shell can still see "pending" while another is actively running
# it) means opening two `wsl -d <distro>` windows at once runs this exactly
# once; the second window's shell just skips it and proceeds straight to a
# normal prompt.
HOOK='
# omarchy-wsl: first-boot owner provisioning (see wsl/arm-first-boot.sh)
if [[ $- == *i* ]] && [[ -f /var/lib/omarchy/provisioning/pending ]]; then
  flock -n /var/lib/omarchy/provisioning/.lock /usr/local/bin/omarchy-wsl-provision-owner
fi
'
mkdir -p "$TARGET/root"
printf '%s\n' "$HOOK" >> "$TARGET/root/.bashrc"
# root has no .bash_profile in a fresh pacstrap, so a login shell (the case
# `wsl -d <distro>` most likely hits) would otherwise skip .bashrc entirely —
# this is the standard convention (many distros' skel does exactly this) for
# making login and non-login interactive shells behave the same.
cat > "$TARGET/root/.bash_profile" <<'EOF'
[[ -f ~/.bashrc ]] && source ~/.bashrc
EOF

echo "Armed first-boot provisioning in $TARGET"
