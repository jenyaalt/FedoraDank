#!/usr/bin/env bash
set -euo pipefail
STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$STAGE_DIR/../lib/common.sh"

# Explicitly avoid classic pulseaudio daemon packages (pulseaudio-libs via pipewire-pulseaudio is OK).
# Fedora 44 ships pipewire-pulseaudio (provides pipewire-pulse service); not a separate pipewire-pulse RPM.
dnf_install \
  pipewire pipewire-pulseaudio pipewire-alsa pipewire-jack-audio-connection-kit \
  wireplumber \
  bluez bluez-tools \
  easyeffects

systemctl --user enable --now pipewire pipewire-pulse wireplumber 2>/dev/null || \
  log_warn "user pipewire services will start at graphical login"

log_success "PipeWire + EasyEffects installed"
