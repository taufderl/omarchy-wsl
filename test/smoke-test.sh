#!/usr/bin/env bash
# Post-build verification (PLAN.md "Verification/testing").
#
# Two modes:
#   ./smoke-test.sh --target <path>   offline checks against a pacstrap'd
#                                      target dir (e.g. right after build.sh,
#                                      before packaging — or a re-extracted
#                                      tarball)
#   ./smoke-test.sh --live            checks run FROM INSIDE the installed WSL2
#                                      instance itself (`wsl -d omarchy`, then
#                                      run this there) — the checks that only
#                                      make sense against a booted, running
#                                      instance (systemd health, live network
#                                      state, the actual default user)
set -euo pipefail

mode="${1:-}"
fail=0
check() { echo -n "  - $1 ... "; }
ok()    { echo "OK"; }
bad()   { echo "FAIL: $1"; fail=1; }

case "$mode" in
  --target)
    target="${2:?usage: smoke-test.sh --target <path>}"
    echo "Offline checks against $target"

    check "package/service state matches the intended architecture"
    # sddm/limine/hyprland etc. are EXPECTED present (real omarchy deps),
    # just not enabled — see wsl/verify-no-boot-artifacts.sh and PLAN.md.
    if bash "$(dirname "${BASH_SOURCE[0]}")/../wsl/verify-no-boot-artifacts.sh" "$target" >/tmp/verify.log 2>&1; then
      ok
    else
      bad "$(cat /tmp/verify.log)"
    fi

    check "wsl.conf present with systemd=true"
    if grep -q '^systemd=true' "$target/etc/wsl.conf" 2>/dev/null; then ok; else bad "missing/wrong wsl.conf"; fi

    check "first-boot provisioning armed (real omarchy-provision-owner, via WSL's own oobe.command)"
    if [[ -f "$target/var/lib/omarchy/provisioning/pending" ]] && \
       arch-chroot "$target" test -x /usr/bin/omarchy-provision-owner && \
       arch-chroot "$target" test -x /usr/local/bin/omarchy-wsl-oobe && \
       grep -q '^command = /usr/local/bin/omarchy-wsl-oobe$' "$target/etc/wsl-distribution.conf" 2>/dev/null; then
      ok
    else
      bad "provisioning sentinel, real omarchy-provision-owner binary, oobe script, or wsl-distribution.conf missing"
    fi

    check "every resolved package spec is actually satisfied in the target"
    # `pacman -T` (not a name-diff against `pacman -Qqe`) because several
    # specs are virtual/provided names — e.g. "nvim" installs as the real
    # package "neovim", which `Provides: nvim`. A plain `pacman -Qqe` diff
    # flags that as "missing" even though it's genuinely installed and
    # working; `-T` resolves provides correctly and only prints what's truly
    # unsatisfied. (Caught by an actual false-positive in this exact check.)
    # Re-resolves against whatever's live right now, same as the build did —
    # if run long after the build (upstream having moved on meanwhile) this
    # can show false "missing" entries for packages added since; run this
    # right after a build for a meaningful result.
    resolve_scratch="$(mktemp -d)"
    bash "$(dirname "${BASH_SOURCE[0]}")/../packages/resolve-packages.sh" "$resolve_scratch" >/dev/null
    unsatisfied="$(arch-chroot "$target" pacman -T $(cat "$resolve_scratch/manifest.txt") || true)"
    rm -rf "$resolve_scratch"
    if [[ -z "$unsatisfied" ]]; then ok; else bad "not satisfied in target: $unsatisfied"; fi
    ;;

  --live)
    echo "Live checks against the running instance"

    check "systemd is PID 1 and healthy"
    if [[ "$(ps -p 1 -o comm=)" == "systemd" ]] && \
       state="$(systemctl is-system-running 2>/dev/null || true)" && \
       [[ "$state" == "running" || "$state" == "degraded" ]]; then
      ok
      [[ "$state" == "degraded" ]] && echo "    note: degraded — run 'systemctl --failed' to see why"
    else
      bad "systemd not healthy (is boot.systemd=true set and was the instance restarted after import?)"
    fi

    check "no unexpected listening services"
    # cups/avahi/sddm are installed (real omarchy deps) but explicitly
    # disabled (see build/_inside-container.sh's WSL overrides) — nothing
    # should be listening at all.
    unexpected="$(ss -tlnH 2>/dev/null | awk '{print $4}' || true)"
    if [[ -z "$unexpected" ]]; then ok; else bad "unexpected listeners: $unexpected"; fi

    check "first-boot owner provisioning completed (no pending sentinel left)"
    if [[ ! -f /var/lib/omarchy/provisioning/pending ]]; then ok; else bad "provisioning never completed"; fi

    check "default WSL user is not root"
    if [[ "$(whoami)" != "root" ]]; then ok; else bad "still running as root — did you restart the instance after first-boot setup?"; fi
    ;;

  *)
    echo "usage: $0 --target <path> | --live" >&2
    exit 2
    ;;
esac

if (( fail )); then
  echo "smoke-test: FAILED"
  exit 1
fi
echo "smoke-test: all checks passed"
