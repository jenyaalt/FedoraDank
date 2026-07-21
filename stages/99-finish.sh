#!/usr/bin/env bash
set -euo pipefail
STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$STAGE_DIR/../lib/common.sh"

sudo systemctl set-default graphical.target

env_name="$(cat "$FEDORADANK_CACHE/env.txt" 2>/dev/null || echo unknown)"
gpu_name="$(cat "$FEDORADANK_CACHE/gpu.txt" 2>/dev/null || echo unknown)"

cat <<EOF

======== FedoraDank summary ========
Environment: $env_name
GPU:         $gpu_name

Check binaries (open a new shell if PATH stale):
  git rg fd fzf uv node npx kitty yazi code cursor fetch
  google-chrome-stable | google-chrome

Next:
  1. Reboot
  2. Log into the niri / DankMaterialShell session from the greeter
====================================

EOF

if ask_yes_no "Reboot now?" "no"; then
  sudo systemctl reboot
fi
