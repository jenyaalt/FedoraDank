#!/usr/bin/env bash
# Shared helpers for FedoraDank bootstrap. Source only — do not execute.

FEDORADANK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FEDORADANK_CACHE="${FEDORADANK_CACHE:-$HOME/.cache/fedoradank}"

log_info()    { printf '==> %s\n' "$*"; }
log_warn()    { printf 'WARN: %s\n' "$*" >&2; }
log_error()   { printf 'ERROR: %s\n' "$*" >&2; }
log_success() { printf 'OK: %s\n' "$*"; }

ask_yes_no() {
  local prompt="$1" default="${2:-no}" reply
  local hint="[y/N]"
  [[ "$default" == "yes" ]] && hint="[Y/n]"
  read -r -p "$prompt $hint " reply || true
  reply="${reply:-}"
  if [[ -z "$reply" ]]; then
    [[ "$default" == "yes" ]]
    return
  fi
  [[ "$reply" =~ ^[Yy]([Ee][Ss])?$ ]]
}

marker_path() { printf '%s/%s.done\n' "$FEDORADANK_CACHE" "$1"; }

marker_done() {
  mkdir -p "$FEDORADANK_CACHE"
  touch "$(marker_path "$1")"
}

marker_clear() {
  rm -f "$(marker_path "$1")"
}

marker_is_done() {
  [[ -f "$(marker_path "$1")" ]]
}

retry() {
  local tries="$1"; shift
  local i=1
  until "$@"; do
    if (( i >= tries )); then
      log_error "command failed after ${tries} attempts: $*"
      return 1
    fi
    log_warn "retry $i/$tries: $*"
    i=$((i + 1))
    sleep 1
  done
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    log_error "required command not found: $1"
    return 1
  }
}

dnf_install() {
  retry 2 sudo dnf install -y "$@"
}

# Enable a COPR project non-interactively.
# On dnf5 (Fedora 41+), `dnf copr enable -y OWNER/PROJECT` is wrong: `-y` is
# parsed as the project-spec. Put assumeyes before the subcommand, or after
# the project name.
copr_enable() {
  local project="$1"
  sudo dnf -y copr enable "$project" \
    || sudo dnf copr enable "$project" -y
}

ensure_path_line() {
  local file="$1" line="$2"
  mkdir -p "$(dirname "$file")"
  touch "$file"
  grep -Fqx "$line" "$file" 2>/dev/null || printf '%s\n' "$line" >>"$file"
}

# Enable and start systemd units if present. Never aborts the caller.
# Usage: service_enable_now [--user] unit [unit...]
service_enable_now() {
  local user=0
  if [[ "${1:-}" == "--user" ]]; then
    user=1
    shift
  fi
  local unit
  for unit in "$@"; do
    if [[ "$user" -eq 1 ]]; then
      if systemctl --user cat "$unit" >/dev/null 2>&1 \
        || systemctl --user cat "${unit}.service" >/dev/null 2>&1; then
        if systemctl --user enable --now "$unit" 2>/dev/null; then
          log_success "enabled (user): $unit"
        else
          log_warn "could not enable (user): $unit"
        fi
      else
        log_warn "user unit not found, skip: $unit"
      fi
    else
      if systemctl cat "$unit" >/dev/null 2>&1 \
        || systemctl cat "${unit}.service" >/dev/null 2>&1; then
        if sudo systemctl enable --now "$unit" 2>/dev/null; then
          log_success "enabled: $unit"
        else
          log_warn "could not enable: $unit"
        fi
      else
        log_warn "unit not found, skip: $unit"
      fi
    fi
  done
  return 0
}
