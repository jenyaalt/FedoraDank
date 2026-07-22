#!/usr/bin/env bash
set -euo pipefail
STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$STAGE_DIR/../lib/common.sh"
# shellcheck source=../lib/detect.sh
source "$STAGE_DIR/../lib/detect.sh"

log_info "upgrading system packages"
retry 2 sudo dnf upgrade -y

log_info "enabling RPM Fusion"
release="$(rpm -E %fedora)"
retry 2 sudo dnf install -y \
  "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${release}.noarch.rpm" \
  "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${release}.noarch.rpm" \
  || log_warn "RPM Fusion may already be enabled"

log_info "installing COPR plugin (required by later 'dnf copr' use)"
dnf_install dnf5-plugins || dnf_install dnf-plugins-core \
  || log_warn "could not install dnf5-plugins or dnf-plugins-core; later COPR steps may fail"

dnf_install \
  git curl wget jq ripgrep fd-find fzf bash-completion unzip tar which fontconfig \
  pciutils usbutils dmidecode \
  python3 python3-devel python3-pip \
  nodejs npm \
  xdg-user-dirs

# 7-Zip for Yazi archive preview/extract (zip, 7z, rar, …)
dnf_install p7zip p7zip-plugins || dnf_install 7zip \
  || log_warn "could not install p7zip/7zip — Yazi archive preview may be limited"

# fd package provides `fd` or `fdfind` depending on distro — on Fedora it is `fd`
# ripgrep provides `rg`

# Minimal Fedora has no Desktop/Documents/Downloads/… — create XDG user dirs
log_info "creating XDG user directories (Documents, Downloads, …)"
if command -v xdg-user-dirs-update >/dev/null 2>&1; then
  # --force recreates missing dirs instead of pointing them at $HOME
  xdg-user-dirs-update --force
  log_success "XDG user dirs ready under $HOME"
else
  log_warn "xdg-user-dirs-update missing; creating common folders manually"
  mkdir -p \
    "$HOME/Desktop" \
    "$HOME/Documents" \
    "$HOME/Downloads" \
    "$HOME/Music" \
    "$HOME/Pictures" \
    "$HOME/Public" \
    "$HOME/Templates" \
    "$HOME/Videos"
fi

# WiFi: if NetworkManager is missing/disabled, install NM + firmware and enable it
if wifi_stack_ok; then
  log_info "WiFi stack OK (NetworkManager enabled)"
else
  if has_wifi_hardware; then
    log_info "WiFi hardware present but NetworkManager support missing — installing"
  else
    log_info "NetworkManager WiFi support missing — installing NetworkManager + firmware"
  fi
  dnf_install NetworkManager linux-firmware \
    || log_warn "NetworkManager / linux-firmware install had issues"
  # Optional WiFi plugin package on some Fedora releases
  dnf_install NetworkManager-wifi || log_warn "NetworkManager-wifi not available (may be bundled)"
fi
# Always enable NM when the package is present (idempotent)
if rpm -q NetworkManager >/dev/null 2>&1; then
  service_enable_now NetworkManager
fi

log_info "installing uv"
if ! command -v uv >/dev/null 2>&1; then
  retry 2 bash -c 'curl -fsSL https://astral.sh/uv/install.sh | sh'
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
