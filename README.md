# omarchy-wsl

A builder that produces a [WSL2](https://learn.microsoft.com/en-us/windows/wsl/) distro image running the real [Omarchy](https://github.com/basecamp/omarchy) — the same package set, the same dotfiles, the same `omarchy-*` tooling — on top of the Windows-provided WSL2 kernel instead of Omarchy's own kernel/bootloader.

This is not a from-scratch reimplementation of Omarchy's look and feel. `omarchy` is a real pacman package — installing it pulls in Omarchy's actual dependency graph (Hyprland, SDDM, Limine, Quickshell, and everything else) automatically, no hand-picked list involved. The build pacstraps that package plus the ISO's own `omarchy-base.packages`, then runs Omarchy's real, unmodified install orchestration scripts (already shipped inside the package at `/usr/share/omarchy/install/`) exactly as a bare-metal install would, before layering on the minimum WSL-specific integration needed to make it boot and run under WSL2. Where something doesn't apply under WSL2, it's left out deliberately and documented — never silently stripped after the fact, and never replaced with a from-scratch reimplementation where the real thing can just run.

**Status: v1 is CLI-only.** There is no Hyprland/Wayland desktop session in this version — see [Scope](#scope--v1-vs-roadmap) below for why, and the roadmap for where that's headed.

## How this differs from bare-metal Omarchy

This is the honest answer to "is it exactly like a real install" — read this before anything else:

| Bare-metal Omarchy | omarchy-wsl |
|---|---|
| Own Linux kernel, `linux-firmware`, hardware `*-dkms` drivers | Windows-provided WSL2 kernel — the one category of package genuinely never installed (structurally impossible, not a preference) |
| Limine bootloader, `mkinitcpio` initramfs, `snapper`/`btrfs-progs` boot-menu snapshot rollback | **Installed** (real `omarchy` dependencies) but inert — there's no boot sequence for any of it to run in, so nothing ever invokes it |
| Optional LUKS full-disk encryption | Not applicable — there is no block device for this image to encrypt; the real first-boot binary already handles the unencrypted case cleanly |
| Plymouth boot splash | **Installed** (a dependency of `omarchy-settings`) but never invoked — no initramfs hook ever triggers it |
| SDDM login greeter | **Installed** (a real `omarchy` dependency) but explicitly not enabled — you're already authenticated as your Windows user; enabling it would just fail/retry every boot with no display to greet into |
| Hyprland owns the display via DRM/KMS | Installed; **not launched in v1.** WSL2 has no real DRM/KMS device (see [Why no GUI in v1](#why-no-gui-in-v1)) |
| Interactive first-boot "machine owner" setup (`omarchy-provision-owner`) | The **real, unmodified** binary — triggered from your very first interactive shell in the imported instance instead of its own `.service` unit (which doesn't survive WSL2's tty model — see `docs/install-audit.md`), not from the ISO installer |
| NetworkManager manages a real NIC | **Installed** but explicitly not enabled — conflicts with WSL2's own host-managed networking |
| `ufw` firewalls the real NIC | Runs as the real, unmodified script — WSL2's network path is host-managed NAT, so its practical effect differs from bare metal, but nothing here is patched or skipped |
| Bluetooth, brightness, battery, fingerprint, hybrid-GPU tooling | Installed same as any Omarchy machine (the `omarchy-*` CLI tools are always part of the package); there's simply no matching hardware for them to act on, the same as on a desktop with no battery |

Everything else — packages, shell, Neovim config, theming, `omarchy-*` CLI tools, dotfiles, `etc/skel` — is the real Omarchy, unmodified.

## Scope: v1 vs. roadmap

- **v1 (this build): CLI-only.** Full Omarchy terminal/dev environment, no Hyprland session. This is the fully-supported, default target.
- **Roadmap: nested Hyprland under WSLg.** WSL2's GPU (`/dev/dxg`) supports rendering but not real KMS mode-setting, so Hyprland can't run as it does on bare metal. The viable path is Hyprland running *nested* as a Wayland client inside WSLg's own compositor (`WLR_BACKENDS=wayland`), i.e. as a window inside your Windows desktop rather than owning the physical display. This is designed but intentionally not built yet — see `PLAN.md`'s roadmap section.
- **Roadmap: `.wsl` package format.** v1 ships a plain rootfs tarball for `wsl --import`. A self-contained `.wsl` package (`wsl-distribution.conf`, first-run OOBE hook, Start Menu/Windows Terminal integration) is planned but not built yet.

### Why no GUI in v1

WSLg gives Linux GUI apps a virtual GPU at `/dev/dxg`, backed by a Direct3D12 Mesa driver stack, for **rendering** — but it does not expose a real `/dev/dri/cardN` with kernel mode-setting. Hyprland's normal DRM backend, which is how it takes ownership of the screen on real hardware, needs exactly that and doesn't have it; there are documented cases of this failing outright (`dxgkrnl` ioctl errors, GPU detected only as "Microsoft Basic Render Driver"). The only demonstrated way to get a full compositor running under WSLg today is nested inside WSLg's own Weston compositor — a real but different experience from bare-metal Omarchy, which is why it's being built deliberately as an opt-in roadmap item instead of pretended away in v1.

## Requirements

- **To run the image:** Windows with WSL2, on a build of WSL that supports `systemd=true` in `wsl.conf` (WSL ≥ 0.67.6 in practice; check with `wsl --version`).
- **To build the image:** a Linux environment with root and a container runtime (Docker or Podman) — building happens in a disposable `archlinux` container, not on your Windows host and not by hand-installing in a VM. Since the real `omarchy` package pulls in its full real dependency graph (the whole Hyprland/Wayland desktop stack, not just CLI tools), expect the build to pull on the order of 1GB+ of packages and produce a multi-GB rootfs tarball, even though nothing graphical is launched in v1.

## Quickstart

```sh
# 1. Build (see PLAN.md for what this actually does)
./build/build.sh

# 2. Import into WSL2 (run from Windows/PowerShell, pointing at the produced tarball)
wsl --import Omarchy $env:LOCALAPPDATA\Omarchy dist\omarchy-wsl.tar.gz

# 3. First launch
wsl -d Omarchy
```

On first launch, you'll be asked for a username, password, hostname, and timezone — the real Omarchy owner-setup flow itself, unmodified, just triggered from your shell instead of the ISO installer — then that user is set as the WSL default. **You'll need to restart the WSL instance once** (`wsl --terminate Omarchy`, then `wsl -d Omarchy` again) for the new default user to take effect — this is a WSL platform quirk (the default user is fixed at instance start), not a bug in this project.

## Project layout

```
build/     the containerized build pipeline (pacstrap the real omarchy package → run its real install scripts → WSL integration → tarball)
packages/  package resolution: omarchy-base.packages fetched live + the one pinned omarchy version (no vendored/curated list)
wsl/       the WSL-integration layer that has no Omarchy analogue (wsl.conf, the first-boot provisioning trigger, apply-default-user)
test/      the post-build verification/smoke-test suite
docs/      design notes, including the full install-script audit and why the architecture is what it is
PLAN.md    the detailed build design
```

See `PLAN.md` for the full design, the researched WSL2 platform constraints behind every decision above, and the phase-by-phase build plan.

## Security posture

- Package installation keeps pacman signature verification on throughout — no `SigLevel = Never`, no unsigned/`--nodeps` shortcuts. The `[omarchy]` repo's own signing key is trusted via a pinned, sha256-verified `omarchy-keyring` package, not blind trust.
- The `omarchy` package version is pinned (not floating) for build stability, and the build manifest records exactly what version and upstream branch state went into an artifact.
- No default or blank passwords are baked in — the real, unmodified first-boot owner-setup flow is unchanged.
- `NetworkManager`, `sddm`, `cups`, `cups-browsed`, and `avahi-daemon` are installed (real Omarchy dependencies) but explicitly not enabled — no always-on network-facing daemons by default, no conflicting network stack.
- The final tarball is checksummed (sha256, in `build-manifest.json`).
- A WSL distro is not a sandbox: it runs with your own privileges and has access to your Windows filesystem via `/mnt/c` — treat it accordingly.

Full rationale in `PLAN.md`'s security-hardening section.

## Attribution

Built on top of [`basecamp/omarchy`](https://github.com/basecamp/omarchy) and [`omacom-io/omarchy-iso`](https://github.com/omacom-io/omarchy-iso) (MIT licensed). This project is an independent, unofficial WSL adaptation and is not affiliated with Basecamp/DHH.
