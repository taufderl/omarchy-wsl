#!/usr/bin/env bash
# Runs as root inside the disposable archlinux container build.sh launches.
# Not meant to be run directly outside that context (it repartitions nothing,
# but it does install packages system-wide into the container and write to
# /dist) — always go through build/build.sh.
set -euo pipefail

REPO=/repo
DIST=/dist
TARGET=/mnt/omarchy-wsl-target
OMARCHY_COMMIT="$(cat "$REPO/packages/UPSTREAM_COMMIT")"

log() { echo "==> $*"; }

# ---------------------------------------------------------------------------
# 1. Prep the container itself: fresh package DB, base bootstrap tools, and
#    the container's OWN keyring (pacstrap resolves/verifies/downloads using
#    whatever pacman.conf + keyring the *calling* system has — the container,
#    not the not-yet-existing target — so this has to happen here first).
# ---------------------------------------------------------------------------
log "Refreshing container package database"
pacman -Sy --noconfirm

log "Initializing container pacman keyring"
pacman-key --init
pacman-key --populate archlinux

log "Installing bootstrap tools (arch-install-scripts, zstd, git)"
pacman -S --noconfirm --needed arch-install-scripts zstd git

# ---------------------------------------------------------------------------
# 2. Add the [omarchy] repo to the CONTAINER's pacman.conf, and bootstrap
#    trust in its signing key via the pinned omarchy-keyring package (see
#    packages/OMARCHY_KEYRING_PIN for why this exact file+hash, not "whatever
#    the repo serves today"). This mirrors exactly how archlinux-keyring
#    bootstraps trust for the official repos, just for Omarchy's own.
# ---------------------------------------------------------------------------
log "Adding [omarchy] repo to container pacman.conf"
if ! grep -q '^\[omarchy\]' /etc/pacman.conf; then
  cat >> /etc/pacman.conf <<'EOF'

[omarchy]
Server = https://pkgs.omarchy.org/stable/$arch
EOF
fi

# shellcheck source=/dev/null
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
# 3. pacstrap the target rootfs with the curated v1 package manifest.
# ---------------------------------------------------------------------------
log "Regenerating package manifest from vendored upstream lists"
GENERATED=/tmp/omarchy-wsl-packages
mkdir -p "$GENERATED"
( cd "$REPO/packages" && ./generate-manifest.sh "$GENERATED" )

mkdir -p "$TARGET"
log "pacstrap: installing $(wc -l < "$GENERATED/manifest.txt") packages into $TARGET"
pacstrap -c "$TARGET" $(cat "$GENERATED/manifest.txt")

# ---------------------------------------------------------------------------
# 4. Restore the real (non-bootstrap) pacman.conf/mirrorlist into the target,
#    same as upstream's own install/post-install/pacman.sh does — minus its
#    trailing `source install/hardware/pacman.sh` call, which we skip (T2
#    MacBook-specific, see docs/install-audit.md).
# ---------------------------------------------------------------------------
log "Installing final pacman.conf/mirrorlist into target"
install -Dm644 "$REPO/patches/pacman-stable.conf" "$TARGET/etc/pacman.conf"
install -Dm644 "$REPO/patches/mirrorlist-stable" "$TARGET/etc/pacman.d/mirrorlist"

log "Initializing target's own pacman keyring"
arch-chroot "$TARGET" pacman-key --init
arch-chroot "$TARGET" pacman-key --populate archlinux omarchy

# ---------------------------------------------------------------------------
# 5. Vendor the actual basecamp/omarchy checkout onto the system, at the same
#    path (/usr/share/omarchy) its own scripts already assume (e.g.
#    OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}" in the real
#    bin/omarchy-provision-owner). This is where the dotfiles skeleton
#    (default/), the etc/ overlay, and the bin/omarchy-* runtime tools this
#    project doesn't reimplement all come from.
# ---------------------------------------------------------------------------
log "Cloning basecamp/omarchy @ $OMARCHY_COMMIT"
git clone --quiet https://github.com/basecamp/omarchy.git /tmp/omarchy-src
git -C /tmp/omarchy-src checkout --quiet "$OMARCHY_COMMIT"
mkdir -p "$TARGET/usr/share/omarchy"
cp -a /tmp/omarchy-src/. "$TARGET/usr/share/omarchy/"

log "Exposing bin/omarchy-* on PATH"
install -Dm644 /dev/stdin "$TARGET/etc/profile.d/omarchy-wsl-path.sh" <<'EOF'
export PATH="/usr/share/omarchy/bin:$PATH"
EOF

log "Applying the default/ dotfile skeleton to /etc/skel"
# New users (created by the first-boot owner-provisioning flow) get these via
# useradd -m's normal /etc/skel copy — the same mechanism bare-metal Omarchy
# relies on to give the owner account its dotfiles, just triggered later
# (first boot) instead of during the installer.
mkdir -p "$TARGET/etc/skel"
cp -a "$TARGET/usr/share/omarchy/default/." "$TARGET/etc/skel/"

log "Applying the etc/ overlay (excluding bootloader/splash/display-manager/network pieces)"
for entry in "$TARGET"/usr/share/omarchy/etc/*; do
  name="$(basename "$entry")"
  case "$name" in
    limine-entry-tool.d|mkinitcpio.conf.d|plymouth|sddm.conf.d|NetworkManager|cups)
      log "  skip etc/$name (see docs/install-audit.md)"
      ;;
    *)
      cp -a "$entry" "$TARGET/etc/"
      ;;
  esac
done

# ---------------------------------------------------------------------------
# 6. Run the audited keep-list of install/*.sh scripts (see
#    docs/install-audit.md) inside the chroot, via their own real
#    helpers/logging.sh — not reimplemented, sourced live from the clone.
# ---------------------------------------------------------------------------
#
# NOTE: every script under install/user/* (theme.sh, chromium.sh, git.sh,
# xcompose.sh, mise-work.sh, mise.sh, default-keyring.sh) writes into $HOME/~
# and several read $OMARCHY_USER_NAME/$OMARCHY_USER_EMAIL — they all assume
# they're running as, and for, a real already-created user. At this point in
# the build we're root, in a chroot, and no user exists yet (that happens
# later, at first boot — see wsl/omarchy-wsl-provision-owner). Running them
# now would silently write into /root's home for a user who's never created,
# which is wrong, not just inert. So none of install/user/* runs at build
# time in v1 — tracked as an open item (wiring the applicable ones into
# first-boot provisioning, once it creates the real user) rather than done
# here under time pressure. Same reasoning killed install/config/lockscreen-pam.sh
# (a one-line call to omarchy-apply-lock, a Hyprland-lock-screen tool with
# nothing to apply to without a GUI session) — see docs/install-audit.md.
log "Running audited install scripts inside the chroot"
KEEP_SCRIPTS=(
  install/config/theme-system.sh
  install/config/fix-powerprofilesctl-shebang.sh
  install/config/ssh-command-path.sh
  install/config/ssh-keepalive.sh
  install/config/docker.sh
  install/config/locate.sh
  install/post-install/udev.sh
  install/post-install/localdb.sh
)
for script in "${KEEP_SCRIPTS[@]}"; do
  if [[ ! -f "$TARGET/usr/share/omarchy/$script" ]]; then
    echo "warning: $script not found in this omarchy revision, skipping" >&2
    continue
  fi
  arch-chroot "$TARGET" /usr/bin/env \
    OMARCHY_PATH=/usr/share/omarchy \
    OMARCHY_INSTALL=/usr/share/omarchy/install \
    OMARCHY_LOG_TO_STDOUT=1 \
    bash -c '
      set -e
      source "$OMARCHY_INSTALL/helpers/logging.sh"
      run_logged "$OMARCHY_PATH/'"$script"'"
    '
done

log "Running our increase-lockout-limit.sh (replaces upstream's, see wsl/increase-lockout-limit.sh)"
install -Dm755 "$REPO/wsl/increase-lockout-limit.sh" "$TARGET/usr/local/bin/omarchy-wsl-lockout-limit"
arch-chroot "$TARGET" /usr/local/bin/omarchy-wsl-lockout-limit

log "Applying WSL-native service enablement (replaces install/config/enable-services.sh)"
install -Dm755 "$REPO/wsl/enable-services.sh" "$TARGET/usr/local/bin/omarchy-wsl-enable-services"
arch-chroot "$TARGET" /usr/local/bin/omarchy-wsl-enable-services

# ---------------------------------------------------------------------------
# 7. WSL integration layer: wsl.conf, first-boot owner provisioning.
# ---------------------------------------------------------------------------
log "Installing /etc/wsl.conf"
install -Dm644 "$REPO/wsl/wsl.conf" "$TARGET/etc/wsl.conf"

log "Arming first-boot owner provisioning"
"$REPO/wsl/arm-first-boot.sh" "$TARGET"

# ---------------------------------------------------------------------------
# 8. Verify, then package.
# ---------------------------------------------------------------------------
log "Verifying no bare-metal-only artifacts made it in"
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

cat > "$DIST/build-manifest.json" <<EOF
{
  "built_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "upstream_omarchy_commit": "$OMARCHY_COMMIT",
  "omarchy_keyring_pin": "$FILENAME",
  "package_count": $(wc -l < "$GENERATED/manifest.txt"),
  "tarball_sha256": "$tarball_sha256"
}
EOF

log "Done."
