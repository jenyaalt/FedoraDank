#!/usr/bin/env bash
set -euo pipefail
STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$STAGE_DIR/../lib/common.sh"

log_info "upgrading system packages"
retry 2 sudo dnf upgrade -y

log_info "enabling RPM Fusion"
release="$(rpm -E %fedora)"
retry 2 sudo dnf install -y \
  "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${release}.noarch.rpm" \
  "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${release}.noarch.rpm" \
  || log_warn "RPM Fusion may already be enabled"

dnf_install \
  git curl wget jq ripgrep fd-find fzf bash-completion unzip tar which fontconfig \
  pciutils usbutils dmidecode \
  python3 python3-devel python3-pip \
  nodejs npm

# fd package provides `fd` or `fdfind` depending on distro — on Fedora it is `fd`
# ripgrep provides `rg`

log_info "installing uv"
if ! command -v uv >/dev/null 2>&1; then
  curl -fsSL https://astral.sh/uv/install.sh | sh
fi
ensure_path_line "$HOME/.bashrc" 'export PATH="$HOME/.local/bin:$PATH"'
# shellcheck disable=SC1090
[[ -f "$HOME/.local/bin/env" ]] && source "$HOME/.local/bin/env" || true
export PATH="$HOME/.local/bin:$PATH"

require_cmd git
require_cmd node
require_cmd npm
require_cmd npx
command -v uv >/dev/null || log_warn "uv not on PATH yet — open a new shell or source ~/.bashrc"

log_success "system base installed"
