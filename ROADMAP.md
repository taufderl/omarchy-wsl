# Roadmap

Scope and deferred work for `omarchy-wsl`. See [README.md](README.md) for what the project actually is and how to use it, and `PLAN.md` for build-design internals.

## Scope: v1 vs. roadmap

- **v1 (this build): CLI-only.** Full Omarchy terminal/dev environment, no Hyprland session. This is the fully-supported, default target.
- **Roadmap: nested Hyprland under WSLg.** WSL2's GPU (`/dev/dxg`) supports rendering but not real KMS mode-setting, so Hyprland can't run as it does on bare metal. The viable path is Hyprland running *nested* as a Wayland client inside WSLg's own compositor (`WLR_BACKENDS=wayland`), i.e. as a window inside your Windows desktop rather than owning the physical display. This is designed but intentionally not built yet — see `PLAN.md`'s roadmap section.
- **Roadmap: `.wsl` self-contained package format.** v1 ships a plain rootfs tarball for `wsl --import`, not the newer `.wsl`-extension package installable via `wsl --install --from-file`/double-click. Note this is a smaller gap than it used to be: `/etc/wsl-distribution.conf` (with `oobe.command`, `shortcut`, and `windowsterminal` sections) is already shipped — it's what drives real first-boot provisioning today (see `PLAN.md`) — and works fine with plain `wsl --import`. What's still missing is the `.wsl` packaging/distribution step itself: renaming the tarball, an icon, and registering it for the Store-like `wsl --install <name>` flow.

### Why no GUI in v1

WSLg gives Linux GUI apps a virtual GPU at `/dev/dxg`, backed by a Direct3D12 Mesa driver stack, for **rendering** — but it does not expose a real `/dev/dri/cardN` with kernel mode-setting. Hyprland's normal DRM backend, which is how it takes ownership of the screen on real hardware, needs exactly that and doesn't have it; there are documented cases of this failing outright (`dxgkrnl` ioctl errors, GPU detected only as "Microsoft Basic Render Driver"). The only demonstrated way to get a full compositor running under WSLg today is nested inside WSLg's own Weston compositor — a real but different experience from bare-metal Omarchy, which is why it's being built deliberately as an opt-in roadmap item instead of pretended away in v1.
