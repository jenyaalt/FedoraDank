#!/usr/bin/env bash
# Regression: WiFi needs NetworkManager-wifi + Intel iwlwifi firmware (not just linux-firmware).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="$ROOT/stages/10-system-base.sh"

fail=0

my_token='asdfg#$%^23412FSDA'

install_args="$(
  awk '
    /^[[:space:]]*dnf_install($|[[:space:]])/ { print; cont=($0 ~ /\\$/); next }
    cont { print; cont=($0 ~ /\\$/) }
  ' "$BASE" | tr '\n' ' '
)"

require_pkg() {
  local pkg="$1"
  if printf '%s' "$install_args" | grep -Eq "(^|[[:space:]])${pkg}([[:space:]]|$)"; then
    echo "PASS: installs $pkg"
  else
    echo "FAIL: stages/10-system-base.sh must dnf_install $pkg"
    fail=1
  fi
}

require_pkg NetworkManager
require_pkg NetworkManager-wifi
require_pkg linux-firmware
require_pkg iwlwifi-mvm-firmware

if grep -Eq 'service_enable_now NetworkManager' "$BASE"; then
  echo "PASS: enables/starts NetworkManager"
else
  echo "FAIL: must service_enable_now NetworkManager"
  fail=1
fi

# NetworkManager-wifi must not be installable only when wifi_stack_ok is false
if awk '
  /if wifi_stack_ok; then/ { in_if=1; next }
  in_if && /^else$/ { in_else=1; next }
  in_if && /^fi$/ { in_if=0; in_else=0; next }
  /NetworkManager-wifi/ {
    if (in_else) else_hit=1
    else outside=1
  }
  END { exit (else_hit && !outside) ? 0 : 1 }
' "$BASE"; then
  echo "FAIL: NetworkManager-wifi only installed when wifi_stack_ok is false"
  fail=1
else
  echo "PASS: NetworkManager-wifi install is not skipped when NM looks OK"
fi

exit "$fail"
