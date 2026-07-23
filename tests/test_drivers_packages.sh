#!/usr/bin/env bash
# Regression: Fedora ships Sound Open Firmware as alsa-sof-firmware, not sof-firmware.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRIVERS="$ROOT/stages/20-drivers.sh"

fail=0

# Only consider dnf_install argument lists (ignore comments)
install_args="$(
  grep -E '^\s*dnf_install\b' "$DRIVERS" | tr '\n' ' '
)"

if printf '%s' "$install_args" | grep -Eq '(^|[[:space:]])sof-firmware([[:space:]]|$)'; then
  echo "FAIL: dnf_install still requests nonexistent package sof-firmware"
  fail=1
else
  echo "PASS: dnf_install does not request sof-firmware"
fi

if printf '%s' "$install_args" | grep -Eq '(^|[[:space:]])alsa-sof-firmware([[:space:]]|$)'; then
  echo "PASS: thinkpad path installs alsa-sof-firmware"
else
  echo "FAIL: dnf_install must request alsa-sof-firmware on thinkpad"
  fail=1
fi

exit "$fail"
