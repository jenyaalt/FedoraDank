#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$ROOT/lib/common.sh"
source "$ROOT/lib/detect.sh"

FORCE=0
FROM=""

usage() {
  cat <<'EOF'
Usage: ./run.sh [--force] [--from NN] [--help]

  --force     Clear markers and re-run all stages
  --from NN   Start from stage number NN (e.g. 40)
  --help      Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    --from)
      FROM="${2:-}"
      [[ -n "$FROM" ]] || { log_error "--from needs a stage number"; exit 1; }
      shift 2
      ;;
    --help|-h) usage; exit 0 ;;
    *) log_error "unknown arg: $1"; usage; exit 1 ;;
  esac
done

mkdir -p "$FEDORADANK_CACHE"

if [[ "$FORCE" -eq 1 ]]; then
  log_warn "clearing all stage markers"
  rm -f "$FEDORADANK_CACHE"/*.done
fi

mapfile -t STAGES < <(find "$ROOT/stages" -maxdepth 1 -type f -name '[0-9]*.sh' | sort)

if [[ ${#STAGES[@]} -eq 0 ]]; then
  log_error "no stage scripts in $ROOT/stages"
  exit 1
fi

for stage in "${STAGES[@]}"; do
  base="$(basename "$stage")"
  id="${base%%-*}"

  if [[ -n "$FROM" ]]; then
    from_n=$((10#$FROM))
    id_n=$((10#$id))
    if (( id_n < from_n )); then
      log_info "skip $base (--from $FROM)"
      continue
    fi
  fi

  if marker_is_done "$id" && [[ "$FORCE" -eq 0 ]]; then
    log_info "skip $base (already done)"
    continue
  fi

  log_info "running $base"
  if ! bash "$stage"; then
    log_error "failed at stage $base"
    exit 1
  fi
  marker_done "$id"
  log_success "completed $base"
done

log_success "all requested stages finished"
