# PLAN.md — omarchy-wsl builder

This is the contributor-facing build design. Read `README.md` first for the user-facing framing.

## Implementation status

**Verified live, end to end, on real Windows/WSL2 hardware.** `wsl --import` + boot works, `omarchy-provision-owner` (the real, unmodified binary) runs and completes the full flow — account creation, hostname/timezone, all the real per-user `install/user/*.sh` setup (including a real `mise`-managed Node.js install) — `/etc/skel` is confirmed clean, and the created user correctly becomes the WSL default after a full `wsl --shutdown` (not just `--terminate`, a separate WSL quirk found along the way — see `docs/install-audit.md`).

One thing found live and fixed after that first successful run: the *automatic* first-boot trigger (root's `.bashrc` hook) didn't fire reliably, even though the real binary and environment were both fine — running it by hand, after the shell had already started, worked perfectly. Root cause and fix (moved the trigger to `PROMPT_COMMAND`, run once the shell is fully interactive) are in `docs/install-audit.md`'s "Incident #3". Rebuilt with that fix; the live-tested account creation above was via the manual-invocation workaround, not yet re-confirmed against a from-scratch image with the `PROMPT_COMMAND` fix baked in — that's the next real-hardware test.

## Why this is built the way it is

An earlier version of this project (see git history) hand-curated a package allow-list and reimplemented several install scripts (its own `enable-services.sh`, its own provisioning driver, a fabricated "copy Omarchy's `default/` dotfiles into `/etc/skel`" step). That produced a working image, but it was a similar-looking system, not Omarchy — concretely, it cluttered every new user's home directory with system-level config source that has no business there, and it couldn't automatically pick up new `omarchy-*` tooling the way "the real thing" does.

The fix, confirmed by actually downloading and inspecting the real packages from `pkgs.omarchy.org`: **`omarchy` is a real, complete pacman package.** Installing it pulls in hyprland, sddm, limine, snapper, quickshell, uwsm, gnome-keyring, gum, jq, etc. as its own real dependencies — no hand-maintained list needed. It ships `etc/skel/*` (the real per-user dotfile skeleton) and the *entire* `install/` script tree at `/usr/share/omarchy/install/`, already at the exact path those scripts assume. `omarchy-provision-owner` (the real first-boot binary, read in full) turns out to already handle the unencrypted-install case cleanly, and its "SDDM handoff" is just systemd unit *ordering* that never triggers if `sddm.service` is never enabled — nothing about it needed rewriting.

## Goals & non-goals

**Goal:** pacstrap the real `omarchy` package plus the ISO's own `omarchy-base.packages`, run the real orchestration scripts already shipped inside that package, and add only what's genuinely inapplicable (kernel/DKMS — structural, not curated) or genuinely new to WSL (the shell-startup provisioning trigger, the `wsl.conf` default-user step). If omarchy ships a new `omarchy-*` tool or a new `install/config/*.sh` script, the next build picks it up automatically — nothing in this repo should need to change for that.

**Non-goals, still holding from the original scope:**
- No Hyprland/Wayland GUI *session* in v1 (the packages install; nothing launches them — see Roadmap).
- No self-contained `.wsl` package format yet — plain rootfs tarball for `wsl --import`.
- No attempt at direct DRM/KMS passthrough for Hyprland (unsupported upstream, per earlier research).

## Architecture

```
[archlinux container, disposable]
   fetch bootstrap pacman.conf/mirrorlist + IgnorePkg addition  (live, from basecamp/omarchy)
   bootstrap-trust the [omarchy] repo via pinned omarchy-keyring hash
   resolve-packages.sh: omarchy-base.packages (live) + omarchy=<pinned version> + base/base-devel/sudo/openssh
   pacstrap target/
   recreate default/pacman/* at the path install/post-install/pacman.sh expects (not shipped in any package)
   arch-chroot: run the REAL install/config/all.sh, install/post-install/all.sh — unmodified
   apply the short, explicit WSL service-disable override (NetworkManager, sddm, cups*, avahi-daemon)
   arm first-boot provisioning: the REAL omarchy-provision-owner, hooked from root's .bashrc
   verify (wsl/verify-no-boot-artifacts.sh)
   tar target/ → dist/omarchy-wsl.tar.gz + sha256 + build-manifest.json
```

### Package resolution (`packages/resolve-packages.sh`)

No vendored/hand-edited package list in this repo. Three inputs:
1. `omarchy-base.packages`, fetched live from `basecamp/omarchy`'s current default branch — the ISO's own authoritative list, tracked live rather than pinned, so new entries show up automatically.
2. `omarchy=$OMARCHY_VERSION` (`packages/OMARCHY_VERSION_PIN`) — the one deliberately pinned thing, for build stability (the project's explicit choice: pin-and-bump over always-latest). Pulls in the entire real dependency graph via pacman itself.
3. `base`, `base-devel`, `sudo`, `openssh` — verified empirically absent from `omarchy`'s dependency closure; these come from `archinstall`'s base profile on bare metal, which this project doesn't reuse.

**The one structural exclusion**: `IgnorePkg` glob patterns for kernel/DKMS packages (`linux*`, `*-dkms`, etc. — deliberately *not* `mkinitcpio`, which is a real unavoidable dependency of `omarchy` via `limine-mkinitcpio-hook`, caught by an actual failed build — see `docs/install-audit.md`), applied to the pacman.conf used both at build time and baked into the target (so it holds for a later `pacman -Syu` too).

### Script execution

`install/config/all.sh` and `install/post-install/all.sh`, sourced directly from the installed package via their own real `helpers/logging.sh` — not reimplemented, not hand-picked script-by-script. `install/hardware/*` is never reached (neither orchestrator calls into it) — no matching hardware exists under WSL2 for any of it to do anything with anyway. Full reasoning and the one small adaptation `install/post-install/pacman.sh` needs (recreating `default/pacman/*` at its expected path, since `default/` isn't shipped in any runtime package) are in `docs/install-audit.md`.

### Service overrides

Applied *after* the real `install/config/enable-services.sh` has already run (it's part of `install/config/all.sh`) and enabled everything upstream normally enables. A short, explicit, separately-visible override then disables exactly three things, each with a stated reason (functional conflict or the original security brief) — see `docs/install-audit.md`. Nothing else upstream enables is touched.

### First-boot provisioning

The real `/usr/bin/omarchy-provision-owner`, completely unmodified, triggered from a hook in `/root/.bashrc`/`.bash_profile` instead of its own `.service` unit (which crashes under WSL — see `docs/install-audit.md`'s incident write-up) plus one genuinely new WSL-only step (`wsl/apply-default-user.sh`) to set `/etc/wsl.conf`'s default user, since bare metal has no equivalent concept at all.

## Security hardening

- Pacman signature verification stays on throughout — no `SigLevel = Never`, no unsigned-package shortcuts.
- The `[omarchy]` repo's signing key is trusted via a pinned, sha256-verified `omarchy-keyring` package (`packages/OMARCHY_KEYRING_PIN`) — the standard bootstrap approach for a repo whose own keyring package can't verify itself, same as `archlinux-keyring`.
- `omarchy=$OMARCHY_VERSION` is pinned (not floating) for build stability/traceability; every build's manifest records exactly what version and branch state it used.
- No default/blank passwords — `omarchy-provision-owner`'s own real password-setup flow is unchanged.
- `NetworkManager`/`sddm`/`cups`/`cups-browsed`/`avahi-daemon` are installed but explicitly not enabled — no always-on network-facing daemons or conflicting network stacks by default.
- The final tarball is checksummed; a build manifest records the pinned version, the `omarchy-base.packages` branch state, and the keyring pin used.
- Threat model: a WSL distro runs with the invoking user's own privileges and reaches the Windows filesystem via `/mnt/c` — this project doesn't create isolation that doesn't exist upstream either, in WSL2 or in Omarchy.

## Verification / testing

`test/smoke-test.sh --target <path>` (offline): package/service state matches the intended architecture (kernel/DKMS absent; `omarchy`/`sddm`/`hyprland`/`limine`/`snapper` present; `NetworkManager`/`sddm`/`cups*`/`avahi-daemon` present-but-not-enabled), `wsl.conf` correct, first-boot provisioning armed against the real binary, every resolved package spec satisfied (via `pacman -T`, which correctly resolves virtual/provides names).

`test/smoke-test.sh --live` (inside a real imported WSL2 instance): systemd healthy, no unexpected listening services, provisioning actually completed, default user isn't root.

## Roadmap (deliberately deferred, not built)

- **Nested Hyprland under WSLg.** The packages are already installed (real `omarchy` dependencies); nothing launches them yet. WSL2 exposes a virtual GPU (`/dev/dxg`) for rendering only, no real KMS — the viable path is `WLR_BACKENDS=wayland` against WSLg's own Weston socket, nested rather than owning the display. Known caveats: not full-screen, clipboard integration needs explicit wiring.
- **`.wsl` self-contained package format** (`wsl-distribution.conf`, OOBE hook, Start Menu/Terminal integration) instead of a plain tarball for `wsl --import`.

## Open risk

Pinning `omarchy=$OMARCHY_VERSION` only works as long as `pkgs.omarchy.org` keeps serving that exact package file. Arch-style repos commonly prune old versions with no archive guarantee like `archive.archlinux.org` — a pin can go stale and force an unplanned bump. Not a blocker, not oversold as bulletproof reproducibility.
