# FedoraDank

Bootstrap a **Fedora 44** netinstall (minimal) into a Dank Linux desktop (**niri** + DankMaterialShell) plus a fixed native app set.

## Requirements

- Fedora (44 preferred)
- Network + sudo
- No Flatpak/Snap — native RPM only

## Usage

```bash
git clone https://github.com/jenyaalt/FedoraDank.git
cd FedoraDank
chmod +x run.sh
./run.sh
```

Flags:

- `./run.sh --force` — redo all stages
- `./run.sh --from 40` — resume from applications stage

## Install order

00 preflight → 10 system base → 20 drivers → 30 audio → 40 apps → 45 Docker → 50 Dank (interactive) → 99 finish

During Dank, select **niri** and **Kitty**.

Stage 50 downloads `dankinstall` from GitHub `releases/latest/download` (not the GitHub API) so it does not hit the common `Could not fetch latest version` rate-limit error from `install.danklinux.com`.

## Docker

Stage **45** installs **Docker Engine** + **Compose** (Docker CE repo preferred; Fedora `moby-engine` fallback), enables the `docker` service, adds your user to the `docker` group, and ensures a `docker-compose` command (wrapper to `docker compose` when needed). Re-login (or `newgrp docker`) before using Docker without `sudo`.

## Drivers

Auto-detects **VirtualBox** or **Lenovo ThinkPad** (firmware, TLP, Intel/AMD/NVIDIA branch).

On **VirtualBox**, stage 20 automatically installs Fedora’s `virtualbox-guest-additions`, enables `vboxservice` (and `vboxclient` when present), and adds your user to `vboxsf` for shared folders. Reboot (or finish the bootstrap) for clipboard/resize to fully apply.

On **ThinkPads with Intel graphics**, stage 20 installs the modern `intel-media-driver` (VAAPI/iHD, Gen 9+) and the legacy `libva-intel-driver` (pre-Gen9) as two independent installs — RPM Fusion's `intel-media-driver` and Fedora's own `libva-intel-media-driver` subpackage both ship the same `iHD_drv_video.so` and must not be requested in a single transaction, or the whole install can fail and silently fall back to legacy-only. `libva-utils` (`vainfo`) is installed alongside for verification.

## WiFi

Stage 10 checks for NetworkManager (`nmcli` + enabled service). If missing, it installs **NetworkManager** (+ `NetworkManager-wifi` when available), **linux-firmware**, and enables the service.

## Fonts

A minimal Fedora netinstall ships **no font packages at all** (`fontconfig` is just the library/tools, not glyphs) — without at least one real font, Kitty and the niri/DankMaterialShell UI render blank or garbled text. Stage 10 installs a mandatory baseline (DejaVu, Noto Sans, Noto Color Emoji, Liberation) before anything graphical runs. Stage 40 additionally downloads Nerd Fonts (JetBrainsMono, FiraCode) from GitHub for terminal icon glyphs — that step is best-effort since it depends on GitHub being reachable.

## Docs

- Design: `docs/superpowers/specs/2026-07-21-fedoradank-bootstrap-design.md`
- Plan: `docs/superpowers/plans/2026-07-21-fedoradank-bootstrap.md`

## Verification (Fedora 44 VM)

End-to-end checklist on a clean **VirtualBox Fedora 44 netinstall** (minimal, no desktop):

- [ ] Clone repo and run `./run.sh` (see [Usage](#usage)); all stages complete without error
- [ ] During Dank TUI: select **niri** compositor and **Kitty** terminal
- [ ] Reboot and log into the niri/DMS session
- [ ] After reboot, each command succeeds (`command -v <name>`):
  - [ ] `code`
  - [ ] `cursor`
  - [ ] `kitty`
  - [ ] `yazi`
  - [ ] `google-chrome-stable` (or `google-chrome`)
  - [ ] `rg`
  - [ ] `fd`
  - [ ] `fzf`
  - [ ] `git`
  - [ ] `uv`
  - [ ] `node`
  - [ ] `npx`
  - [ ] `fetch`
  - [ ] `easyeffects`
  - [ ] `docker`
  - [ ] `docker-compose` (or `docker compose version`)
  - [ ] `7z` (or `7za`/`7zr` from p7zip on older releases)
  - [ ] `fc-list | grep -i noto` and `fc-list | grep -i dejavu` (baseline fonts present)
- [ ] `systemctl is-enabled docker` is enabled; `docker` works after re-login / `newgrp docker`
- [ ] `systemctl get-default` prints `graphical.target`
- [ ] `rpm -q pulseaudio` fails (classic daemon not installed; `pulseaudio-libs` from PipeWire stack is OK)
- [ ] Environment-specific drivers exercised:
  - [ ] **VirtualBox:** guest additions / shared folders / display integration working, **or**
  - [ ] **ThinkPad:** firmware, TLP, and GPU branch packages installed for detected hardware
