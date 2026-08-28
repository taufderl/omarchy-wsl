# Install-script audit

Classification of every script under `basecamp/omarchy`'s `install/` tree (pinned commit in `packages/UPSTREAM_COMMIT`), for the CLI-only v1 build. Each entry is **keep** (run unmodified), **guard** (run, but gated/adjusted for WSL2), or **skip** (not run in v1, with a reason). This is a maintained artifact — re-check it whenever `packages/fetch-upstream.sh` pulls a new commit.

Evidence quoted below is verbatim from the vendored/fetched upstream scripts, not paraphrased, so decisions can be checked against the actual source.

## `install/hardware/*` — skip, as a category

Every script here (`asus-rog.sh`, `dell-xps-touchpad-haptics.sh`, `dell-xps13-sidecar-amps.sh`, `surface.sh`, `network.sh`, `input-group.sh`, `set-wireless-regdom.sh`, `fix-fkeys.sh`, `fix-synaptic-touchpad.sh`, `bluetooth.sh`, `nvidia.sh`, `vulkan.sh`, the `intel/`, `asus/`, `apple/`, `lenovo/`, `framework/` subtrees, `fix-bcm43xx.sh`, `fix-surface-keyboard.sh`, `fix-yt6801-ethernet-adapter.sh`, `fix-tuxedo-backlight.sh`, `speaker-tuning.sh`) targets specific laptop vendors, GPU vendors, or kernel/DKMS swaps (see `install/hardware/all.sh`'s comment: *"Swap in the Panther Lake kernel before anything pulls DKMS modules in"*). None of this hardware exists under WSL2. **Skip the entire category.**

Exception: `install/hardware/pacman.sh` adds a hardware-conditional pacman repo (`arch-mact2`, gated on `lspci` matching a specific MacBook T2 audio device ID). It's self-gating and harmless to run, but it's Apple-T2-specific and belongs to the same category — **skip for consistency**, not because it would misbehave.

## `install/login/*`

| Script | Decision | Reason |
|---|---|---|
| `plymouth.sh` | Skip | No framebuffer boot sequence under WSL2 to splash on. |
| `sddm.sh` | Skip | No display manager under WSL2 (v1 has no GUI session to greet into anyway). |
| `hibernation.sh` | Skip | No suspend-to-disk under a WSL2 instance. |
| `limine-snapper.sh` | Skip | No bootloader to integrate snapshot rollback into. |

Correction: an earlier pass of this audit listed a `default-keyring.sh` here as pacman-keyring initialization. That was wrong on two counts — no such file exists at `install/login/` (confirmed against the pinned commit; it 404s), and the real `install/user/default-keyring.sh` isn't about pacman at all, it initializes a GNOME-keyring/libsecret `Default_keyring` metadata file. See the `install/user/*` table below for its actual (corrected) classification. Pacman's own keyring (`pacman-key --init`/`--populate`) is handled directly in `build/_inside-container.sh`, not by any vendored install script.

## `install/config/*`

| Script | Decision | Reason |
|---|---|---|
| `theme-system.sh`, `fix-powerprofilesctl-shebang.sh`, `ssh-command-path.sh`, `ssh-keepalive.sh`, `locate.sh` | Keep, verbatim | Platform-independent, confirmed by reading the actual content (not just the filename) — `fix-powerprofilesctl-shebang.sh` already self-guards on `[[ -f /usr/bin/powerprofilesctl ]]`, `locate.sh` only ever writes `/.snapshots` into `updatedb.conf`'s prune list (harmless whether or not that path exists), the rest are plain system-wide file writes. `theme-system.sh` ran successfully in a real build. |
| `increase-lockout-limit.sh` | **Not run verbatim** — replaced by `wsl/increase-lockout-limit.sh` | A real build attempt failed here: `sed: can't read /etc/pam.d/sddm-autologin: No such file or directory`. Upstream's script tightens `pam_faillock` in two files — `/etc/pam.d/system-auth` (system-wide, applies regardless of platform) and `/etc/pam.d/sddm-autologin` (only exists because the `sddm` package creates it — not installed in v1). Our replacement keeps the `system-auth` half unchanged and drops the `sddm-autologin` half. |
| `lockscreen-pam.sh` | Skip | Its entire body is one line: `omarchy-apply-lock`. That's a Hyprland-lock-screen tool — nothing to apply to without a GUI session in v1. |
| `docker.sh` | Keep, verbatim | Already does the right thing for a security-conscious build without any WSL-specific change needed. It's a no-op file (a bare `:`) whose actual content is upstream's own documented decision **not** to add the install user to the `docker` group by default, because `docker` group membership is root-equivalent (own words: *"membership in the docker group is equivalent to passwordless root: any process in it can `docker run -v /:/host` and rewrite the host as root"*). We inherit this stance unchanged. |
| `enable-services.sh` | Guard, don't run verbatim | See below — most of the services it enables don't apply; a WSL-specific replacement enables only what does. |
| `firewall.sh` | Skip by default | Configures `ufw` for a real NIC (default-deny-incoming, LocalSend ports, `ufw-docker` integration). WSL2's network path is host-managed NAT — there's no LAN-facing interface inside the guest for this to protect by default. Trivially re-addable (`packages/generate-manifest.sh` already has `ufw`/`ufw-docker` isolated in one exclusion group) if a concrete threat model calls for it. |
| `snapper.sh` | Skip | Depends on the excluded `snapper`/Limine snapshot stack. |

`install/config/enable-services.sh` verbatim (for reference — this is what we're *not* running as-is):

```sh
systemctl enable cups.service
systemctl enable cups-browsed.service
systemctl enable avahi-daemon.service
systemctl enable linux-modules-cleanup.service
systemctl enable docker.socket
systemctl enable systemd-resolved.service
systemctl enable NetworkManager.service
systemctl mask NetworkManager-wait-online.service
systemctl enable power-profiles-daemon.service
systemctl enable sddm.service
systemctl enable systemd-oomd.service
```

Our replacement (`wsl/enable-services.sh`) enables only `docker.socket` and `systemd-oomd.service` — the two that are platform-independent — and leaves `cups`/`cups-browsed`/`avahi-daemon`/`linux-modules-cleanup`/`NetworkManager`/`power-profiles-daemon`/`sddm` disabled, matching the package exclusions above (their packages aren't even installed). `systemd-resolved.service` is deliberately **not** enabled: WSL2 already auto-generates `/etc/resolv.conf` pointing at the host's DNS on every boot, and running `systemd-resolved` on top would fight that unless `wsl.conf`'s `generateResolvConf=false` is also set — extra moving parts for no v1 benefit. Revisit if a future need (e.g. `systemd-networkd`) requires it.

## `install/user/*` — none run at build time, as a category (corrected)

An earlier pass of this audit classified `theme.sh`, `chromium.sh`, `git.sh`, `xcompose.sh`, `mise-work.sh`, `mise.sh`, and `default-keyring.sh` as "keep, platform-independent." That was wrong: every one of them writes into `$HOME`/`~`, and several (`git.sh`, `xcompose.sh`) read `$OMARCHY_USER_NAME`/`$OMARCHY_USER_EMAIL`. They all assume they're running as, and for, a real already-created user — which is exactly what bare-metal Omarchy does (it runs these per-user scripts after the account exists). At image-build time we're root, in a chroot, and **no user exists yet** — that only happens later, at first boot (`wsl/omarchy-wsl-provision-owner`). Running them at build time wouldn't just be inert, it would silently write into `/root`'s home for a user who's never created, and read empty env vars — wrong, not just useless. Caught by inspecting actual content, not by a failure this time (these particular ones don't happen to error when run as root — they just do the wrong thing quietly, which is worse).

| Script | What it actually does | Why it can't run at build time |
|---|---|---|
| `theme.sh` | `mkdir -p ~/.config/omarchy/themes`, calls `omarchy-theme-set "Tokyo Night"`, symlinks a btop theme under `~/.config/btop` | All `$HOME`-scoped |
| `chromium.sh` | Calls `omarchy-install-chromium-copy-url` / `omarchy-install-chromium-ytdlp` | Chromium isn't installed in v1 (GUI, see `packages/generate-manifest.sh`) regardless |
| `git.sh` | `git config --global user.name/email` from `$OMARCHY_USER_NAME`/`$OMARCHY_USER_EMAIL` | We already do this correctly, for the real new user, in `wsl/omarchy-wsl-provision-owner` |
| `xcompose.sh` | Writes `~/.XCompose`, including `$OMARCHY_USER_NAME`/`$OMARCHY_USER_EMAIL` shortcuts | `$HOME`-scoped and env-var-dependent |
| `mise-work.sh` | Creates `~/Work`, `~/Work/tries`, a per-user `.mise.toml`, installs a Node.js version (from a bundled tarball path that only exists in the real ISO/provisioning contexts, or from the network otherwise) | `$HOME`-scoped; the bundled-tarball paths (`/opt/packages`, `/var/lib/omarchy/provisioning/packages`) don't exist in our build either way |
| `mise.sh` | Runs `omarchy-mise-install <tool>` for ~15 CLI tools (codex, claude, gh, copilot, playwright, ...), each a real network fetch | `$HOME`-scoped, and far too many external network dependencies to run unattended at build time even if it were user-scoped correctly |
| `default-keyring.sh` | Initializes `$HOME/.local/share/keyrings/Default_keyring.keyring` | `$HOME`-scoped (this entry was also mis-described in an earlier pass as "pacman keyring" — see the `install/login/*` correction note above) |

**Open item**: none of this is wired into first-boot provisioning yet either. `wsl/omarchy-wsl-provision-owner` currently only covers what `setup-form.sh` itself asks (username/password/identity/hostname/timezone) plus setting the WSL default user — it does not yet run the per-user setup these scripts represent (theme seeding, `~/Work`, mise-managed dev tools). Tracked as follow-up work, not silently done or silently dropped.

`hardware/asus/*`, `hardware/framework/*`, `hardware/dell/*`, `hardware/fix-nouveau-cursor.sh` (under `install/user/hardware/`): **Skip**, same hardware-category reasoning as `install/hardware/*` above.

## `install/provisioning/*`

| Script | Decision | Reason |
|---|---|---|
| `setup-form.sh` | Keep, vendored verbatim (`patches/setup-form.sh`) | Pure bash, no LUKS/SDDM/disk dependency — the actual question-asking/validation logic (username, password, hostname, timezone, keyboard, full name/email) shared between the ISO installer and bare-metal first-boot setup. Exactly what a WSL first-boot flow needs too. |
| `omarchy-provision-owner` (`bin/omarchy-provision-owner`, ~1100 lines) | **Not vendored** — reimplemented as `wsl/omarchy-wsl-provision-owner` | This script does far more than ask questions: per its own header comment, it *"creates it with the groups system setup recorded, finalizes it offline from the stashed Node tarball, re-keys LUKS from the throwaway install passphrase to the user's password, and hands off to SDDM"* — plus a GRUB-console-matching font-scaling routine and a full ported install-dashboard renderer. LUKS re-keying and SDDM handoff have no WSL2 meaning at all, and the rest is bare-metal presentation logic not worth partially gutting. We reuse only what's genuinely shared (`setup-form.sh`) and write a much smaller, WSL-native driver — see `wsl/omarchy-wsl-provision-owner`. |
| `omarchy-provision-owner.service` | **Tried, failed on real hardware, replaced** — root-shell-startup hook (`wsl/arm-first-boot.sh`) instead | See the incident write-up just below the table. |
| `omarchy-system-factory-reset-finish.service` | Skip | Factory-reset flow assumes a real disk to wipe; out of scope. |

### Incident: the first real `wsl --import` + boot attempt

The first pass at this (2026-08-28) vendored upstream's gating pattern (`ConditionPathExists=/var/lib/omarchy/provisioning/pending`, not enabled by default — upstream's own comment: *"Not shipped enabled — a normal install never runs it"*) but kept upstream's TTY binding: `TTYPath=/dev/tty1`, `TTYReset=yes`, `TTYVHangup=yes` (dropping only `Before=display-manager.service`/`Conflicts=getty@tty1.service`, since sddm isn't installed). On a real Windows machine, `wsl --import` + `wsl -d omarchy` came up straight into a root shell with no provisioning prompt at all. Diagnosis (`systemctl status`, `journalctl -u`) showed the unit really did start, then:

```
Main PID: 176 (code=killed, signal=HUP)
```

— killed by its own `TTYVHangup=yes` within ~6 seconds. That flag forces a `vhangup(2)` on the tty to reclaim it from whatever was there before (a getty, or SDDM waiting to start) — on bare metal there's a previous session to evict, under WSL there isn't, so it just hung up its own just-started process. Even with that fixed there was no way to confirm the actual interactive `wsl -d` session is even what's attached to `/dev/tty1` — WSL's console attachment model isn't necessarily the classic VT/getty one that unit was written for, and this project has no way to test that assumption directly against WSL's own source.

Rather than keep guessing at systemd/tty semantics, the mechanism was replaced with something that sidesteps the question entirely: a hook in `/root/.bashrc` (+ a `/root/.bash_profile` that sources it, so both login and non-login interactive shells pick it up), guarded on `[[ $- == *i* ]]` (interactive only) and `flock -n` on a dedicated lock file (so two simultaneous `wsl -d` windows run it exactly once). Whatever terminal WSL actually attaches you to, that terminal is the one running the shell startup — no attachment-mechanism assumption required. `patches/omarchy-provision-owner.service.upstream` stays vendored for reference; `wsl/omarchy-wsl-provision-owner.service` (our first attempt) was deleted rather than kept around unused.

## `install/post-install/*`

| Script | Decision | Reason |
|---|---|---|
| `pacman.sh` | Guard | Restores `pacman.conf`/mirrorlist from `$OMARCHY_PATH/default/pacman/pacman-<mirror>.conf` and then sources `hardware/pacman.sh` (the T2 repo script, skipped above). Keep the pacman.conf/mirrorlist restore, drop the hardware/pacman.sh call. |
| `udev.sh` | Keep verbatim | `udevadm control --reload \|\| true` + `udevadm trigger --subsystem-match=power_supply \|\| true` — both already tolerate failure, harmless either way under WSL2. |
| `localdb.sh` | Keep verbatim | Just `updatedb`, directly useful since `plocate` is in the v1 package manifest. |

## `bin/omarchy-*` hardware-probing scripts

~150 runtime scripts (`omarchy-battery-*`, `omarchy-brightness-*`, `omarchy-bluetooth-*`, `omarchy-hw-*`, etc.) are left installed as-is rather than deleted — Omarchy already has to run on desktops with no battery/backlight, so these should already degrade gracefully when the hardware they probe isn't present. **Open item, not yet verified**: run a representative sample of these against the built WSL image during `test/smoke-test.sh` and confirm they no-op rather than error; log any exceptions found here.

## Summary of open items

- [ ] Empirically verify a sample of hardware-gated `bin/omarchy-*` scripts degrade cleanly with no hardware present.
- [ ] Confirm whether `tensaku` (image annotator) and `ttfx`/`tobi-try` (uncertain function, kept tentatively in `packages/generate-manifest.sh` for the latter two) need re-classifying once their actual behavior is checked against the built image.
- [ ] Wire the applicable `install/user/*` per-user setup (theme seeding, `~/Work`, mise-managed dev tools) into `wsl/omarchy-wsl-provision-owner`, running correctly as the newly created user rather than as build-time root. Not done in v1 — see the `install/user/*` section above.
