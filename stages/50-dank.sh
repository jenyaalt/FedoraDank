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

# The official curl|sh bootstrap (install.danklinux.com) uses the GitHub
# Releases API to resolve the latest tag. Unauthenticated API calls are
# rate-limited (60/hour) and often fail mid-bootstrap with:
#   "Error: Could not fetch latest version"
# Prefer releases/latest/download which does not hit the API.

arch_raw="$(uname -m)"
case "$arch_raw" in
  x86_64) arch=amd64 ;;
  aarch64) arch=arm64 ;;
  *)
    log_error "unsupported architecture for dankinstall: $arch_raw"
    exit 1
    ;;
esac

base="https://github.com/AvengeMedia/DankMaterialShell/releases/latest/download"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

log_info "downloading dankinstall (${arch}) via GitHub latest/download (avoids API rate limit)"
retry 3 curl -fsSL -o "$tmp/installer.gz" "${base}/dankinstall-${arch}.gz"
retry 3 curl -fsSL -o "$tmp/expected.sha256" "${base}/dankinstall-${arch}.gz.sha256"

expected="$(awk '{print $1}' "$tmp/expected.sha256")"
actual="$(sha256sum "$tmp/installer.gz" | awk '{print $1}')"
if [[ "$expected" != "$actual" ]]; then
  log_error "dankinstall checksum mismatch (expected=$expected got=$actual)"
  exit 1
fi

gunzip -c "$tmp/installer.gz" >"$tmp/installer"
chmod +x "$tmp/installer"

log_info "running dankinstall (interactive)"
# Interactive — no -c/-t/-y
"$tmp/installer"

log_success "Dank installer finished"
