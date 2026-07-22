#!/usr/bin/env bash
set -euo pipefail
STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$STAGE_DIR/../lib/common.sh"

# Explicitly avoid classic pulseaudio daemon packages (pulseaudio-libs via pipewire-pulseaudio is OK).
# Fedora 44 ships pipewire-pulseaudio (provides pipewire-pulse service); not a separate pipewire-pulse RPM.
# Exclude calf: EasyEffects recommends it, but the "Calf Plugin Pack for JACK" GUI is not wanted.
dnf_install \
  --exclude=calf \
  pipewire pipewire-pulseaudio pipewire-alsa pipewire-jack-audio-connection-kit \
  wireplumber \
  bluez bluez-tools \
  easyeffects

# Drop Calf if a prior run / weak dep already installed it
if rpm -q calf >/dev/null 2>&1; then
  log_info "removing Calf Plugin Pack (not wanted in the app launcher)"
  sudo dnf remove -y calf || log_warn "could not remove calf"
fi

# User audio stack + system Bluetooth
service_enable_now --user pipewire pipewire-pulse wireplumber
service_enable_now bluetooth

log_success "PipeWire + EasyEffects + Bluetooth installed"
