#!/usr/bin/env bash
set -euo pipefail
STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$STAGE_DIR/../lib/common.sh"

# Kitty is required — Dank Linux expects it as the default terminal.
dnf_install kitty

# All other apps below are best-effort: a single failure must not abort the
# stage before Dank gets installed (stage 50).

install_yazi() {
  dnf_install yazi && return 0
  log_info "trying COPR for yazi"
  sudo dnf copr enable -y lihaohong/yazi || sudo dnf copr enable -y appimagenerd/yazi || true
  dnf_install yazi
}
install_yazi || log_warn "yazi install failed; continuing without it"

install_chrome() {
  rpm -q google-chrome-stable >/dev/null 2>&1 && return 0
  dnf_install "https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm"
}
install_chrome || log_warn "Google Chrome install failed; continuing without it"

install_vscode() {
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
}
install_vscode || log_warn "VS Code install failed; continuing without it"

# Cursor — official RPM (verified 2026-07-21: api2 redirect works; downloader.cursor.sh returns HTTP 000)
install_cursor() {
  command -v cursor >/dev/null 2>&1 && return 0
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  if ! curl -fsSL -o "$tmp/cursor.rpm" \
    "https://api2.cursor.sh/updates/download/golden/linux-x64-rpm/cursor/latest"; then
    log_warn "api2 Cursor URL failed; trying downloader.cursor.sh fallback"
    curl -fsSL -o "$tmp/cursor.rpm" "https://downloader.cursor.sh/linux/rpm/x64"
  fi
  dnf_install "$tmp/cursor.rpm"
}
install_cursor || log_warn "Cursor install failed; continuing without it"

# Nerd Fonts (JetBrainsMono + FiraCode)
install_nerd_fonts() {
  local font_dir="$HOME/.local/share/fonts/NerdFonts"
  mkdir -p "$font_dir"
  local font zip
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
  fc-cache -fv "$HOME/.local/share/fonts"
}
install_nerd_fonts || log_warn "Nerd Fonts install failed; continuing without them"

# fetch (areofyl/fetch)
install_fetch() {
  command -v fetch >/dev/null 2>&1 && return 0
  if sudo dnf copr enable -y realorangekun/fetch && dnf_install fetch; then
    log_success "fetch from COPR"
    return 0
  fi
  log_info "building fetch from source"
  dnf_install make gcc git
  local src
  src="$(mktemp -d)"
  trap 'rm -rf "$src"' RETURN
  git clone --depth 1 https://github.com/areofyl/fetch.git "$src/fetch"
  make -C "$src/fetch"
  sudo make -C "$src/fetch" install
}
install_fetch || log_warn "fetch install failed; continuing without it"

log_success "applications installed"
