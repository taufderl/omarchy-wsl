#!/usr/bin/env bash
# omarchy-wsl builder entry point.
#
# Runs entirely inside a disposable `archlinux` container (never on the host,
# never in a QEMU VM, never via a manual ISO install) — see PLAN.md
# "Architecture" for why. Produces dist/omarchy-wsl.tar.gz plus a checksum,
# signature, and build manifest.
#
# Usage: ./build/build.sh
#   Requires: docker (or podman, via CONTAINER_ENGINE=podman), network access,
#   a few GB of free disk.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTAINER_ENGINE="${CONTAINER_ENGINE:-docker}"
DIST_DIR="$REPO_ROOT/dist"

if ! command -v "$CONTAINER_ENGINE" >/dev/null; then
  echo "error: $CONTAINER_ENGINE not found. Install Docker (or set CONTAINER_ENGINE=podman)." >&2
  exit 1
fi

mkdir -p "$DIST_DIR"
rm -f "$DIST_DIR"/omarchy-wsl.tar.gz*

echo "==> Building inside a disposable archlinux container"
# --privileged: pacstrap/arch-chroot need to bind-mount /proc, /sys, /dev and
# chroot into the target tree — that needs real mount/chroot capability, not
# just a handful of --cap-add's. The container itself is discarded after this
# run (--rm); nothing here persists beyond dist/omarchy-wsl.tar.gz.
"$CONTAINER_ENGINE" run --rm --privileged \
  -v "$REPO_ROOT:/repo:ro" \
  -v "$DIST_DIR:/dist" \
  -e OMARCHY_MIRROR_URL="${OMARCHY_MIRROR_URL:-}" \
  archlinux:latest \
  bash /repo/build/_inside-container.sh

echo "==> Build artifacts:"
ls -la "$DIST_DIR"
