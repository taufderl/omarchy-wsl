#!/usr/bin/env bash
# Computes the v1 (CLI-only) omarchy-wsl package manifest from upstream
# Omarchy's own package lists, minus what genuinely doesn't apply to WSL2.
#
# Inputs (vendored verbatim from basecamp/omarchy@quattro, for provenance —
# see fetch-upstream.sh):
#   omarchy-base.packages   the ISO's core pacstrap list
#   omarchy-other.packages  hardware-conditional extras + base/base-devel,
#                           installed by the ISO builder's offline mirror step
#
# Output:
#   manifest.txt            final sorted package list to pacstrap
#   excluded-report.txt      every dropped package with its reason, for audit
#
# Every exclusion below is a *category* decision with a one-line reason, not a
# silent drop — see docs/install-audit.md for the fuller narrative and the
# specific evidence behind each category (upstream script contents, WSL2
# platform research, etc).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
export LC_ALL=C   # comm/sort must agree on ordering regardless of the invoking shell's locale

# Where to write manifest.txt/excluded-report.txt. Defaults to this directory
# (the normal case for local/dev use), but build/_inside-container.sh passes
# a writable scratch dir instead, since it mounts the repo read-only into the
# build container on purpose (the build has no business writing back into
# its own source tree).
OUT_DIR="${1:-.}"
mkdir -p "$OUT_DIR"

# ---------------------------------------------------------------------------
# Group 0: essential base-system packages that neither .packages file lists,
# because on bare metal they're installed by omarchy-iso's archinstall step
# (the disk/base-OS layer we deliberately don't reuse — see PLAN.md) rather
# than by these Omarchy-specific package lists. archinstall's base profile
# installs `sudo` and typically `openssh`, which install/config/*.sh (sudoers
# tuning, ssh-command-path.sh, ssh-keepalive.sh) and `etc/sudoers.d` (vendored
# in basecamp/omarchy's own etc/ skeleton) all assume are already present.
# The `base` package group itself does NOT include either — confirmed against
# Arch's own base group contents.
# ---------------------------------------------------------------------------
ESSENTIAL_BASE_NOT_IN_EITHER_LIST=(
  sudo             # wheel-group sudo access is core to how Omarchy expects the owner account to work
  openssh           # ssh client (git-over-ssh, scp) — sshd is NOT enabled by default, see wsl/enable-services.sh
  omarchy-keyring    # trusts the [omarchy] pacman repo's signing key; see packages/OMARCHY_KEYRING_PIN
                     # for how build.sh bootstraps trust in this package itself
)

# ---------------------------------------------------------------------------
# Group 1: kept from omarchy-other.packages.
# Almost everything in that file is hardware-conditional (dkms drivers, kernel
# variants, vendor firmware, bootloader) and excluded below. These few are the
# exception: genuine base-system/dev-tooling prerequisites, or the PipeWire
# PulseAudio-compat shim that WSLg's audio bridge speaks.
# ---------------------------------------------------------------------------
KEEP_FROM_OTHER=(
  base                # the Arch base group itself
  base-devel          # needed to build AUR packages via yay/makepkg
  autoconf-archive     # general build dependency, not hardware-specific
  pipewire            # audio server; wireplumber (already in base list) depends
                      # on it, so it would be pulled in transitively anyway —
                      # listed explicitly for clarity
  pipewire-pulse       # WSLg's audio bridge speaks the PulseAudio protocol;
                      # this is the compat shim that lets pipewire answer it
)

# ---------------------------------------------------------------------------
# Group 2: excluded — kernel, bootloader, and hardware-driver packages.
# None of this has any WSL2 equivalent: WSL2 boots a Microsoft-provided kernel
# directly, there is no bootloader stage, no initramfs is consumed, and none
# of the laptop/GPU-vendor hardware exists to drive.
# ---------------------------------------------------------------------------
EXCLUDE_KERNEL_BOOTLOADER_HARDWARE=(
  linux linux-firmware linux-headers linux-ptl linux-ptl-headers
  linux-t2 linux-t2-headers linux-firmware-marvell
  dkms asusctl broadcom-wl macbook12-spi-driver-dkms
  nvidia-580xx-dkms nvidia-dkms nvidia-open-dkms
  nvidia-580xx-utils nvidia-utils lib32-nvidia-580xx-utils lib32-nvidia-utils
  tuxedo-drivers-nocompatcheck-dkms yt6801-dkms
  limine limine-mkinitcpio-hook limine-snapper-sync
  btrfs-progs snapper
  sof-firmware apple-bcm-firmware apple-t2-audio-config t2fanrd
  intel-ipu7-camera intel-lpmd intel-media-driver
  libva-intel-driver libva-nvidia-driver libvpl vpl-gpu-rt
  vulkan-intel vulkan-radeon vulkan-asahi
  dell-xps-touchpad-haptics dell-xps13-sidecar-amps
  lsp-plugins-lv2 qmk-hid
  thermald zram-generator kernel-modules-hook
  yay-debug           # debug symbols for a kernel/hardware debugging workflow
  webp-pixbuf-loader   # GTK thumbnailer codec, only consumed by GUI file managers
                      # (nautilus) which are excluded in v1 too
)

# ---------------------------------------------------------------------------
# Group 3: excluded — GUI/Wayland desktop packages, deferred to the
# nested-Hyprland-under-WSLg roadmap item (see PLAN.md). v1 is CLI-only, so
# none of these have anything to attach to.
# ---------------------------------------------------------------------------
EXCLUDE_GUI_DESKTOP=(
  hyprland hyprland-guiutils hyprland-preview-share-picker hyprpicker hyprsunset
  quickshell uwsm sddm plymouth
  xdg-desktop-portal-gtk xdg-desktop-portal-hyprland xdg-terminal-exec
  wl-clipboard wtype grim slurp foot
  nautilus nautilus-python sushi gnome-disk-utility
  gvfs-mtp gvfs-nfs gvfs-smb gnome-keyring gnome-themes-extra
  imv evince obs-studio gpu-screen-recorder moonlight-qt
  pinta xournalpp kdenlive localsend obsidian libreoffice-fresh
  qt6-imageformats python-gobject chromium udiskie
  omacalc omawrite omacut     # Omarchy's bespoke Qt apps (calculator/writer/cut) — GUI
  aether                      # Omarchy's Hyprland/Quickshell theme-builder GUI
  tensaku                     # image annotator — GUI; unverified whether it has a
                               # usable CLI mode, see docs/install-audit.md open item
  woff2-font-awesome yaru-icon-theme ttf-ia-writer
  egl-wayland gst-plugin-pipewire gtk4-layer-shell libpulse qt6-wayland
  fcitx5-gtk fcitx5-qt         # GUI-toolkit input-method bindings; fcitx5 core kept
  ffmpegthumbnailer            # GTK/Nautilus thumbnailer, no use without a file manager
)

# ---------------------------------------------------------------------------
# Group 4: excluded — hardware/network daemons with no WSL2 equivalent, or
# that this project deliberately doesn't enable by default for security
# reasons (see PLAN.md "Security hardening"). Each is re-addable by a user who
# has a concrete reason to.
# ---------------------------------------------------------------------------
EXCLUDE_HARDWARE_NETWORK_DAEMONS=(
  bluez bluez-tools bluez-utils        # no Bluetooth hardware under WSL2
  brightnessctl ddcutil asdcontrol     # no display hardware to control
  bolt                                  # no Thunderbolt under WSL2
  wireless-regdb                       # no Wi-Fi radio to regulate
  networkmanager                       # superseded by WSL2's own host-managed networking
  power-profiles-daemon                # power/thermal profiles of a virtualized CPU are meaningless
  avahi nss-mdns                       # mDNS daemon: network-facing, not needed by default
  cups cups-browsed cups-filters cups-pdf system-config-printer  # no printer, network-facing daemon
  ufw ufw-docker                       # skip-by-default; WSL2's traffic model is host-managed NAT
                                        # (see install/config/firewall.sh in docs/install-audit.md) —
                                        # trivially re-addable if a real threat model calls for it
)

# ---------------------------------------------------------------------------
# Assemble: base list + KEEP_FROM_OTHER, minus every exclusion group.
# ---------------------------------------------------------------------------
strip_comments() { grep -vE '^\s*(#|$)'; }

all_excluded=("${EXCLUDE_KERNEL_BOOTLOADER_HARDWARE[@]}" "${EXCLUDE_GUI_DESKTOP[@]}" "${EXCLUDE_HARDWARE_NETWORK_DAEMONS[@]}")

{
  strip_comments < omarchy-base.packages
  printf '%s\n' "${KEEP_FROM_OTHER[@]}"
  printf '%s\n' "${ESSENTIAL_BASE_NOT_IN_EITHER_LIST[@]}"
} | sort -u > /tmp/omarchy-wsl-candidate.$$

printf '%s\n' "${all_excluded[@]}" | sort -u > /tmp/omarchy-wsl-excluded.$$

comm -23 /tmp/omarchy-wsl-candidate.$$ /tmp/omarchy-wsl-excluded.$$ > "$OUT_DIR/manifest.txt"

{
  echo "# Packages present upstream but excluded from omarchy-wsl v1, with category."
  echo "# Regenerate with: ./generate-manifest.sh"
  echo
  comm -12 /tmp/omarchy-wsl-candidate.$$ /tmp/omarchy-wsl-excluded.$$ | while read -r pkg; do
    if printf '%s\n' "${EXCLUDE_KERNEL_BOOTLOADER_HARDWARE[@]}" | grep -qx "$pkg"; then
      cat="kernel/bootloader/hardware"
    elif printf '%s\n' "${EXCLUDE_GUI_DESKTOP[@]}" | grep -qx "$pkg"; then
      cat="gui-desktop (roadmap)"
    else
      cat="hardware/network-daemon"
    fi
    printf '%-30s %s\n' "$pkg" "$cat"
  done
} > "$OUT_DIR/excluded-report.txt"

rm -f /tmp/omarchy-wsl-candidate.$$ /tmp/omarchy-wsl-excluded.$$

echo "Wrote $(wc -l < "$OUT_DIR/manifest.txt") packages to $OUT_DIR/manifest.txt"
echo "Wrote $(grep -c . "$OUT_DIR/excluded-report.txt") accounted-for lines to $OUT_DIR/excluded-report.txt"
