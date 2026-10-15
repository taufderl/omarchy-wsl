#!/usr/bin/env bash
# Resolves the pacstrap package list for a build. Unlike the v1 approach this
# replaces, there is no hand-picked include/exclude list to maintain here —
# see PLAN.md for why. Three inputs, all live (nothing vendored/hand-edited
# in this repo):
#
#   1. omarchy-base.packages, read out of the pinned omarchy package itself
#      (it ships the file at usr/share/omarchy/install/). Upstream's default
#      branch tracks the edge channel and lists packages the stable repo
#      doesn't carry yet, so only the list that shipped with the pinned
#      release is guaranteed to match it. Bumping OMARCHY_VERSION_PIN moves
#      the list along with it.
#   2. `omarchy=$OMARCHY_VERSION` (packages/OMARCHY_VERSION_PIN) — the one
#      deliberately pinned thing. Installing this one package pulls in the
#      entire real dependency graph (hyprland, sddm, limine, snapper,
#      quickshell, uwsm, gnome-keyring, gum, jq, ...) via pacman itself, not
#      via anything this repo lists by name.
#   3. base, base-devel, sudo, openssh — verified empirically (see git
#      history for sudo/openssh) to be genuinely absent from omarchy's own
#      dependency closure. `base`/`base-devel` are what pacstrap needs
#      explicitly listed to produce a usable Arch system at all (pacstrap
#      does not imply them), and are also what `yay` (an omarchy-base.packages
#      entry) needs to build AUR packages. `sudo`/`openssh` are what the real
#      install/config/*.sh scripts assume are present (sudoers.d tuning,
#      ssh-command-path.sh/ssh-keepalive.sh). All four normally come from
#      archinstall's base profile; we don't reuse that layer, so they're
#      listed explicitly here — the one place this script still hand-lists
#      anything.
#
# Usage: resolve-packages.sh <output-dir> [omarchy-base.packages]
#   Without the second argument, downloads the pinned omarchy package via
#   pacman (needs the [omarchy] repo configured, as the build container has).
#   test/smoke-test.sh passes the copy already installed in a target instead.
#
# Output: $1/manifest.txt — package names/specs to pass to pacstrap.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# A relative $1 must resolve against the caller's cwd, not this script's own
# directory — resolving OUT_DIR before any `cd` (there isn't one) keeps that
# true; every current caller happens to pass an absolute path, but a relative
# one would otherwise have silently landed in the wrong place.
OUT_DIR="${1:?usage: resolve-packages.sh <output-dir> [omarchy-base.packages]}"
mkdir -p "$OUT_DIR"

# shellcheck source=./OMARCHY_VERSION_PIN
source "$SCRIPT_DIR/OMARCHY_VERSION_PIN"

base_list="${2:-}"
if [[ -z "$base_list" ]]; then
  pkg_cache="$OUT_DIR/omarchy-pkg"
  mkdir -p "$pkg_cache"
  echo "Downloading omarchy=$OMARCHY_VERSION to read its omarchy-base.packages" >&2
  pacman -Sw --noconfirm -dd --cachedir "$pkg_cache" "omarchy=$OMARCHY_VERSION" >&2
  pkg_file="$(ls "$pkg_cache"/omarchy-"$OMARCHY_VERSION"-*.pkg.tar.zst)"
  base_list="$OUT_DIR/omarchy-base.packages"
  bsdtar -xOf "$pkg_file" usr/share/omarchy/install/omarchy-base.packages > "$base_list"
fi
[[ -s "$base_list" ]] || { echo "error: empty or missing omarchy-base.packages: $base_list" >&2; exit 1; }

{
  grep -vE '^\s*(#|$)' "$base_list"
  echo "omarchy=$OMARCHY_VERSION"
  echo "base"
  echo "base-devel"
  echo "sudo"
  echo "openssh"
} | sort -u > "$OUT_DIR/manifest.txt"

echo "Wrote $(wc -l < "$OUT_DIR/manifest.txt") package specs to $OUT_DIR/manifest.txt" >&2
