#!/usr/bin/env bash
# The one genuinely new, WSL-only step after first-boot provisioning: bare
# metal has no concept of a "default user" for a shell launcher to pick, so
# there's no upstream equivalent of this file to defer to. Called from
# wsl/oobe.sh (WSL's own oobe.command) right after the real, unmodified
# omarchy-provision-owner exits.
#
# Finds the account omarchy-provision-owner just created (the first real,
# human-range UID it created — 1000 is both Arch's UID_MIN and the account
# useradd assigns first on a machine with no prior users) and points
# /etc/wsl.conf's [user] default= at it. Safe to call repeatedly: a no-op
# once default= is already set to a real user.
#
# This is a defense-in-depth backstop, not the thing that actually gets the
# user into their new account: /etc/wsl-distribution.conf's own
# oobe.defaultUid=1000 already makes WSL switch to the new user immediately,
# in the same session, once oobe.command exits 0 — confirmed on real
# hardware (no restart needed). wsl.conf's default= just makes that hold
# true for every later launch too. No user-facing message here: printing a
# "restart WSL now" banner every first boot was actively wrong/confusing
# once the immediate-switch path was confirmed working.
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
