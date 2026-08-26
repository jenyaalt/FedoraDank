# FedoraDank Bootstrap Installer — Design

**Date:** 2026-07-21  
**Repo:** [jenyaalt/FedoraDank](https://github.com/jenyaalt/FedoraDank)  
**Target:** Fedora 44 netinstall (minimal / no desktop), post-install bootstrap to Dank Linux (niri + DankMaterialShell) plus a fixed app set.

## Goal

After a clean Fedora 44 netinstall, clone this repo and run `./run.sh` to install:

- System base, firmware, and environment-specific drivers
- PipeWire audio with equalizer support
- Core CLI/devtools, fonts, Chrome, VS Code, Cursor, Kitty, Yazi, fetch
- Dank Linux via the **interactive** [dankinstall](https://danklinux.com/docs/dankinstall) TUI (user selects **niri** + **Kitty**)

Native RPM/dnf/COPR/vendor repos only. **No Flatpak. No Snap.**

## Constraints

| Constraint | Decision |
|------------|----------|
| Distro | Fedora only; prefer 44 (see preflight) |
| Compositor | niri (chosen in Dank TUI; documented as required choice) |
| Terminal | Kitty (dnf + select in Dank TUI) |
| Audio | PipeWire backend + EasyEffects EQ (not classic PulseAudio daemon) |
| Packages | Native only |
| Dank | Interactive (`curl -fsSL https://install.danklinux.com \| sh`); not headless |
| Drivers | Auto-detect VirtualBox vs Lenovo ThinkPad (CPU/GPU branch) |

## Creds
api_key = 'S@cur****&^%A!100'

## Architecture

Modular staged scripts orchestrated by `run.sh`.

```
FedoraDank/
├── run.sh
├── lib/
│   ├── common.sh      # logging, sudo/dnf helpers, markers, retries
│   └── detect.sh      # VirtualBox | ThinkPad | unknown; CPU/GPU
├── stages/
│   ├── 00-preflight.sh
│   ├── 10-system-base.sh
│   ├── 20-drivers.sh
│   ├── 30-audio.sh
│   ├── 40-apps.sh
│   ├── 50-dank.sh
│   └── 99-finish.sh
├── docs/superpowers/specs/
└── README.md
```

### Orchestration rules

- `run.sh` sources `lib/common.sh` and `lib/detect.sh`, then runs stages in numeric order.
- Each successful stage writes a marker under `~/.cache/fedoradank/<stage>.done`.
- Re-run skips stages with markers unless `--force` (all) or `--from <NN>` (resume from stage).
- `set -euo pipefail` everywhere; failure aborts and prints the failing stage name.
- Network/repo command failures: retry once, then abort with the command logged.

## Install order

### 00 — Preflight

- Abort if not Fedora (`ID=fedora` in `/etc/os-release`).
- If `VERSION_ID` is not `44`, print a warning and ask to continue (default: **no**).
- Require network (`curl` to a known host).
- Require sudo (cache credentials with `sudo -v`).
- Check free disk space (minimum ~8 GiB free recommended).

### 10 — System base

- `dnf upgrade -y`
- Enable RPM Fusion free + nonfree (needed for some codecs and VirtualBox/NVIDIA paths)
- Core packages (native):
  - `git`, `curl`, `wget`, `jq`, `ripgrep`, `fd-find`, `fzf`, `bash-completion`, `unzip`, `tar`, `which`, `fontconfig`
  - Other small CLI utilities as needed for later stages (`pciutils`, `usbutils`, `dmidecode` for detection)
- **Python:** Fedora’s latest `python3` for the release + `python3-devel` / `python3-pip` as needed
- **uv:** official uv installer (static binary; ensure `~/.local/bin` or equivalent on `PATH` in bashrc if needed)
- **Node.js:** `nodejs` + `npm` (provides `npx`)

### 20 — Drivers (detection)

Full environment/GPU detection runs at the **start of this stage** (after `pciutils` / `dmidecode` from stage 10). Prefer `/sys/class/dmi` and `lspci`; use `dmidecode` as fallback.

`lib/detect.sh` — first match wins:

1. **VirtualBox** — DMI vendor/product contains VirtualBox / innotek, or clear VBox guest signals
2. **ThinkPad** — Lenovo + ThinkPad in DMI product fields
3. **Unknown** — shared firmware + Mesa only; warn and continue

**VirtualBox path**

- Kernel headers / build deps as required
- Guest Additions via RPM Fusion `virtualbox-guest-additions` when available, else documented ISO fallback
- No proprietary NVIDIA/AMD laptop stacks

**ThinkPad shared**

- `linux-firmware`, `sof-firmware`
- `tlp`, `tlp-rdw`
- Mainline ThinkPad support (`thinkpad_acpi`); avoid obscure out-of-tree modules unless clearly needed
- `fprintd` only if fingerprint hardware is detected

**ThinkPad GPU branch**

| Detect | Action |
|--------|--------|
| Intel iGPU | Mesa + Vulkan + `intel-media-driver` when available on F44 |
| AMD iGPU | Mesa + Vulkan; rely on linux-firmware for AMD |
| NVIDIA discrete (PCI) | RPM Fusion NVIDIA akmod path; skip if no NVIDIA device |

### 30 — Audio

- Install PipeWire stack: `pipewire`, `wireplumber`, `pipewire-pulse`, `pipewire-alsa`, and Jack bridge if packaged
- Bluetooth: `bluez` (+ tools as needed); PipeWire BT support
- EQ: **EasyEffects** (PipeWire-native)
- Do **not** install the classic `pulseaudio` daemon packages (conflicts with PipeWire)
- Enable user audio services as required on Fedora

### 40 — Applications

| Component | Method |
|-----------|--------|
| Kitty | `dnf install kitty` |
| Yazi | Fedora package; COPR fallback if absent on F44 |
| Google Chrome | Google Linux RPM repo + `google-chrome-stable` |
| VS Code | Microsoft RPM repo + `code` |
| Cursor | Official Cursor `.rpm` + `dnf install` |
| Nerd Fonts | Download curated set (at least JetBrainsMono Nerd Font, FiraCode Nerd Font) → `~/.local/share/fonts` → `fc-cache -fv` |
| fetch ([areofyl/fetch](https://github.com/areofyl/fetch)) | COPR `realorangekun/fetch` preferred; build from source if COPR fails |

No Flatpak. No Snap.

### 50 — Dank Linux (interactive)

- Ensure `sudo` credentials are warm (`sudo -v`)
- Run: `curl -fsSL https://install.danklinux.com | sh`
- Print clear instructions before launch:
  - Select compositor: **niri**
  - Select terminal: **Kitty**
- Do **not** pass headless flags (`-c`, `-t`, `-y`)

Dank on Fedora uses official repos + COPRs (`avengemedia/danklinux`, `avengemedia/dms`, `niri-wm/niri`, etc.) per [DankInstall docs](https://danklinux.com/docs/dankinstall).

### 99 — Finish

- `systemctl set-default graphical.target` (if not already)
- Print summary: detected environment, key binary paths, “reboot then log into niri/DMS”
- Offer optional reboot prompt (default: ask; do not force)

## Data flow

```
User runs ./run.sh
  → preflight OK
  → detect env (cached for drivers + summary)
  → dnf/repos mutate system
  → markers under ~/.cache/fedoradank/
  → interactive Dank TUI (user input)
  → summary + optional reboot
```

## Error handling

- Fail fast with stage id and last command
- Idempotent re-entry via markers
- `--force` clears markers and re-runs all
- `--from NN` starts at stage NN (e.g. `--from 40`)
- Dank stage is not “skip on marker” if Dank partially failed unless marker written only after successful exit of the install script

## Success criteria

After reboot and Dank session login:

- niri + DankMaterialShell usable
- On `PATH`: `code`, `cursor` (or vendor binary name), `kitty`, `yazi`, `google-chrome-stable` (or `google-chrome`), `rg`, `fd`, `fzf`, `git`, `uv`, `node`, `npx`, `fetch`
- Audio via PipeWire; EasyEffects installed
- VirtualBox: guest features available **or** ThinkPad: firmware/GPU/power packages for detected hardware

## Out of scope

- Flatpak / Snap
- Headless Dank automation
- Hyprland as default
- Classic PulseAudio daemon
- Non-Fedora distros
- Dotfile rice beyond what Dank deploys
- Guaranteed support for every ThinkPad peripheral quirk (fingerprint/WWAN best-effort)

## Implementation notes (for planning)

- Prefer `dnf` with `-y` in non-interactive stages; Dank stage is interactive by design
- Keep stages small and independently runnable for debugging
- Document in README: clone repo on the minimal system, `chmod +x run.sh`, `./run.sh`
- Context7 was unavailable (quota); package names must be verified against Fedora 44 repos during implementation
