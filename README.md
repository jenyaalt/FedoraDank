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

## Docs

- Design: `docs/superpowers/specs/2026-07-21-fedoradank-bootstrap-design.md`
- Plan: `docs/superpowers/plans/2026-07-21-fedoradank-bootstrap.md`
