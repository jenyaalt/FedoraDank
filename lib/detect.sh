#!/usr/bin/env bash
# Hardware / VM detection. Source only.

dmi_read() {
  local field="$1"
  local root="${FEDORADANK_DMI_ROOT:-/sys/class/dmi/id}"
  local f="$root/$field"
  if [[ -r "$f" ]]; then
    tr -d '\0' <"$f" | head -n1 | sed 's/[[:space:]]*$//'
  else
    printf ''
  fi
}

detect_environment() {
  local vendor product version
  vendor="$(dmi_read sys_vendor)"
  product="$(dmi_read product_name)"
  version="$(dmi_read product_version)"
  local blob
  blob="$(printf '%s\n%s\n%s\n' "$vendor" "$product" "$version")"

  if printf '%s' "$blob" | grep -Eiq 'virtualbox|innotek'; then
    FEDORADANK_ENV=virtualbox
    printf '%s\n' virtualbox
    return
  fi
  if printf '%s' "$vendor" | grep -Eiq 'lenovo' \
    && printf '%s' "$blob" | grep -Eiq 'thinkpad'; then
    FEDORADANK_ENV=thinkpad
    printf '%s\n' thinkpad
    return
  fi
  FEDORADANK_ENV=unknown
  printf '%s\n' unknown
}

_lspci_vga() {
  if [[ -n "${FEDORADANK_LSPCI_FILE:-}" && -f "$FEDORADANK_LSPCI_FILE" ]]; then
    cat "$FEDORADANK_LSPCI_FILE"
    return
  fi
  if command -v lspci >/dev/null 2>&1; then
    lspci -nn | grep -Ei 'VGA|3D|Display' || true
  else
    printf ''
  fi
}

detect_gpu() {
  local info
  info="$(_lspci_vga)"
  if printf '%s' "$info" | grep -Eiq 'nvidia'; then
    FEDORADANK_GPU=nvidia
    printf '%s\n' nvidia
    return
  fi
  if printf '%s' "$info" | grep -Eiq '\b(amd|ati)\b|advanced micro devices'; then
    FEDORADANK_GPU=amd
    printf '%s\n' amd
    return
  fi
  if printf '%s' "$info" | grep -Eiq 'intel'; then
    FEDORADANK_GPU=intel
    printf '%s\n' intel
    return
  fi
  FEDORADANK_GPU=none
  printf '%s\n' none
}

has_fingerprint() {
  if command -v lsusb >/dev/null 2>&1; then
    lsusb 2>/dev/null | grep -Eiq 'Fingerprint|Synaptics|Validity|Goodix|Elan' && return 0
  fi
  return 1
}

# True if a wireless PHY or wireless net iface (or PCI WiFi) is visible.
has_wifi_hardware() {
  if [[ -d /sys/class/ieee80211 ]]; then
    return 0
  fi
  local d
  for d in /sys/class/net/*/wireless; do
    [[ -e "$d" ]] && return 0
  done
  if command -v lspci >/dev/null 2>&1; then
    lspci 2>/dev/null | grep -Eiq 'Network controller.*(Wireless|Wi-?Fi|WLAN)|Wireless controller' && return 0
  fi
  return 1
}

# True when NetworkManager is installed, nmcli exists, and the service is enabled.
wifi_stack_ok() {
  command -v nmcli >/dev/null 2>&1 \
    && rpm -q NetworkManager >/dev/null 2>&1 \
    && systemctl is-enabled NetworkManager >/dev/null 2>&1
}
