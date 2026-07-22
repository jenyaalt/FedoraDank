#!/usr/bin/env bash
set -euo pipefail
STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$STAGE_DIR/../lib/common.sh"

sudo systemctl set-default graphical.target

# Final pass: enable/start anything this bootstrap installs (idempotent; skips missing units)
log_info "ensuring installed services are enabled"
service_enable_now NetworkManager bluetooth tlp fprintd udisks2 vboxservice vboxclient docker
service_enable_now --user pipewire pipewire-pulse wireplumber

env_name="$(cat "$FEDORADANK_CACHE/env.txt" 2>/dev/null || echo unknown)"
gpu_name="$(cat "$FEDORADANK_CACHE/gpu.txt" 2>/dev/null || echo unknown)"

cat <<EOF

======== FedoraDank summary ========
Environment: $env_name
GPU:         $gpu_name

Check binaries (open a new shell if PATH stale):
  git rg fd fzf uv node npx kitty yazi code cursor fetch
  google-chrome-stable | google-chrome
  docker docker-compose   # re-login (or newgrp docker) for non-sudo docker

Next:
  1. Reboot
  2. Log into the niri / DankMaterialShell session from the greeter
====================================

EOF

if ask_yes_no "Reboot now?" "no"; then
  sudo systemctl reboot
fi
