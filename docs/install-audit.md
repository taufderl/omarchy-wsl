# Install-script audit

This describes what actually gets installed/run and why, superseding an earlier version of this document that hand-picked individual `install/*.sh` scripts by name. That approach was wrong — see PLAN.md's "Research finding that changes everything" for the full story. The short version: `omarchy` is a real pacman package, `/usr/share/omarchy/install/` (its complete `install/` tree) ships inside it, and this project runs the real orchestration files (`install/config/all.sh`, `install/post-install/all.sh`) from there wholesale, unmodified, rather than maintaining its own list of which individual scripts to call.

## What actually runs

`build/_inside-container.sh` sources exactly two files, straight from the installed `omarchy` package, via their own real `helpers/logging.sh`:

- `install/config/all.sh` — theme-system, docker (a documented no-op — see below), snapper, locate, `enable-services.sh` (see the override note below), `firewall.sh`, and whatever else this file lists in whatever `omarchy` version is pinned. New entries upstream adds here are picked up automatically the next time the build runs against a newer pin — nothing in this repo needs to change.
  - Invoked *without* `set -e` in the shell that sources it. A real build run showed why: `install/config/all.sh`'s body is a flat sequence of bare `run_logged "..."` calls with no `|| true`, and `run_logged` is explicitly designed to capture-and-continue on a failing script (it logs `Failed: script (exit code: N)` and returns rather than propagating a hard stop). Adding `set -e` around the whole chain ourselves turned one script's expected failure (`snapper.sh`, next item) into the rest of the chain — `locate.sh`, `enable-services.sh`, `firewall.sh` — silently never running at all. Fixed in `build/_inside-container.sh`.
  - `snapper.sh` fails in this environment: `Failure (org.freedesktop.DBus.Error.FileNotFound)` — snapper's D-Bus-backed config creation has nothing to talk to / no btrfs target to configure here. Left to fail and be logged, exactly like any other hardware/environment mismatch this project doesn't special-case — matches the open item already flagged for this script before it was confirmed.
  - The `limine` package's own pacman hook (`Deploying Limine after upgrade...`) fails on every `pacman` transaction with `ERROR: FAT32 boot partition not found` — expected and harmless (there is no ESP under WSL2), logged by pacman as a failed hook but does not abort the transaction or the build.
- `install/post-install/all.sh` — pacman.conf/mirrorlist restore, udev, localdb. Its `pacman.sh` references `$OMARCHY_PATH/default/pacman/pacman-stable.conf` and `mirrorlist-stable`; those aren't shipped in any runtime package (confirmed by inspecting the real package's contents — it ships only `etc/skel/*` and `usr/share/omarchy/*`, no `default/`), so `build/_inside-container.sh` recreates them at the expected path from the same bootstrap files it already fetched to get pacman working in the first place. That's the one adaptation this category needs — the script itself is untouched.

## What deliberately never runs

**`install/hardware/*`, as a category.** No matching hardware exists under WSL2 for any of it to detect — per-laptop-vendor fixes, GPU-vendor driver installs, kernel swaps ("Swap in the Panther Lake kernel before anything pulls DKMS modules in", per `install/hardware/all.sh`'s own comment). Neither `install/config/all.sh` nor `install/post-install/all.sh` calls into this directory itself, so it's simply never reached — not something this project has to separately skip. The one exception is `install/post-install/pacman.sh`'s own conditional (`lspci`-gated) sourcing of `install/hardware/pacman.sh` (adds a MacBook-T2-specific pacman repo) — that's the real script's own behavior, left alone rather than special-cased around.

**Kernel/DKMS packages**, via `pacman.conf`'s `IgnorePkg` (set in `build/_inside-container.sh`): `linux linux-firmware linux-headers linux-ptl* linux-t2* linux-firmware-marvell *-dkms`. Verified empirically to not appear anywhere in the real `omarchy` package's dependency closure — this is a pure safety net, not something expected to ever actually trigger, and it's a glob-pattern rule rather than a name list, so it doesn't need updating if upstream adds a new hardware-specific DKMS package later.

`mkinitcpio` is deliberately **not** in this list, despite looking just as kernel-adjacent as everything else here. A real build attempt with it included failed outright: `limine-mkinitcpio-hook` (a real, unavoidable dependency of the real `omarchy` package) hard-depends on `mkinitcpio`, so ignoring it made `omarchy` itself uninstallable (`unable to satisfy dependency 'mkinitcpio' required by limine-mkinitcpio-hook`). Letting `mkinitcpio` install is harmless: its hooks only ever fire on a `linux`/kernel package transaction, and `linux` itself stays excluded, so those hooks never actually trigger.

## What's installed but not enabled

Everything else `omarchy` and `omarchy-base.packages` bring along installs for real: `hyprland`, `sddm`, `quickshell`, `uwsm`, `limine`, `limine-mkinitcpio-hook`, `limine-snapper-sync`, `snapper`, `btrfs-progs`, `xorg-server`, `mesa`, the full GUI/Wayland stack, `efibootmgr`/`efivar`, everything. None of it is excluded from the package set — it's real Omarchy, installed as real Omarchy installs it. The only intervention is a short, explicit override in `build/_inside-container.sh`, applied *after* the real `install/config/enable-services.sh` (part of `install/config/all.sh`) has already run and enabled everything upstream normally enables:

```
systemctl disable NetworkManager.service    # conflicts with WSL2's own networking
systemctl disable sddm.service              # no display in v1; would fail/retry every boot otherwise
systemctl disable cups.service cups-browsed.service avahi-daemon.service  # security: no always-on network-facing daemons by default
```

`power-profiles-daemon` and everything else upstream enables is left alone — no functional conflict, no security concern, no reason to override it.

## First-boot provisioning: the real binary, not a rewrite

`/usr/bin/omarchy-provision-owner` — the real ~1100-line binary, shipped in the `omarchy` package — is used completely unmodified. Read in full (not just skimmed) to confirm this is actually safe:

- LUKS re-keying is gated on `[[ -f $PROVISIONING_DIR/luks-key ]] || return 0` — a pure no-op with no staged LUKS key, which there never will be for us. This is the script's own designed behavior for an unencrypted install, not something that needs patching.
- "Hands off to SDDM" turns out to be nothing more than `Before=display-manager.service` unit *ordering* in the real `.service` file (not used here — see below) — the script itself never execs or blocks on a display manager. Since `sddm.service` is disabled (see above), nothing hands off to anything; the script just finishes.
- It already self-checks `[[ -f $PROVISIONING_DIR/pending ]] || exit 0` on entry (its own line 25) — safe to invoke directly without a systemd `ConditionPathExists` gate duplicating that check.
- Its `finalize_user()` step already runs the equivalent of `omarchy-provision-user`, which itself does `source "$OMARCHY_INSTALL/user/all.sh"` — i.e. calling this one binary already correctly runs all the real per-user setup (theme seeding, xdg-user-dirs, dev-tool installs, etc.), with correct `$HOME`/`$OMARCHY_USER_NAME` context, automatically. No separate per-user script wiring needed.

### Incident: why this isn't triggered by `omarchy-provision-owner.service`

The first pass at this (before the pivot documented in PLAN.md) used the real `omarchy-provision-owner.service` unit — `ConditionPathExists=.../pending`, `TTYPath=/dev/tty1`, `TTYReset=yes`, `TTYVHangup=yes`. On a real `wsl --import` + boot, nothing appeared — the session landed straight into a root shell. `systemctl status`/`journalctl -u` showed the unit really did start, then:

```
Main PID: 176 (code=killed, signal=HUP)
```

`TTYVHangup=yes` forces a `vhangup(2)` on the tty to reclaim it from a previous session (a getty, or SDDM waiting to start) — on bare metal there's a previous session to evict, under WSL there isn't, so it hung up its own just-started process. Even fixed, there's no confirmed guarantee WSL's actual interactive session is what's attached to `/dev/tty1` in the first place.

The fix (`wsl/arm-first-boot.sh`) doesn't touch the binary or its `.service` unit at all — it just doesn't use the `.service` unit as the trigger. Instead, a hook in `/root/.bashrc` (+ `.bash_profile` sourcing it, so both login and non-login interactive shells pick it up) calls `/usr/bin/omarchy-provision-owner` directly, guarded on `[[ $- == *i* ]]` (interactive only) and `flock -n` (so two simultaneous `wsl -d` windows run it exactly once). Whatever terminal WSL actually attaches you to, that's the shell whose startup runs it — no attachment-mechanism assumption required. This is a genuine WSL-vs-bare-metal environment difference in *how* the real binary gets invoked, not a modification of the binary or a decision to reimplement it.

### The one genuinely new, WSL-only piece

`wsl/apply-default-user.sh`, called right after `omarchy-provision-owner` exits. Bare metal has no concept of "the WSL default user" for a launcher to pick, so there's no upstream file or behavior to defer to here — this finds the newly-created account and writes it into `/etc/wsl.conf`'s `[user] default=`. Everything else about first-boot provisioning is the real thing.

## Corrections this pivot resolved for free

Several things patched around in the previous (hand-curated) version of this build turned out to be artifacts of that same over-exclusion, not genuine WSL incompatibilities:

- `install/config/increase-lockout-limit.sh` previously failed outright (`sed: can't read /etc/pam.d/sddm-autologin`) because the `sddm` package had been excluded from the manifest. Once `sddm` installs for real (as a real dependency of the real `omarchy` package), that file exists, and the real script needs no patching or replacement at all.
- The earlier "copy `default/` into `/etc/skel`" step — invented, with no upstream equivalent — was the direct cause of a cluttered home directory (system-level dotfile *source* like `limine/`, `sddm/`, `systemd/`, `pacman/`, `libalpm/` landing in a user's home). The real `omarchy` package ships its own correctly-shaped `etc/skel/*` payload; pacstrap lays it down automatically, and `useradd -m` (inside the real `omarchy-provision-owner`) picks it up the normal way. No copying step of our own is needed at all.

## Open items

- [ ] Empirically verify a sample of hardware-gated `bin/omarchy-*` runtime scripts (battery, brightness, bluetooth, hw-nvidia, etc.) degrade cleanly with no hardware present — not yet checked against a real running instance.
- [x] `install/config/snapper.sh` fails as predicted (D-Bus `FileNotFound`) — confirmed harmless, logged, doesn't block the rest of the chain (see above).
- [ ] Confirm `install/config/firewall.sh` (also run unmodified) doesn't hang waiting on an interactive confirmation prompt under WSL2 — not yet observed either way in a build log.
