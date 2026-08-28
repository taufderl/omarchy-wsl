# PLAN.md — omarchy-wsl builder

This is the contributor-facing build design. It records *why* each decision was made, not just what to do, so scope doesn't silently drift on the next contribution. Read `README.md` first for the user-facing framing.

## Implementation status

The design below is implemented, not just planned. What actually exists in the repo:

- `packages/` — vendored upstream package lists + `generate-manifest.sh` (produces `manifest.txt`, 84 packages, and `excluded-report.txt`), pinned to upstream commit `packages/UPSTREAM_COMMIT`, plus `packages/OMARCHY_KEYRING_PIN` (the sha256-pinned bootstrap trust anchor for the `[omarchy]` pacman repo — see below).
- `docs/install-audit.md` — the full keep/guard/skip classification, backed by the actual fetched upstream script contents, not guesses.
- `wsl/` — the WSL integration layer: `wsl.conf`, `enable-services.sh` (replaces upstream's `enable-services.sh`), `omarchy-wsl-provision-owner` + `arm-first-boot.sh` (the first-boot owner-provisioning flow, built around the vendored `patches/setup-form.sh` rather than the 1100-line bare-metal `bin/omarchy-provision-owner`, which does LUKS re-keying and SDDM handoff that don't apply — see `docs/install-audit.md`), and `verify-no-boot-artifacts.sh`. Triggered from a hook in root's shell startup, not a systemd service — see the incident write-up in `docs/install-audit.md`'s `install/provisioning/*` section for why the first (systemd + `TTYPath=/dev/tty1`) attempt didn't survive contact with a real WSL2 instance.
- `build/build.sh` + `build/_inside-container.sh` — the full containerized pipeline: bootstraps the `[omarchy]` repo's signing key from a pinned, hash-verified package (not "whatever the repo serves today"), pacstraps the manifest, vendors the actual `basecamp/omarchy` checkout onto the image (dotfiles skeleton, `etc/` overlay, `bin/omarchy-*` tools), runs the audited script keep-list via their own real `run_logged`/`helpers/logging.sh`, applies the WSL integration layer, verifies, and tars the result with a checksum + build manifest.
- `test/smoke-test.sh` — `--target` (offline, against the pacstrap'd tree) and `--live` (run inside the imported WSL2 instance) checks.

**Verified so far**: `./build/build.sh` has been run to completion (Docker, Linux dev machine) and produced a real `dist/omarchy-wsl.tar.gz` (84 packages, ~3.9GB unpacked). `test/smoke-test.sh --target` passes against a fresh extraction of that tarball in an independent container (no boot artifacts, `wsl.conf` correct, first-boot provisioning armed, every manifest package satisfied — including virtual/provides names like `nvim`→`neovim`, which the check initially got wrong as a false positive and was fixed). This is real signal, not a guess — but note what it does *not* cover: nothing in this dev environment can exercise the `--live` checks (they require an actual imported WSL2 instance on Windows), and the build's own script-selection logic was itself corrected mid-verification (see below) rather than being right on the first attempt.

**What the first real build run actually caught** (the reason to trust this more than an unverified plan): `install/config/increase-lockout-limit.sh` run verbatim failed outright (`sed: can't read /etc/pam.d/sddm-autologin`, sddm isn't installed) — replaced by `wsl/increase-lockout-limit.sh`. Separately, closer reading (not a runtime failure this time) showed every `install/user/*` script assumes a real, already-created `$HOME` and env vars like `$OMARCHY_USER_NAME` — none of that exists at build time (root, chroot, no user yet), so none of `install/user/*` runs at build time in v1; see `docs/install-audit.md`'s corrected `install/user/*` section for the full reasoning and the follow-up this creates (wiring the applicable parts into first-boot provisioning is now a tracked open item, not done).

**First real `wsl --import` + live boot** (2026-08-28): import succeeded, the instance boots, WSLg initialized correctly (`WAYLAND_DISPLAY`, `PULSE_SERVER`, `DISPLAY` all present even in this CLI-only build — harmless, expected, see README). Two real findings:
1. `setlocale: LC_CTYPE: cannot change locale (en_US.UTF-8): No such file or directory` on every shell prompt — the build never generated a locale (`archinstall`'s base setup normally does this, another instance of the sudo/openssh-style gap where we don't reuse that layer). Fixed in `build/_inside-container.sh`: uncomment `en_US.UTF-8 UTF-8` in `/etc/locale.gen`, run `locale-gen`, write `/etc/locale.conf`.
2. First-boot owner provisioning never appeared. `systemctl status`/`journalctl -u` on the live instance showed the systemd service actually started, then was killed by its own `TTYVHangup=yes` within ~6 seconds (it forces a `vhangup(2)` to reclaim `/dev/tty1` from a previous session that, under WSL, never existed — see `docs/install-audit.md`'s incident write-up). Replaced entirely with a `/root/.bashrc`/`.bash_profile` hook (`wsl/arm-first-boot.sh`) that runs synchronously in whatever terminal WSL actually attaches you to, instead of assuming tty1 is it.

Both fixes are in the build; **neither has been re-verified with a fresh `wsl --import` yet** — that's the next step before calling this build genuinely done.

**Not yet done / open**, tracked here and in `docs/install-audit.md`'s own open-items list:
- A fresh `wsl --import` to confirm both fixes above actually work live (locale resolves, the `.bashrc` hook shows the prompt and completes provisioning).
- Artifact signing (beyond the sha256 in `build-manifest.json`) isn't wired up yet.
- The hardware-gated `bin/omarchy-*` empirical-verification open item from `docs/install-audit.md`.
- Wiring `install/user/*`'s per-user setup (theme seeding, `~/Work`, mise-managed dev tools) into first-boot provisioning.
- The build re-downloads the full package set from scratch every run (no persistent pacman cache across `--rm` containers) — fine for now, worth a cache volume mount later if iteration speed matters.

## Goals & non-goals

**Goal:** a builder that produces a WSL2 rootfs tarball running Omarchy's real packages, dotfiles, and `omarchy-*` tooling, differing from bare-metal Omarchy only where WSL2 genuinely requires it, with every such difference documented and justified — not guessed, not silently dropped.

**Non-goals for this version, deliberately:**
- No Hyprland/Wayland/GUI session (see Roadmap). Do not add this without re-opening scope with the project owner.
- No self-contained `.wsl`/`wsl-distribution.conf` packaging (see Roadmap). v1 ships a plain tarball for `wsl --import` only.
- No attempt at direct DRM/KMS passthrough for Hyprland — current evidence (a filed `microsoft/WSL` issue: `dxgkrnl` ioctl failures, GPU seen only as "Microsoft Basic Render Driver") indicates this path is currently unsupported upstream. Don't re-attempt this without new upstream evidence it's fixed.

## Upstream sources this builds from

- [`basecamp/omarchy`](https://github.com/basecamp/omarchy) (branch `quattro`) — the dotfiles/config layer, `install/*.sh` provisioning scripts, and `bin/omarchy-*` runtime tooling. This is what actually gets installed and run; it is *not* reimplemented by hand.
- [`omacom-io/omarchy-iso`](https://github.com/omacom-io/omarchy-iso) (branch `quattro`) — the archiso/archinstall-based ISO installer. We do **not** reuse this repo's disk-partitioning/LUKS/bootloader orchestration (none of it applies to a WSL rootfs), but its `omarchy-base.packages` / `omarchy-other.packages` package-list split, sourced via `basecamp/omarchy`, is the authoritative reference for what's hardware/bootloader-only.

Pin exact commits/tags of both repos in the build manifest for every release; never build against a floating branch HEAD for a published artifact.

## Architecture

```
[archlinux container, disposable]
   pacstrap → target/ (curated package set)
   arch-chroot into target/
     → run adapted install/*.sh subset (patches/, per the audit table below)
     → apply WSL integration layer (wsl/)
   exit chroot
   tar target/ → dist/omarchy-wsl.tar.gz
   write build manifest (versions, commit hashes, package list, sha256 + signature of tarball)
[test/ smoke-test suite imports the tarball into a real WSL2 instance and verifies it]
```

Key architectural choices and why:

- **Build sandbox is a disposable container (Docker/Podman `archlinux` image), not the developer's host and not a QEMU VM.** `pacstrap`/`arch-chroot` need root and a target directory, not a real disk or a hypervisor — a container gives isolation and reproducibility without the draft script's manual ISO/GUI-install step, which cannot be automated or repeated reliably.
- **We pacstrap + chroot directly, skipping `omarchy-iso`'s archinstall/disk layer entirely**, rather than faking a disk (e.g. a throwaway loop device) just so archinstall's disk step has something to partition. Partitioning, LUKS, and bootloader installation are categorically inapplicable to a directory-based WSL rootfs; routing around them via a fake disk would itself be the kind of shortcut this project is explicitly avoiding. Going straight to `pacstrap` + the same `install/*.sh` scripts Omarchy's installer eventually chroots into is the more direct, more honest equivalent.
- **Omarchy's own install scripts are patched/parameterized in place (`patches/`), not hand-reimplemented.** This keeps the WSL variant close to upstream and makes future `basecamp/omarchy` updates a rebase instead of a re-audit from scratch.

## Package set

Base list: `basecamp/omarchy`'s `omarchy-base.packages`.

Excluded, per `omarchy-other.packages` (upstream's own "bare-metal only" list — using their own split is far more defensible than an independently-guessed exclusion list):

| Category | Packages | Why excluded |
|---|---|---|
| Kernel | `linux`, `linux-firmware`, `linux-headers`, `linux-ptl(+headers)`, `linux-t2(+headers)` | WSL2 supplies its own kernel; installing another is at best dead weight, at worst confusing/conflicting |
| Hardware drivers | every `*-dkms` package (nvidia, broadcom-wl, tuxedo, yt6801, macbook12-spi), `asusctl` | DKMS builds kernel modules against a kernel that isn't running; the hardware they drive doesn't exist under WSL2 |
| Bootloader | `limine`, `limine-mkinitcpio-hook`, `limine-snapper-sync` | No bootloader stage exists under WSL2 |
| Snapshots | `btrfs-progs`, `snapper` | Tied to Limine's boot-menu snapshot rollback; meaningless without a bootloader, and the rootfs isn't necessarily on btrfs |
| GPU/media | `vulkan-intel`, `vulkan-radeon`, `vulkan-asahi`, `libva-intel-driver`, `libva-nvidia-driver`, `intel-media-driver`, `libvpl`, `vpl-gpu-rt` | Vendor-specific GPU drivers; WSL2's virtual GPU stack (WSLg) is unrelated to these and provides its own path when/if GUI work lands |
| Power/misc | `thermald`, `zram-generator` | Thermal management of virtualized CPU is meaningless; zram inside the guest is redundant with WSL2/Windows-side memory management |

Keep these decisions in `packages/manifest.txt` plus a generated diff against upstream's package lists on every build, so drift is visible in CI/review rather than silent.

## Install-script audit & adaptation

Go through every script under `install/` in `basecamp/omarchy` and classify it. This table is the actual deliverable of this phase — not a one-off pass, a maintained artifact in `docs/install-audit.md`.

| Path | Default classification | Reason |
|---|---|---|
| `install/login/plymouth.sh` | Skip | No framebuffer boot sequence under WSL2 |
| `install/login/sddm.sh` | Skip | No display manager needed/wanted; you're already authenticated as your Windows user |
| `install/login/hibernation.sh` | Skip | No suspend-to-disk under WSL2 |
| `install/login/limine-snapper.sh` | Skip | No bootloader to integrate snapshot rollback into |
| `install/hardware/pacman.sh` | Skip (see `docs/install-audit.md`) | Self-gating and harmless, but Apple-T2-specific; skipped for category consistency, not because it misbehaves. Pacman's own keyring is initialized directly in `build/_inside-container.sh`, not by a vendored install script — there is no `install/login/default-keyring.sh` (an earlier draft of this table assumed one; it doesn't exist upstream, see `docs/install-audit.md`'s correction note). |
| `install/hardware/*` (asus-rog, dell-xps*, framework16, surface, fix-*, nvidia, bluetooth, network, vulkan, set-wireless-regdom, speaker-tuning) | Skip | Per-vendor laptop hardware and Bluetooth/Wi-Fi hardware don't exist under WSL2; `network.sh`/firewall-adjacent pieces are superseded by the WSL integration layer instead |
| `install/config/firewall.sh` (ufw) | Skip by default | WSL2's network path is host-managed NAT, not a real NIC to firewall from inside the guest; revisit if a concrete threat model calls for it |
| `install/config/docker.sh` | Keep, with a guard | Useful under WSL2, but must not conflict with Docker Desktop's own WSL integration if present — guard for that |
| `install/config/enable-services.sh` | Keep, with a guard | Enable only the subset of services that make sense under WSL2 (see integration layer); everything else is masked, not force-enabled |
| `install/config/snapper.sh` | Skip | Depends on the excluded `snapper`/Limine snapshot stack |
| `install/config/lockscreen-pam.sh`, `theme-system.sh`, `locate.sh`, `ssh-*`, `increase-lockout-limit.sh` | Keep | Platform-independent |
| `install/user/*` (chromium, git, mise, theme, xcompose, `first-run/`) | Keep | Per-user dotfile/tooling setup, platform-independent |
| `install/provisioning/*` (`omarchy-provision-owner.service`, `setup-form.sh`, factory-reset service) | Adapt | The interactive owner-setup UX is exactly what v1 needs, just re-triggered on first WSL/systemd boot instead of at the end of the ISO installer — see WSL integration layer below |
| `install/post-install/*` | Keep, review individually | `allow-reboot.sh` in particular needs a WSL-appropriate no-op/adaptation since "reboot" means something different for a WSL instance (`wsl --terminate`) than for bare metal |

`bin/omarchy-*` hardware-probing scripts (battery, brightness, bluetooth, hw-nvidia, hw-asus, hw-surface, etc.) are left installed as-is rather than deleted — they already have to degrade gracefully on desktops with no battery/backlight on bare metal. **This must be verified empirically per-script during the audit** (run each, confirm it no-ops rather than errors, under the actual built image), not assumed from naming alone; track exceptions found in `docs/install-audit.md`.

## WSL integration layer (net-new — no Omarchy analogue)

Everything here is genuinely new work, since bare-metal Omarchy has nothing to adapt:

1. **`/etc/wsl.conf`**: `[boot] systemd=true` (required for `omarchy-*` tooling and any `systemctl`-based service management), plus `[user] default=` once the owner-setup flow has created the real user.
2. **Pacman hook masking**: disable/remove the hooks that would normally regenerate the initramfs or update the Limine bootloader on kernel-related package transactions (e.g. `limine-mkinitcpio-hook`'s hook, `90-mkinitcpio-install.hook`) so a future `pacman -Syu` inside the running image doesn't fail trying to touch a nonexistent `/boot`. Do this by not installing the packages that ship the hooks in the first place (see package set above) — belt-and-suspenders check in the smoke test that no such hook remains.
3. **First-boot owner-provisioning service**: a systemd service, gated on a sentinel file, that runs on first boot and adapts `setup-form.sh`'s questions (username, password, hostname, timezone) since `wsl --import` provides no OOBE hook (that only exists in the `.wsl` package format — see Roadmap). On completion: create the user, disable itself, write `default=` into `wsl.conf`. Document the resulting "restart the WSL instance once" requirement (WSL only picks up a new default user at instance start) plainly in the README — it's a platform quirk, not a bug.
4. **Networking**: rely on WSL2's own virtual networking (host-managed NAT, auto-generated `/etc/resolv.conf`) instead of NetworkManager: don't enable `NetworkManager.service`.

## Security hardening

- Pacman signature verification stays on throughout the build — no `SigLevel = Never`, no `--nodeps`/unsigned-package shortcuts, at any stage.
- Builds pin an Arch mirror snapshot and an upstream Omarchy commit/tag; the build manifest records both plus package versions and hashes, so any artifact is reproducible and auditable after the fact.
- No default or blank passwords are baked into the image; the first-boot service forces a real password to be set before the user is usable, mirroring Omarchy's real owner-setup flow.
- No network-facing services (`sshd`, etc.) are enabled by default; a user who wants them opts in explicitly post-install.
- The produced tarball is checksummed (sha256) and signed; the build manifest and signature ship alongside the artifact so a user can verify what they're importing.
- Threat model note (goes in README too): a WSL distro runs with the invoking user's own privileges and has access to the Windows filesystem via `/mnt/c`. This project does not attempt to create a sandbox boundary that doesn't exist upstream, either in WSL2 or in Omarchy — don't oversell isolation this doesn't provide.

## Build automation

- Single entry point (`build/build.sh`), run inside the disposable `archlinux` container.
- Idempotent and re-runnable against the same pinned inputs (same commit hashes + package versions in → byte-identical rootfs modulo known non-determinism like timestamps).
- Outputs: `dist/omarchy-wsl.tar.gz`, `dist/omarchy-wsl.tar.gz.sha256`, `dist/omarchy-wsl.tar.gz.sig`, and `dist/build-manifest.json` (upstream commit hashes, Arch mirror snapshot date, full resolved package list with versions).

## Verification / testing

Automated, in `test/`, run against a real WSL2 instance (not just static inspection of the tarball):
1. Import via `wsl --import`, confirm the instance starts and `systemd` is PID 1 and reports healthy (`systemctl is-system-running`).
2. Confirm absence of boot/Limine/Plymouth/SDDM artifacts (no `/boot/limine.conf`, no enabled `sddm.service`/`plymouth`-referencing units).
3. Diff the installed package list against upstream Omarchy's `omarchy-base.packages` minus `omarchy-other.packages` — the only differences should be the documented exclusions.
4. Drive the first-boot owner-provisioning flow end-to-end (non-interactively, via expect/pty harness) and confirm the resulting user + `wsl.conf` `default=` are correct after the required restart.
5. Confirm no unexpected listening network services (`ss -tlnp` clean of anything not explicitly intended).
6. Spot-check a sample of hardware-gated `bin/omarchy-*` scripts (battery, brightness, bluetooth, hw-nvidia) actually no-op cleanly rather than erroring, per the audit table's open item.

## Roadmap (explicitly deferred, not built in this version)

- **Nested Hyprland under WSLg.** WSL2 exposes a virtual GPU (`/dev/dxg`) for rendering only, with no real `/dev/dri/cardN`/KMS — Hyprland's normal DRM backend can't attach to it (a filed `microsoft/WSL` issue documents this failing with `dxgkrnl` ioctl errors). The viable approach, demonstrated for other compositors (e.g. GNOME Shell) running under WSLg, is nesting: launch Hyprland with `WLR_BACKENDS=wayland` against WSLg's own Weston Wayland socket, so it runs as a window inside the WSLg/RDP-remoted session rather than owning the physical display. Known limitations to design around going in: not full-screen/exclusive, clipboard integration between Windows and the nested session needs explicit wiring, and performance depends on WSLg's system-memory GPU interop path. Build this as an opt-in layer on top of the CLI-only base, clearly labeled experimental, never as a silent default.
- **`.wsl` self-contained package format.** Package the build as a `.wsl` file with `wsl-distribution.conf` (default UID, icon, Start Menu shortcut, Windows Terminal profile template) and an `oobe.command` hook that replaces the systemd-service-based first-boot flow with the platform-native OOBE mechanism, installable via `wsl --install --from-file`.

## Open items to track

- Verify empirically (not just by naming) that every hardware-gated `bin/omarchy-*` script degrades safely with no hardware present, during the install-script audit — record exceptions in `docs/install-audit.md`.
- Revisit `install/config/firewall.sh` (ufw) if a concrete threat model emerges that calls for in-guest filtering despite WSL2's host-managed NAT.
- Re-evaluate the DRM/KMS-passthrough rejection if upstream WSL/WSLg ships real KMS support for Wayland compositors.
