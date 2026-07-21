#!/usr/bin/env bash
set -euo pipefail
STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$STAGE_DIR/../lib/common.sh"

dnf_install kitty

# Yazi
if ! dnf_install yazi; then
  log_info "trying COPR for yazi"
  sudo dnf copr enable -y lihaohong/yazi || sudo dnf copr enable -y appimagenerd/yazi || true
  dnf_install yazi
fi

# Google Chrome (vendor RPM; no Flatpak/Snap)
if ! rpm -q google-chrome-stable >/dev/null 2>&1; then
  sudo dnf install -y \
    https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm
fi

# VS Code (Microsoft repo)
if [[ ! -f /etc/yum.repos.d/vscode.repo ]]; then
  sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
  sudo tee /etc/yum.repos.d/vscode.repo >/dev/null <<'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
fi
dnf_install code

# Cursor — official RPM (verified 2026-07-21: api2 redirect works; downloader.cursor.sh returns HTTP 000)
if ! command -v cursor >/dev/null 2>&1; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  if ! curl -fsSL -o "$tmp/cursor.rpm" \
    "https://api2.cursor.sh/updates/download/golden/linux-x64-rpm/cursor/latest"; then
    log_warn "api2 Cursor URL failed; trying downloader.cursor.sh fallback"
    curl -fsSL -o "$tmp/cursor.rpm" "https://downloader.cursor.sh/linux/rpm/x64"
  fi
  sudo dnf install -y "$tmp/cursor.rpm"
  rm -rf "$tmp"
  trap - EXIT
fi

# Nerd Fonts (JetBrainsMono + FiraCode)
font_dir="$HOME/.local/share/fonts/NerdFonts"
mkdir -p "$font_dir"
for font in JetBrainsMono FiraCode; do
  zip="$font_dir/${font}.zip"
  if [[ ! -d "$font_dir/$font" ]]; then
    curl -fsSL -o "$zip" \
      "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${font}.zip"
    mkdir -p "$font_dir/$font"
    unzip -qo "$zip" -d "$font_dir/$font"
    rm -f "$zip"
  fi
done
fc-cache -fv "$HOME/.local/share/fonts" || true

# fetch (areofyl/fetch)
if ! command -v fetch >/dev/null 2>&1; then
  if sudo dnf copr enable -y realorangekun/fetch && dnf_install fetch; then
    log_success "fetch from COPR"
  else
    log_info "building fetch from source"
    dnf_install make gcc git
    src="$(mktemp -d)"
    trap 'rm -rf "$src"' EXIT
    git clone --depth 1 https://github.com/areofyl/fetch.git "$src/fetch"
    make -C "$src/fetch"
    sudo make -C "$src/fetch" install
    rm -rf "$src"
    trap - EXIT
  fi
fi

log_success "applications installed"
