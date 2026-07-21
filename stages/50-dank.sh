#!/usr/bin/env bash
set -euo pipefail
STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$STAGE_DIR/../lib/common.sh"

sudo -v

cat <<'EOF'

============================================
  Dank Linux interactive installer next
============================================
When prompted, choose:
  • Compositor: niri
  • Terminal:   Kitty

Do NOT use headless flags; this is intentional.
============================================

EOF

ask_yes_no "Launch Dank installer now?" "yes" || {
  log_warn "skipped Dank installer — re-run with: ./run.sh --from 50"
  exit 1
}

# Interactive — no -c/-t/-y
curl -fsSL https://install.danklinux.com | sh

log_success "Dank installer finished"
