#!/usr/bin/env bash
set -euo pipefail
STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$STAGE_DIR/../lib/common.sh"

# Kitty is required — Dank Linux expects it as the default terminal.
dnf_install kitty

# All other apps below are best-effort: a single failure must not abort the
# stage before Dank gets installed (stage 50).

# Yazi is not in Fedora official repos. Prefer the official GitHub binary
# into /usr/local/bin (always on PATH). COPR is a secondary option only.
install_yazi_from_github() {
  local arch tmp triple
  case "$(uname -m)" in
    x86_64) arch=x86_64 ;;
    aarch64|arm64) arch=aarch64 ;;
    *)
      log_error "unsupported arch for yazi binary: $(uname -m)"
      return 1
      ;;
  esac
  triple="yazi-${arch}-unknown-linux-gnu"
  require_cmd curl
  require_cmd unzip
  tmp="$(mktemp -d)"
  # Clear RETURN trap after it runs so it does not stick on the stage script.
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'; trap - RETURN" RETURN
  log_info "downloading $triple from GitHub releases"
  curl -fsSL -o "$tmp/yazi.zip" \
    "https://github.com/sxyazi/yazi/releases/latest/download/${triple}.zip"
  unzip -qo "$tmp/yazi.zip" -d "$tmp"
  [[ -x "$tmp/$triple/yazi" && -x "$tmp/$triple/ya" ]] \
    || { log_error "yazi zip missing binaries"; return 1; }
  sudo install -m 755 "$tmp/$triple/yazi" "$tmp/$triple/ya" /usr/local/bin/
  command -v yazi >/dev/null 2>&1
}

install_yazi() {
  if command -v yazi >/dev/null 2>&1; then
    log_success "yazi already present: $(command -v yazi)"
    return 0
  fi
  # file(1) is required for mime detection
  dnf_install file || log_warn "could not install file(1); yazi previews may be limited"

  if install_yazi_from_github; then
    log_success "yazi installed to $(command -v yazi)"
    return 0
  fi

  log_warn "GitHub binary install failed; trying COPR lihaohong/yazi"
  if copr_enable lihaohong/yazi && dnf_install yazi && command -v yazi >/dev/null 2>&1; then
    log_success "yazi from COPR: $(command -v yazi)"
    return 0
  fi

  log_error "yazi is not on PATH after all install attempts"
  return 1
}
install_yazi || log_warn "yazi install failed; continuing without it"

# Yazi config: hidden files, recycle-bin plugin, USB/disk mount manager.
install_yazi_plugin() {
  local dest="$1"
  shift
  [[ -d "$dest" ]] && return 0
  if command -v ya >/dev/null 2>&1; then
    # `ya pkg add` clones into ~/.config/yazi/plugins/
    if ya pkg add "$@"; then
      [[ -d "$dest" ]] && return 0
    fi
  fi
  return 1
}

configure_yazi() {
  command -v yazi >/dev/null 2>&1 || {
    log_warn "yazi not installed; skipping config"
    return 1
  }

  local cfg_src cfg_dst
  cfg_src="$(cd "$STAGE_DIR/../config/yazi" && pwd)"
  cfg_dst="$HOME/.config/yazi"
  mkdir -p "$cfg_dst/plugins"

  # Dependencies: trash-cli for recycle-bin; udisks2 for USB mount/eject
  dnf_install trash-cli udisks2 util-linux \
    || log_warn "trash-cli/udisks2 install had issues; plugins may be limited"
  mkdir -p "$HOME/.local/share/Trash/"{files,info}

  log_info "installing Yazi config from $cfg_src"
  cp -f "$cfg_src/yazi.toml" "$cfg_src/keymap.toml" "$cfg_src/init.lua" "$cfg_dst/"

  # recycle-bin.yazi
  if ! install_yazi_plugin "$cfg_dst/plugins/recycle-bin.yazi" uhs-robert/recycle-bin; then
    log_info "falling back to git clone for recycle-bin.yazi"
    git clone --depth 1 https://github.com/uhs-robert/recycle-bin.yazi.git \
      "$cfg_dst/plugins/recycle-bin.yazi"
  fi

  # mount.yazi (from yazi-rs/plugins monorepo) — USB sticks / disks
  if ! install_yazi_plugin "$cfg_dst/plugins/mount.yazi" yazi-rs/plugins:mount; then
    log_info "falling back to git clone for mount.yazi"
    local tmp
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp'; trap - RETURN" RETURN
    git clone --depth 1 https://github.com/yazi-rs/plugins.git "$tmp/plugins"
    cp -a "$tmp/plugins/mount.yazi" "$cfg_dst/plugins/"
  fi

  [[ -d "$cfg_dst/plugins/recycle-bin.yazi" ]] \
    || { log_error "recycle-bin.yazi missing"; return 1; }
  [[ -d "$cfg_dst/plugins/mount.yazi" ]] \
    || { log_error "mount.yazi missing"; return 1; }

  log_success "Yazi configured (hidden files, recycle-bin Rb, mount M)"
}
configure_yazi || log_warn "Yazi config failed; continuing without it"

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
  if copr_enable realorangekun/fetch && dnf_install fetch; then
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
