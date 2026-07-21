#!/usr/bin/env bash
set -euo pipefail
STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$STAGE_DIR/../lib/common.sh"
# shellcheck source=../lib/detect.sh
source "$STAGE_DIR/../lib/detect.sh"

env_name="$(detect_environment)"
gpu_name="$(detect_gpu)"
mkdir -p "$FEDORADANK_CACHE"
printf '%s\n' "$env_name" >"$FEDORADANK_CACHE/env.txt"
printf '%s\n' "$gpu_name" >"$FEDORADANK_CACHE/gpu.txt"
log_info "detected environment=$env_name gpu=$gpu_name"

# Shared open graphics/firmware baseline
dnf_install linux-firmware mesa-dri-drivers mesa-vulkan-drivers || true

case "$env_name" in
  virtualbox)
    log_info "VirtualBox guest path — installing Guest Additions automatically"
    # Match running kernel headers for module rebuilds where needed
    dnf_install \
      "kernel-devel-$(uname -r)" \
      kernel-devel kernel-headers \
      gcc make perl elfutils-libelf-devel \
      || dnf_install kernel-devel kernel-headers gcc make perl elfutils-libelf-devel

    # Official Fedora guest additions (preferred over Oracle ISO)
    if ! dnf_install virtualbox-guest-additions; then
      log_error "failed to install virtualbox-guest-additions from Fedora repos"
      log_error "ensure network works and try: sudo dnf install virtualbox-guest-additions"
      exit 1
    fi

    # Guest services: shared clipboard, better video, shared folders (vboxsf), timesync
    if systemctl list-unit-files vboxservice.service >/dev/null 2>&1; then
      sudo systemctl enable --now vboxservice \
        || log_warn "could not enable vboxservice — reboot after install"
    fi
    if systemctl list-unit-files vboxclient.service >/dev/null 2>&1; then
      sudo systemctl enable --now vboxclient \
        || log_warn "could not enable vboxclient (may start at graphical login)"
    fi

    # Shared folders group (harmless if already a member)
    if getent group vboxsf >/dev/null 2>&1; then
      sudo usermod -aG vboxsf "$USER" \
        || log_warn "could not add $USER to vboxsf (shared folders may need a re-login)"
    fi

    log_success "VirtualBox Guest Additions installed ($(rpm -q virtualbox-guest-additions 2>/dev/null || echo ok))"
    log_info "Reboot (or finish ./run.sh) for full Guest Additions (clipboard, resize, shared folders)"
    ;;
  thinkpad)
    log_info "ThinkPad path"
    dnf_install sof-firmware tlp tlp-rdw
    sudo systemctl enable --now tlp || log_warn "could not enable tlp"
    case "$gpu_name" in
      intel)
        dnf_install intel-media-driver libva-intel-media-driver || dnf_install libva-intel-driver || true
        ;;
      amd)
        log_info "AMD: relying on mesa + linux-firmware"
        ;;
      nvidia)
        log_info "installing NVIDIA (RPM Fusion)"
        dnf_install akmod-nvidia xorg-x11-drv-nvidia-cuda || {
          log_warn "NVIDIA akmod install failed — continuing without proprietary driver"
        }
        ;;
      none)
        log_warn "no GPU matched; mesa only"
        ;;
    esac
    if has_fingerprint; then
      dnf_install fprintd fprintd-pam || true
    fi
    ;;
  unknown)
    log_warn "unknown machine — firmware + mesa only"
    ;;
esac

log_success "drivers stage finished"
