#!/usr/bin/env bash
# Installs and arms the first-boot owner-provisioning flow inside the target
# rootfs. Run once, at build time, inside the chroot (build/build.sh calls
# this) — never at runtime.
#
# "Arming" means: install the service + driver script, enable the unit, and
# create the pending sentinel that gates it. This mirrors exactly how
# upstream Omarchy arms its own equivalent (deferred-provisioning ISO installs
# / omarchy-system-factory-reset write the same sentinel file for the same
# reason — see docs/install-audit.md).
set -euo pipefail

WSL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:?usage: arm-first-boot.sh <target-rootfs-path>}"

install -Dm755 "$WSL_DIR/omarchy-wsl-provision-owner" \
  "$TARGET/usr/local/bin/omarchy-wsl-provision-owner"

install -Dm644 "$WSL_DIR/omarchy-wsl-provision-owner.service" \
  "$TARGET/etc/systemd/system/omarchy-wsl-provision-owner.service"

install -Dm644 "$WSL_DIR/../patches/setup-form.sh" \
  "$TARGET/usr/share/omarchy-wsl/setup-form.sh"

mkdir -p "$TARGET/var/lib/omarchy/provisioning"
: > "$TARGET/var/lib/omarchy/provisioning/pending"

# systemctl enable, without a running systemd (build time, inside a chroot):
# hand-create the symlink enable normally would, same mechanics `systemctl
# enable` uses under the hood.
mkdir -p "$TARGET/etc/systemd/system/multi-user.target.wants"
ln -sf ../omarchy-wsl-provision-owner.service \
  "$TARGET/etc/systemd/system/multi-user.target.wants/omarchy-wsl-provision-owner.service"

echo "Armed first-boot provisioning in $TARGET"
