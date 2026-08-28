#!/usr/bin/env bash
# Defense in depth: assert that no bootloader/initramfs/display-manager
# package or unit made it into the target rootfs, rather than assuming the
# package-manifest exclusions in packages/generate-manifest.sh were enough.
# Run at the end of build/build.sh (build-time check) and again by
# test/smoke-test.sh (post-import check) — same script, two callers.
set -euo pipefail

TARGET="${1:?usage: verify-no-boot-artifacts.sh <target-rootfs-or-/ inside the running image>}"
fail=0

check_absent_pkg() {
  local pkg="$1"
  if arch-chroot "$TARGET" pacman -Qq "$pkg" &>/dev/null; then
    echo "FAIL: package '$pkg' is installed but should never be in a WSL image" >&2
    fail=1
  fi
}

check_absent_path() {
  local path="$1"
  if [[ -e "$TARGET$path" ]]; then
    echo "FAIL: '$path' exists but shouldn't (bootloader/initramfs/splash artifact)" >&2
    fail=1
  fi
}

check_absent_enabled_unit() {
  local unit="$1"
  if [[ -e "$TARGET/etc/systemd/system/multi-user.target.wants/$unit" ]] || \
     [[ -e "$TARGET/etc/systemd/system/graphical.target.wants/$unit" ]]; then
    echo "FAIL: unit '$unit' is enabled but shouldn't be" >&2
    fail=1
  fi
}

for pkg in linux linux-firmware mkinitcpio limine limine-mkinitcpio-hook \
           limine-snapper-sync sddm plymouth networkmanager; do
  check_absent_pkg "$pkg"
done

for path in /boot/limine.conf /boot/vmlinuz-linux /usr/lib/modules; do
  check_absent_path "$path"
done

for unit in sddm.service plymouth-quit.service NetworkManager.service; do
  check_absent_enabled_unit "$unit"
done

if (( fail )); then
  echo "verify-no-boot-artifacts: FAILED" >&2
  exit 1
fi

echo "verify-no-boot-artifacts: OK — no bare-metal-only artifacts found"
