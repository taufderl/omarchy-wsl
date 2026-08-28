#!/usr/bin/env bash
# Our WSL-native replacement for basecamp/omarchy's install/config/enable-services.sh
# (see docs/install-audit.md for the full comparison). Run inside the chroot
# during the build, after packages are installed.
#
# Upstream enables: cups.service, cups-browsed.service, avahi-daemon.service,
# linux-modules-cleanup.service, docker.socket, systemd-resolved.service,
# NetworkManager.service (+ masks NetworkManager-wait-online.service),
# power-profiles-daemon.service, sddm.service, systemd-oomd.service.
#
# We enable only the two that are genuinely platform-independent; every other
# upstream unit belongs to a package we don't install in v1 (see
# packages/generate-manifest.sh), so enabling it would just fail or no-op —
# neither of which is better than not asking for it in the first place.
set -euo pipefail

systemctl enable docker.socket
systemctl enable systemd-oomd.service

# Deliberately NOT enabled, and why:
#   cups.service, cups-browsed.service   — no printer under WSL2; package not installed
#   avahi-daemon.service                 — mDNS daemon, network-facing, not needed by default
#   linux-modules-cleanup.service        — tied to `linux` package, not installed
#   systemd-resolved.service             — WSL2 already generates a working resolv.conf;
#                                           see docs/install-audit.md for the conflict this avoids
#   NetworkManager.service               — superseded by WSL2's own host-managed networking
#   power-profiles-daemon.service        — power profiles of a virtualized CPU are meaningless
#   sddm.service                         — no display manager in v1 (no GUI session to greet into)
