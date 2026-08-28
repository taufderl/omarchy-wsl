#!/usr/bin/env bash
# The actual /etc/wsl-distribution.conf `oobe.command` target, installed to
# /usr/local/bin/omarchy-wsl-oobe. WSL's own launcher runs this the first
# time a shell is opened for this distribution — see wsl-distribution.conf
# for why this replaced the earlier .bashrc/PROMPT_COMMAND approach.
#
# Deliberately never returns non-zero: per WSL's own documented contract,
# "if [oobe.command] returns non zero, ... the user won't be able to open a
# shell" — a failed/cancelled provisioning attempt should leave the user
# with a root shell to retry from (matching what already happens today),
# never lock them out entirely.
set -uo pipefail

if [[ -f /var/lib/omarchy/provisioning/pending ]]; then
  # flock -n, same as before: if two sessions somehow both hit this (WSL's
  # own tracking of "has OOBE run" should already prevent that, but the real
  # omarchy-provision-owner re-checks the pending sentinel on entry too, for
  # its own deferred-provisioning/factory-reset use cases), only one runs it.
  flock -n /var/lib/omarchy/provisioning/.lock /usr/bin/omarchy-provision-owner || true
fi

/usr/local/bin/omarchy-wsl-apply-default-user || true

exit 0
