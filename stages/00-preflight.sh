#!/usr/bin/env bash
set -euo pipefail
STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$STAGE_DIR/../lib/common.sh"

# shellcheck disable=SC1091
source /etc/os-release

if [[ "${ID:-}" != "fedora" ]]; then
  log_error "FedoraDank requires Fedora (found ID=${ID:-unknown})"
  exit 1
fi

if [[ "${VERSION_ID:-}" != "44" ]]; then
  log_warn "This script targets Fedora 44 (found $VERSION_ID)"
  if ! ask_yes_no "Continue anyway?" "no"; then
    log_error "aborted by user"
    exit 1
  fi
fi

require_cmd curl
require_cmd sudo

if ! curl -fsS --max-time 10 https://fedoraproject.org/ >/dev/null; then
  log_error "network check failed"
  exit 1
fi

sudo -v

# Free space on /
avail_kb="$(df -Pk / | awk 'NR==2{print $4}')"
need_kb=$((8 * 1024 * 1024))
if (( avail_kb < need_kb )); then
  log_warn "less than 8 GiB free on / (${avail_kb} KiB available)"
  if ! ask_yes_no "Continue with low disk space?" "no"; then
    exit 1
  fi
fi

log_success "preflight OK (Fedora ${VERSION_ID})"
