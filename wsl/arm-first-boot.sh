#!/usr/bin/env bash
# Arms first-boot owner provisioning inside the target rootfs. Run once, at
# build time, inside the chroot (build/_inside-container.sh calls this).
#
# This does not install any provisioning logic of our own — the real
# /usr/bin/omarchy-provision-owner (shipped by the real `omarchy` package)
# is used completely unmodified. "Arming" here means: create the pending
# sentinel it already expects (the same gating mechanism upstream's own
# deferred-provisioning/factory-reset paths use — see docs/install-audit.md),
# and hook it up to WSL's own first-run mechanism.
#
# History (full account in docs/install-audit.md): this used to be a hook in
# root's .bashrc, first guarded on `[[ $- == *i* ]]`, then on
# `-t 0`/`-t 1`, then moved to `PROMPT_COMMAND` — three real, repeatable
# fixes on real hardware, and *still* not reliable: a genuinely fresh
# `wsl --import` kept showing the real splash rendering on a pty that wasn't
# the one the session actually attached to. All three attempts were shell
# rc-file tricks racing against however WSL's own launcher sets up a
# session's console — a race we can't fully control from inside the guest.
#
# The actual fix: WSL has an official, built-in first-run mechanism for
# exactly this (`/etc/wsl-distribution.conf`'s `[oobe] command=`, supported
# since WSL 2.4.4 — https://learn.microsoft.com/en-us/windows/wsl/build-custom-distro).
# It's the same mechanism Ubuntu/Debian's WSL distros use for their "create
# a UNIX user" prompt: WSL's own launcher runs the command the first time a
# shell is opened, before any shell/rc-file layer exists to race against.
# See wsl-distribution.conf and oobe.sh.
set -euo pipefail

WSL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:?usage: arm-first-boot.sh <target-rootfs-path>}"

install -Dm755 "$WSL_DIR/apply-default-user.sh" \
  "$TARGET/usr/local/bin/omarchy-wsl-apply-default-user"
install -Dm755 "$WSL_DIR/oobe.sh" \
  "$TARGET/usr/local/bin/omarchy-wsl-oobe"
install -Dm644 "$WSL_DIR/wsl-distribution.conf" \
  "$TARGET/etc/wsl-distribution.conf"

mkdir -p "$TARGET/var/lib/omarchy/provisioning"
: > "$TARGET/var/lib/omarchy/provisioning/pending"
: > "$TARGET/var/lib/omarchy/provisioning/.lock"

echo "Armed first-boot provisioning (real omarchy-provision-owner, via WSL's own oobe.command) in $TARGET"
