#!/usr/bin/env bash
# Verifies the target rootfs's package/service state matches what this
# project actually intends — NOT "these packages are absent" the way v1's
# version of this script asserted. Under the current architecture (see
# PLAN.md) sddm/limine/hyprland/NetworkManager etc. are *expected* to be
# installed, as real dependencies of the real `omarchy` package — the
# distinction that matters is installed-but-inert vs actively enabled.
#
# Run at the end of build/_inside-container.sh (build-time check) and again
# by test/smoke-test.sh (post-import check) — same script, two callers.
set -euo pipefail

TARGET="${1:?usage: verify-no-boot-artifacts.sh <target-rootfs-path>}"
fail=0

check_absent_pkg() {
  local pkg="$1"
  if arch-chroot "$TARGET" pacman -Qq "$pkg" &>/dev/null; then
    echo "FAIL: package '$pkg' is installed but should be structurally impossible under WSL2" >&2
    fail=1
  fi
}

check_present_pkg() {
  local pkg="$1"
  if ! arch-chroot "$TARGET" pacman -Qq "$pkg" &>/dev/null; then
    echo "FAIL: package '$pkg' is missing — expected as a real omarchy dependency" >&2
    fail=1
  fi
}

check_absent_path() {
  local path="$1"
  if [[ -e "$TARGET$path" ]]; then
    echo "FAIL: '$path' exists but shouldn't (kernel/initramfs artifact)" >&2
    fail=1
  fi
}

check_not_enabled() {
  local unit="$1"
  if [[ -e "$TARGET/etc/systemd/system/multi-user.target.wants/$unit" ]] || \
     [[ -e "$TARGET/etc/systemd/system/graphical.target.wants/$unit" ]] || \
     [[ -e "$TARGET/etc/systemd/system/sockets.target.wants/$unit" ]]; then
    echo "FAIL: unit '$unit' is enabled but this project deliberately disables it" >&2
    fail=1
  fi
}

# --- The one real structural exclusion: kernel/initramfs/DKMS. ---
# mkinitcpio is NOT in this list on purpose: it's a real, unavoidable
# dependency of the real omarchy package (via limine-mkinitcpio-hook) and
# installing it is harmless — its hooks only ever fire on a linux/kernel
# transaction, which never happens here since `linux` itself stays excluded.
# See docs/install-audit.md.
for pkg in linux linux-firmware linux-headers; do
  check_absent_pkg "$pkg"
done
for path in /boot/vmlinuz-linux /usr/lib/modules; do
  check_absent_path "$path"
done

# --- These are EXPECTED to be present — real omarchy dependencies, just ---
# --- not enabled/active. A regression here usually means the resolved   ---
# --- package manifest broke, not that exclusion is "working better".    ---
for pkg in omarchy sddm hyprland limine snapper; do
  check_present_pkg "$pkg"
done

# --- Present-but-must-not-be-enabled (the short, explicit override from ---
# --- build/_inside-container.sh — see PLAN.md for the reasoning).       ---
for unit in NetworkManager.service sddm.service cups.service cups-browsed.service avahi-daemon.service; do
  check_not_enabled "$unit"
done

if (( fail )); then
  echo "verify-no-boot-artifacts: FAILED" >&2
  exit 1
fi

echo "verify-no-boot-artifacts: OK"
