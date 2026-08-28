#!/usr/bin/env bash
# The one genuinely new, WSL-only step after first-boot provisioning: bare
# metal has no concept of a "default user" for a shell launcher to pick, so
# there's no upstream equivalent of this file to defer to. Called from the
# root .bashrc hook (see arm-first-boot.sh) right after the real, unmodified
# omarchy-provision-owner exits.
#
# Finds the account omarchy-provision-owner just created (the first real,
# human-range UID it created — 1000 is both Arch's UID_MIN and the account
# useradd assigns first on a machine with no prior users) and points
# /etc/wsl.conf's [user] default= at it. Safe to call repeatedly: a no-op
# once default= is already set to a real user.
set -euo pipefail

WSL_CONF=/etc/wsl.conf

current_default="$(sed -n 's/^default=//p' "$WSL_CONF" 2>/dev/null | tail -n1)"
[[ -n "$current_default" && "$current_default" != "root" ]] && exit 0

username="$(awk -F: '$3 >= 1000 && $3 < 60000 {print $1; exit}' /etc/passwd)"
[[ -n "$username" ]] || exit 0   # provisioning hasn't created anyone yet

if grep -q '^\[user\]' "$WSL_CONF" 2>/dev/null; then
  sed -i "/^\[user\]/,/^\[/{s/^default=.*/default=$username/}" "$WSL_CONF"
else
  printf '\n[user]\ndefault=%s\n' "$username" >> "$WSL_CONF"
fi

cat <<EOF

============================================================
 Restart this WSL instance once for '$username' to become
 the default user (a WSL platform requirement, not a bug).

 Use a full shutdown, not just --terminate — on a real test,
 'wsl --terminate' alone left the instance still starting as
 root; 'wsl --shutdown' (stops the whole WSL VM, forcing a
 fresh re-read of wsl.conf) reliably picked up the new default:

   From Windows/PowerShell:
     wsl --shutdown
     wsl -d <distro-name>
============================================================

EOF
