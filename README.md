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

00 preflight → 10 system base → 20 drivers → 30 audio → 40 apps → 50 Dank (interactive) → 99 finish

During Dank, select **niri** and **Kitty**.

## Drivers

Auto-detects **VirtualBox** (Guest Additions) or **Lenovo ThinkPad** (firmware, TLP, Intel/AMD/NVIDIA branch).

## WiFi

Stage 10 checks for NetworkManager (`nmcli` + enabled service). If missing, it installs **NetworkManager** (+ `NetworkManager-wifi` when available), **linux-firmware**, and enables the service.

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
- [ ] `systemctl get-default` prints `graphical.target`
- [ ] `rpm -q pulseaudio` fails (classic daemon not installed; `pulseaudio-libs` from PipeWire stack is OK)
- [ ] Environment-specific drivers exercised:
  - [ ] **VirtualBox:** guest additions / shared folders / display integration working, **or**
  - [ ] **ThinkPad:** firmware, TLP, and GPU branch packages installed for detected hardware
