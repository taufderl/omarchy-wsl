#!/usr/bin/env bash
# Resolves the pacstrap package list for a build. Unlike the v1 approach this
# replaces, there is no hand-picked include/exclude list to maintain here —
# see PLAN.md for why. Three inputs, all live (nothing vendored/hand-edited
# in this repo):
#
#   1. omarchy-base.packages, fetched fresh from basecamp/omarchy's current
#      default branch — this is the ISO's own authoritative "what else to
#      pacstrap besides the omarchy package itself" list. Tracking the live
#      branch (not a pinned commit) means new entries upstream adds show up
#      automatically on the next build, same as everything else in this repo
#      that used to be hand-copied.
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
# Output: $1/manifest.txt — package names/specs to pass to pacstrap.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

OUT_DIR="${1:?usage: resolve-packages.sh <output-dir>}"
mkdir -p "$OUT_DIR"

# shellcheck source=./OMARCHY_VERSION_PIN
source ./OMARCHY_VERSION_PIN

default_branch="$(curl -fsSL https://api.github.com/repos/basecamp/omarchy | \
  grep -m1 '"default_branch"' | sed -E 's/.*"default_branch": *"([^"]+)".*/\1/')"
: "${default_branch:?could not resolve the basecamp/omarchy default branch}"

echo "Fetching omarchy-base.packages from basecamp/omarchy@$default_branch" >&2
curl -fsSL "https://raw.githubusercontent.com/basecamp/omarchy/$default_branch/install/omarchy-base.packages" \
  -o "$OUT_DIR/omarchy-base.packages.fetched"

{
  grep -vE '^\s*(#|$)' "$OUT_DIR/omarchy-base.packages.fetched"
  echo "omarchy=$OMARCHY_VERSION"
  echo "base"
  echo "base-devel"
  echo "sudo"
  echo "openssh"
} | sort -u > "$OUT_DIR/manifest.txt"

echo "Wrote $(wc -l < "$OUT_DIR/manifest.txt") package specs to $OUT_DIR/manifest.txt" >&2
