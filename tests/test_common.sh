#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "$ROOT/lib/common.sh"

export FEDORADANK_CACHE="$(mktemp -d)"
trap 'rm -rf "$FEDORADANK_CACHE"' EXIT

fail=0
assert_eq() {
  local got="$1" want="$2" msg="$3"
  if [[ "$got" != "$want" ]]; then
    echo "FAIL: $msg (got='$got' want='$want')"
    fail=1
  else
    echo "PASS: $msg"
  fi
}

marker_clear 10 2>/dev/null || true
if marker_is_done 10; then
  echo "FAIL: marker should be absent"
  fail=1
else
  echo "PASS: marker absent"
fi

marker_done 10
if marker_is_done 10; then
  echo "PASS: marker present after done"
else
  echo "FAIL: marker missing after done"
  fail=1
fi

# retry: succeed on second attempt
n=0
retry 3 bash -c 'nfile='"$FEDORADANK_CACHE"'/n; c=$(cat "$nfile" 2>/dev/null || echo 0); c=$((c+1)); echo $c >"$nfile"; test "$c" -ge 2'
assert_eq "$(cat "$FEDORADANK_CACHE/n")" "2" "retry succeeds on second try"

exit "$fail"
