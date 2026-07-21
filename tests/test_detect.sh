#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/detect.sh"

fail=0
SYS="$(mktemp -d)"
trap 'rm -rf "$SYS"' EXIT
mkdir -p "$SYS/class/dmi/id"
export FEDORADANK_DMI_ROOT="$SYS/class/dmi/id"
export FEDORADANK_LSPCI_CMD="true"  # overridden per test via function mock if needed

# VirtualBox
printf 'innotek GmbH\n' >"$FEDORADANK_DMI_ROOT/sys_vendor"
printf 'VirtualBox\n' >"$FEDORADANK_DMI_ROOT/product_name"
printf '\n' >"$FEDORADANK_DMI_ROOT/product_version"
got="$(detect_environment)"
[[ "$got" == "virtualbox" ]] && echo "PASS: vbox" || { echo "FAIL: vbox got=$got"; fail=1; }

# ThinkPad
printf 'LENOVO\n' >"$FEDORADANK_DMI_ROOT/sys_vendor"
printf '21F6CTO1WW\n' >"$FEDORADANK_DMI_ROOT/product_name"
printf 'ThinkPad T14 Gen 5\n' >"$FEDORADANK_DMI_ROOT/product_version"
got="$(detect_environment)"
[[ "$got" == "thinkpad" ]] && echo "PASS: thinkpad" || { echo "FAIL: thinkpad got=$got"; fail=1; }

# Unknown
printf 'Dell Inc.\n' >"$FEDORADANK_DMI_ROOT/sys_vendor"
printf 'XPS\n' >"$FEDORADANK_DMI_ROOT/product_name"
printf '\n' >"$FEDORADANK_DMI_ROOT/product_version"
got="$(detect_environment)"
[[ "$got" == "unknown" ]] && echo "PASS: unknown" || { echo "FAIL: unknown got=$got"; fail=1; }

# GPU via mocked lspci file
export FEDORADANK_LSPCI_FILE="$(mktemp)"
printf '00:02.0 VGA compatible controller: Intel Corporation\n' >"$FEDORADANK_LSPCI_FILE"
got="$(detect_gpu)"
[[ "$got" == "intel" ]] && echo "PASS: intel gpu" || { echo "FAIL: intel got=$got"; fail=1; }

printf '01:00.0 VGA compatible controller: NVIDIA Corporation\n00:02.0 VGA: Intel\n' >"$FEDORADANK_LSPCI_FILE"
got="$(detect_gpu)"
[[ "$got" == "nvidia" ]] && echo "PASS: nvidia wins" || { echo "FAIL: nvidia got=$got"; fail=1; }

exit "$fail"
