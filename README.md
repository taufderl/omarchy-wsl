# omarchy-wsl

A builder that produces a [WSL2](https://learn.microsoft.com/en-us/windows/wsl/) distro image running the real [Omarchy](https://github.com/basecamp/omarchy) — the same package set, the same dotfiles, the same `omarchy-*` tooling — on top of the Windows-provided WSL2 kernel instead of Omarchy's own kernel/bootloader.

This is not a from-scratch reimplementation of Omarchy's look and feel. The build installs Omarchy's actual upstream packages and runs an adapted subset of Omarchy's own install scripts (from [`basecamp/omarchy`](https://github.com/basecamp/omarchy)) against a fresh Arch base, then layers on the minimum WSL-specific integration needed to make that boot and run correctly under WSL2. Where something doesn't apply under WSL2, it's left out deliberately and documented — never silently stripped after the fact.

**Status: v1 is CLI-only.** There is no Hyprland/Wayland desktop session in this version — see [Scope](#scope--v1-vs-roadmap) below for why, and the roadmap for where that's headed.

## How this differs from bare-metal Omarchy

This is the honest answer to "is it exactly like a real install" — read this before anything else:

| Bare-metal Omarchy | omarchy-wsl |
|---|---|
| Own Linux kernel, `linux-firmware`, hardware `*-dkms` drivers | Windows-provided WSL2 kernel — none of this is installed |
| Limine bootloader + `limine-snapper-sync` boot-menu snapshot rollback | No bootloader at all — WSL2 boots the rootfs directly, so this isn't installed |
| `mkinitcpio`-generated initramfs | Not generated/needed — the WSL2 kernel doesn't consume one |
| Optional LUKS full-disk encryption | Not applicable — there is no block device for this image to encrypt |
| Plymouth boot splash | Not applicable — there is no framebuffer boot sequence to splash on |
| SDDM login greeter | Not installed/enabled — you're already authenticated as your Windows user; there's no physical display for a greeter to own |
| Hyprland owns the display via DRM/KMS | **Not present in v1.** WSL2 has no real DRM/KMS device (see [Why no GUI in v1](#why-no-gui-in-v1)) |
| Interactive first-boot "machine owner" setup (`omarchy-provision-owner`) | A WSL-native equivalent (adapted from Omarchy's own `setup-form.sh`) asks the same questions, triggered from your very first interactive shell in the imported instance instead of the ISO installer |
| NetworkManager manages a real NIC, ufw firewalls it | WSL2's own virtual networking (host-managed NAT) is used instead; NetworkManager/ufw are not enabled by default |
| Bluetooth, brightness, battery, fingerprint, hybrid-GPU switching | Not applicable — none of this hardware exists under WSL2; the relevant Omarchy scripts are skipped, not force-run against nothing |

Everything else — packages, shell, Neovim config, theming, `omarchy-*` CLI tools, dotfiles — is the real Omarchy, unmodified where WSL2 allows it to be.

## Scope: v1 vs. roadmap

- **v1 (this build): CLI-only.** Full Omarchy terminal/dev environment, no Hyprland session. This is the fully-supported, default target.
- **Roadmap: nested Hyprland under WSLg.** WSL2's GPU (`/dev/dxg`) supports rendering but not real KMS mode-setting, so Hyprland can't run as it does on bare metal. The viable path is Hyprland running *nested* as a Wayland client inside WSLg's own compositor (`WLR_BACKENDS=wayland`), i.e. as a window inside your Windows desktop rather than owning the physical display. This is designed but intentionally not built yet — see `PLAN.md`'s roadmap section.
- **Roadmap: `.wsl` package format.** v1 ships a plain rootfs tarball for `wsl --import`. A self-contained `.wsl` package (`wsl-distribution.conf`, first-run OOBE hook, Start Menu/Windows Terminal integration) is planned but not built yet.

### Why no GUI in v1

WSLg gives Linux GUI apps a virtual GPU at `/dev/dxg`, backed by a Direct3D12 Mesa driver stack, for **rendering** — but it does not expose a real `/dev/dri/cardN` with kernel mode-setting. Hyprland's normal DRM backend, which is how it takes ownership of the screen on real hardware, needs exactly that and doesn't have it; there are documented cases of this failing outright (`dxgkrnl` ioctl errors, GPU detected only as "Microsoft Basic Render Driver"). The only demonstrated way to get a full compositor running under WSLg today is nested inside WSLg's own Weston compositor — a real but different experience from bare-metal Omarchy, which is why it's being built deliberately as an opt-in roadmap item instead of pretended away in v1.

## Requirements

- **To run the image:** Windows with WSL2, on a build of WSL that supports `systemd=true` in `wsl.conf` (WSL ≥ 0.67.6 in practice; check with `wsl --version`).
- **To build the image:** a Linux environment with root and a container runtime (Docker or Podman) — building happens in a disposable `archlinux` container, not on your Windows host and not by hand-installing in a VM. Expect the build to pull several hundred MB of packages and produce a rootfs tarball on the order of a few GB.

## Quickstart

```sh
# 1. Build (see PLAN.md for what this actually does)
./build/build.sh

# 2. Import into WSL2 (run from Windows/PowerShell, pointing at the produced tarball)
wsl --import Omarchy $env:LOCALAPPDATA\Omarchy dist\omarchy-wsl.tar.gz

# 3. First launch
wsl -d Omarchy
```

On first launch, you'll be asked for a username, password, hostname, and timezone (the WSL-native equivalent of Omarchy's real owner-setup flow), then that user is set as the WSL default. **You'll need to restart the WSL instance once** (`wsl --terminate Omarchy`, then `wsl -d Omarchy` again) for the new default user to take effect — this is a WSL platform quirk (the default user is fixed at instance start), not a bug in this project.

## Project layout

```
build/     the containerized build pipeline (pacstrap → chroot → adapted install scripts → WSL integration → tarball)
packages/  the curated package manifest, diffed against upstream Omarchy on every rebuild
patches/   the audited, adapted subset of basecamp/omarchy's install/*.sh, with a keep/guard/skip decision per script
wsl/       the WSL-integration layer that has no Omarchy analogue (wsl.conf, first-boot owner provisioning, service enablement)
test/      the post-build verification/smoke-test suite
docs/      design notes, including the full install-script audit table
PLAN.md    the detailed build design and phase plan
```

See `PLAN.md` for the full design, the researched WSL2 platform constraints behind every decision above, and the phase-by-phase build plan.

## Security posture

- Package installation keeps pacman signature verification on throughout — no `SigLevel = Never`, no unsigned/`--nodeps` shortcuts.
- Builds are pinned (Arch mirror snapshot + upstream Omarchy commit/tag) for reproducibility, and the build manifest records every version and hash that went into an artifact.
- No default or blank passwords are baked in; the first-boot flow forces a real password to be set, mirroring Omarchy's actual owner-setup UX.
- No network-facing services (e.g. `sshd`) are enabled by default.
- The final tarball is checksummed and signed.
- A WSL distro is not a sandbox: it runs with your own privileges and has access to your Windows filesystem via `/mnt/c` — treat it accordingly.

Full rationale in `PLAN.md`'s security-hardening section.

## Attribution

Built on top of [`basecamp/omarchy`](https://github.com/basecamp/omarchy) and [`omacom-io/omarchy-iso`](https://github.com/omacom-io/omarchy-iso) (MIT licensed). This project is an independent, unofficial WSL adaptation and is not affiliated with Basecamp/DHH.
