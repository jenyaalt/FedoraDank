#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ec=0
for t in "$ROOT"/tests/test_*.sh; do
  echo "=== $(basename "$t") ==="
  bash "$t" || ec=1
done
exit "$ec"
