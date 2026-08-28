#!/usr/bin/env bash
# Runs as root inside the disposable archlinux container build.sh launches.
# Not meant to be run directly outside that context — always go through
# build/build.sh.
#
# See PLAN.md for the architecture this implements: pacstrap the real
# `omarchy` pacman package (pinned version) plus the ISO's own
# omarchy-base.packages (fetched live, not vendored), run the real
# install/config/*.sh and install/post-install/*.sh orchestration scripts
# already shipped inside that package — completely unmodified — and apply
# only the small set of additions that have no bare-metal equivalent at all
# (WSL integration) or are explicitly, narrowly justified (the short
# service-disable override, for the reasons the original security/no-GUI-v1
# brief already called for).
set -euo pipefail

REPO=/repo
DIST=/dist
TARGET=/mnt/omarchy-wsl-target
SCRATCH=/tmp/omarchy-wsl-build
mkdir -p "$SCRATCH"

log() { echo "==> $*"; }

# ---------------------------------------------------------------------------
# 1. Prep the container itself: fresh package DB, the container's OWN
#    keyring (pacstrap resolves/verifies/downloads using whatever pacman.conf
#    + keyring the *calling* system has — the container, not the not-yet-
#    existing target — so this has to happen here first), and pacstrap
#    itself.
# ---------------------------------------------------------------------------
log "Refreshing container package database"
pacman -Sy --noconfirm

log "Initializing container pacman keyring"
pacman-key --init
pacman-key --populate archlinux

log "Installing bootstrap tools (arch-install-scripts)"
pacman -S --noconfirm --needed arch-install-scripts

# ---------------------------------------------------------------------------
# 2. Fetch the real bootstrap pacman.conf/mirrorlist live from
#    basecamp/omarchy (default/pacman/pacman-stable.conf + mirrorlist-stable
#    — not vendored/hand-edited in this repo; see packages/resolve-packages.sh
#    for why that's true of everything else too). This is genuinely necessary
#    scaffolding, not a curation choice: default/pacman/* isn't shipped in
#    any runtime-installed package (confirmed by inspecting the real
#    `omarchy` package's contents — verified empirically, see PLAN.md), so
#    *something* has to bootstrap pacman before any package — including
#    omarchy-keyring itself — can be verified and installed at all.
#
#    The ONE addition on top of the real file: IgnorePkg glob patterns for
#    the kernel/initramfs/DKMS set. This is the single remaining structural
#    exclusion in the whole build (down from three large hand-picked arrays
#    in v1) — verified to not appear anywhere in omarchy's own dependency
#    tree, so it can never block installing the real package; it exists
#    purely as a durable safety net against a hardware-detection script
#    somewhere deciding WSL2's virtualized PCI bus looks like a real GPU.
#    Applied to BOTH the container's and the target's pacman.conf, so it
#    still holds for a `pacman -Syu` run inside the finished image later,
#    not just at build time.
# ---------------------------------------------------------------------------
default_branch="$(curl -fsSL https://api.github.com/repos/basecamp/omarchy | \
  grep -m1 '"default_branch"' | sed -E 's/.*"default_branch": *"([^"]+)".*/\1/')"
log "Fetching bootstrap pacman.conf/mirrorlist from basecamp/omarchy@$default_branch"
curl -fsSL "https://raw.githubusercontent.com/basecamp/omarchy/$default_branch/default/pacman/pacman-stable.conf" \
  -o "$SCRATCH/pacman-stable.conf"
curl -fsSL "https://raw.githubusercontent.com/basecamp/omarchy/$default_branch/default/pacman/mirrorlist-stable" \
  -o "$SCRATCH/mirrorlist-stable"

# IgnorePkg is only valid inside [options] — appending it at the end of the
# file (after [omarchy]'s own section starts) silently attaches it to that
# repo section instead, where pacman just warns "not recognized" and drops
# it, defeating the whole point (caught by an actual pacman warning on a
# real build run). Insert it right after [options] instead.
#
# --- omarchy-wsl addition, not part of the fetched file ---
# Structural safety net: no kernel/DKMS package ever belongs in a WSL2 image
# (no kernel to boot, no hardware to build kernel modules against).
#
# mkinitcpio is deliberately NOT in this list, despite being just as
# kernel-adjacent as everything else here — a real build run caught that
# `limine-mkinitcpio-hook` (a real, unavoidable dependency of the real
# `omarchy` package) hard-depends on it, so ignoring it makes `omarchy`
# itself uninstallable ("unable to satisfy dependency 'mkinitcpio'").
# Installing it is harmless: its hooks only ever fire on a `linux`/kernel
# package transaction, and `linux` is (and must stay) on this list, so
# mkinitcpio's own hooks never actually trigger.
sed -i '/^\[options\]/a IgnorePkg = linux linux-firmware linux-headers linux-ptl* linux-t2* linux-firmware-marvell *-dkms' \
  "$SCRATCH/pacman-stable.conf"

cp "$SCRATCH/pacman-stable.conf" /etc/pacman.conf
cp "$SCRATCH/mirrorlist-stable" /etc/pacman.d/mirrorlist

# ---------------------------------------------------------------------------
# 3. Bootstrap trust in the [omarchy] repo's signing key via the pinned,
#    hash-verified omarchy-keyring package (packages/OMARCHY_KEYRING_PIN) —
#    the standard *-keyring bootstrap problem (it can't verify itself), same
#    approach archlinux-keyring itself needs.
# ---------------------------------------------------------------------------
# shellcheck source=../packages/OMARCHY_KEYRING_PIN
source "$REPO/packages/OMARCHY_KEYRING_PIN"
log "Fetching pinned omarchy-keyring package ($FILENAME)"
curl -fsSL "https://pkgs.omarchy.org/stable/x86_64/$FILENAME" -o "/tmp/$FILENAME"
echo "$SHA256  /tmp/$FILENAME" | sha256sum -c -
log "Hash verified. Installing omarchy-keyring (its own scriptlet trusts the omarchy key)"
pacman -U --noconfirm "/tmp/$FILENAME"
rm -f "/tmp/$FILENAME"

log "Refreshing package database with the omarchy repo active"
pacman -Sy --noconfirm

# ---------------------------------------------------------------------------
# 4. Resolve and pacstrap the package set (packages/resolve-packages.sh —
#    omarchy-base.packages fetched live + the pinned `omarchy=$VERSION` +
#    base/base-devel/sudo/openssh; see that script for why each is there).
# ---------------------------------------------------------------------------
log "Resolving package manifest"
bash "$REPO/packages/resolve-packages.sh" "$SCRATCH"

mkdir -p "$TARGET"
log "pacstrap: installing $(wc -l < "$SCRATCH/manifest.txt") package specs into $TARGET"
pacstrap -c "$TARGET" $(cat "$SCRATCH/manifest.txt")

log "Installing the same bootstrap pacman.conf/mirrorlist into the target"
install -Dm644 "$SCRATCH/pacman-stable.conf" "$TARGET/etc/pacman.conf"
install -Dm644 "$SCRATCH/mirrorlist-stable" "$TARGET/etc/pacman.d/mirrorlist"

log "Initializing the target's own pacman keyring"
arch-chroot "$TARGET" pacman-key --init
arch-chroot "$TARGET" pacman-key --populate archlinux omarchy

# ---------------------------------------------------------------------------
# 5. Generate a locale. Base Arch installs don't ship one pre-generated —
#    normally archinstall's base setup handles this (same gap category as
#    sudo/openssh above), and skipping it produced a real, live bug: a
#    genuine `wsl -d` session came up with `setlocale: LC_CTYPE: cannot
#    change locale (en_US.UTF-8): No such file or directory` on every
#    prompt. en_US.UTF-8 specifically because that's what WSL itself passes
#    through as $LANG.
# ---------------------------------------------------------------------------
log "Generating en_US.UTF-8 locale"
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' "$TARGET/etc/locale.gen"
arch-chroot "$TARGET" locale-gen
echo "LANG=en_US.UTF-8" > "$TARGET/etc/locale.conf"

# ---------------------------------------------------------------------------
# 6. Recreate the two default/pacman/* files at the exact path the real,
#    unmodified install/post-install/pacman.sh expects them
#    ($OMARCHY_PATH/default/pacman/pacman-stable.conf and mirrorlist-stable —
#    default/ genuinely isn't shipped in any package, see step 2's comment),
#    so that script — and everything else under install/ — can run
#    completely unmodified rather than being skipped or rewritten.
# ---------------------------------------------------------------------------
install -Dm644 "$SCRATCH/pacman-stable.conf" "$TARGET/usr/share/omarchy/default/pacman/pacman-stable.conf"
install -Dm644 "$SCRATCH/mirrorlist-stable" "$TARGET/usr/share/omarchy/default/pacman/mirrorlist-stable"

# ---------------------------------------------------------------------------
# 7. Run the real install/config/*.sh and install/post-install/*.sh
#    orchestration — install/config/all.sh and install/post-install/all.sh,
#    exactly as shipped in the omarchy package, via their own real
#    helpers/logging.sh (run_logged). Not reimplemented, not hand-selected
#    script-by-script: whatever these two files call is what runs, so a
#    future omarchy release adding a new install/config/*.sh script is
#    picked up automatically the next time this build runs, with zero
#    changes needed here.
#
#    install/hardware/* is the one category deliberately never invoked: no
#    matching hardware exists under WSL2 for any of it to detect (kernel
#    swaps, DKMS builds, vendor-specific fixes), and install/config/all.sh
#    and install/post-install/all.sh don't call into it themselves — the
#    only place hardware/* gets touched at all is post-install/pacman.sh's
#    own conditional (lspci-gated, harmless) sourcing of hardware/pacman.sh,
#    which is left alone since it's the real script's own behavior, not
#    something we're choosing to run.
# ---------------------------------------------------------------------------
log "Running the real install/config/all.sh and install/post-install/all.sh"
# No `set -e` in this inner shell: install/config/all.sh's body is a flat
# sequence of bare `run_logged "..."` calls with no `|| true` of their own —
# matching how upstream must actually invoke it too, since a real build
# already showed one of them (snapper.sh, see docs/install-audit.md) failing
# with a normal, expected error, and run_logged is explicitly designed to
# capture-and-continue on exactly that (it logs "Failed: script (exit code:
# N)" and returns, it doesn't propagate a hard stop). Adding `set -e` here
# ourselves turned one script's expected failure into the whole install/config
# chain silently not finishing (caught by an actual build that stopped dead
# right after snapper.sh, having skipped locate.sh/enable-services.sh/
# firewall.sh entirely). `|| true` on the whole arch-chroot call is the
# outer half of the same fix: this script's own `set -euo pipefail` would
# otherwise still abort the build if the LAST script in either chain happens
# to be the one that fails.
for orchestrator in config/all.sh post-install/all.sh; do
  arch-chroot "$TARGET" /usr/bin/env \
    OMARCHY_PATH=/usr/share/omarchy \
    OMARCHY_INSTALL=/usr/share/omarchy/install \
    OMARCHY_LOG_TO_STDOUT=1 \
    bash -c '
      source "$OMARCHY_INSTALL/helpers/logging.sh"
      source "$OMARCHY_INSTALL/'"$orchestrator"'"
    ' || true
done

# ---------------------------------------------------------------------------
# 8. The one deliberate, narrow WSL-specific override — not a rewrite of
#    enable-services.sh (which just ran, unmodified, as part of
#    install/config/all.sh above and enabled everything real Omarchy enables,
#    including these). Each line here has a specific, stated reason; nothing
#    else upstream enables is touched.
# ---------------------------------------------------------------------------
log "Applying the WSL service overrides (see PLAN.md for the reasoning per line)"
arch-chroot "$TARGET" systemctl disable sddm.service || true            # no display in v1; would fail/retry every boot otherwise
arch-chroot "$TARGET" systemctl disable cups.service cups-browsed.service avahi-daemon.service || true  # security: no always-on network-facing daemons by default

# Separately, Microsoft's own WSL custom-distro guidance
# (https://learn.microsoft.com/en-us/windows/wsl/build-custom-distro,
# "Systemd recommendations") lists these exact units as known to cause
# issues under WSL specifically — a WSL-platform concern, not an Omarchy
# one, masked (not just disabled) the same way that guidance says to for
# any distro. NetworkManager.service is in their list too — masked here
# instead of the plain `disable` an earlier version of this file used,
# for the same reason as the rest of this group.
for unit in NetworkManager.service systemd-resolved.service systemd-networkd.service \
            systemd-tmpfiles-setup.service systemd-tmpfiles-clean.service systemd-tmpfiles-clean.timer \
            systemd-tmpfiles-setup-dev-early.service systemd-tmpfiles-setup-dev.service tmp.mount; do
  arch-chroot "$TARGET" systemctl mask "$unit" || true
done

# ---------------------------------------------------------------------------
# 9. WSL integration layer: wsl.conf, first-boot owner provisioning (the
#    real, unmodified omarchy-provision-owner binary — see wsl/arm-first-boot.sh).
# ---------------------------------------------------------------------------
log "Installing /etc/wsl.conf"
install -Dm644 "$REPO/wsl/wsl.conf" "$TARGET/etc/wsl.conf"

log "Arming first-boot owner provisioning"
"$REPO/wsl/arm-first-boot.sh" "$TARGET"

# ---------------------------------------------------------------------------
# 10. Verify, then package.
# ---------------------------------------------------------------------------
log "Verifying the target's package/service state"
bash "$REPO/wsl/verify-no-boot-artifacts.sh" "$TARGET"

log "Cleaning package cache in target (keep the rootfs lean)"
arch-chroot "$TARGET" pacman -Scc --noconfirm

log "Packaging $TARGET into dist/omarchy-wsl.tar.gz"
tar -C "$TARGET" \
  --exclude='./proc/*' --exclude='./sys/*' --exclude='./dev/*' \
  --exclude='./tmp/*' --exclude='./run/*' \
  -czpf "$DIST/omarchy-wsl.tar.gz" .

tarball_sha256="$(sha256sum "$DIST/omarchy-wsl.tar.gz" | awk '{print $1}')"
echo "$tarball_sha256" > "$DIST/omarchy-wsl.tar.gz.sha256"

# shellcheck source=../packages/OMARCHY_VERSION_PIN
source "$REPO/packages/OMARCHY_VERSION_PIN"
cat > "$DIST/build-manifest.json" <<EOF
{
  "built_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "omarchy_version": "$OMARCHY_VERSION",
  "omarchy_base_packages_branch": "$default_branch",
  "omarchy_keyring_pin": "$FILENAME",
  "package_spec_count": $(wc -l < "$SCRATCH/manifest.txt"),
  "tarball_sha256": "$tarball_sha256"
}
EOF

log "Done."
