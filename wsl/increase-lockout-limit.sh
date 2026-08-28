#!/usr/bin/env bash
# Our WSL-native replacement for basecamp/omarchy's
# install/config/increase-lockout-limit.sh (see docs/install-audit.md).
#
# Upstream's version does two things: (1) raises the pam_faillock lockout
# threshold in /etc/pam.d/system-auth (system-wide, platform-independent),
# and (2) does the same for /etc/pam.d/sddm-autologin — which only exists
# because the `sddm` package creates it, and sddm isn't installed in v1.
# Running upstream's script verbatim fails outright: a real build attempt
# hit `sed: can't read /etc/pam.d/sddm-autologin: No such file or directory`
# and aborted. We keep exactly the system-auth half, unchanged, and drop the
# sddm-autologin half rather than guard it with an `if [[ -f ... ]]` around
# someone else's file — see PLAN.md's roadmap for re-adding it if/when sddm
# is installed for the nested-Hyprland GUI work.
set -euo pipefail

sed -i 's|^\(auth\s\+required\s\+pam_faillock.so\)\s\+preauth.*$|\1 preauth silent deny=10 unlock_time=120|' \
  /etc/pam.d/system-auth
sed -i 's|^\(auth\s\+\[default=die\]\s\+pam_faillock.so\)\s\+authfail.*$|\1 authfail deny=10 unlock_time=120|' \
  /etc/pam.d/system-auth
