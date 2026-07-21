# FedoraDank Bootstrap Installer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a staged `./run.sh` bootstrap for Fedora 44 netinstall that installs drivers (VirtualBox or ThinkPad), PipeWire+EasyEffects, core apps (Chrome, VS Code, Cursor, Kitty, Yazi, fetch, Python/uv, Node), then launches interactive Dank Linux (niri + Kitty).

**Architecture:** `run.sh` orchestrates numbered stage scripts under `stages/`, with shared helpers in `lib/common.sh` (logging, dnf, markers, retries) and `lib/detect.sh` (VirtualBox / ThinkPad / GPU). Stages write markers under `~/.cache/fedoradank/` for idempotent re-runs. Native RPM only — no Flatpak/Snap.

**Tech Stack:** Bash (`set -euo pipefail`), Fedora `dnf`/COPR, RPM Fusion, vendor RPM repos (Google, Microsoft, Cursor), official uv installer, Dank `install.danklinux.com`, lightweight bash unit tests in `tests/`.

## Global Constraints

- Fedora only; prefer VERSION_ID=44 (warn + confirm if other Fedora version; abort if non-Fedora)
- Native packages only — never Flatpak or Snap
- PipeWire + EasyEffects — do not install classic `pulseaudio` daemon packages
- Dank install is interactive — no `-c`/`-t`/`-y` headless flags
- Documented Dank choices: compositor **niri**, terminal **Kitty**
- Spec: `docs/superpowers/specs/2026-07-21-fedoradank-bootstrap-design.md`

## File Structure

| Path | Responsibility |
|------|----------------|
| `run.sh` | CLI (`--force`, `--from NN`), source libs, run stages in order |
| `lib/common.sh` | `log_*`, `require_cmd`, `dnf_install`, `retry`, markers, `ask_yes_no` |
| `lib/detect.sh` | `detect_environment`, `detect_gpu`, DMI/lspci helpers |
| `stages/00-preflight.sh` … `99-finish.sh` | One concern each |
| `tests/test_common.sh` | Unit tests for markers/retry helpers |
| `tests/test_detect.sh` | Unit tests for env/GPU detection with mocked DMI |
| `tests/run-tests.sh` | Test runner |
| `README.md` | Clone + `./run.sh` usage |

---

### Task 1: Common library + test harness

**Files:**
- Create: `lib/common.sh`
- Create: `tests/test_common.sh`
- Create: `tests/run-tests.sh`

**Interfaces:**
- Consumes: none
- Produces:
  - `FEDORADANK_ROOT` — repo root absolute path
  - `FEDORADANK_CACHE` — default `$HOME/.cache/fedoradank`
  - `log_info|warn|error|success(msg)`
  - `ask_yes_no(prompt, default_yes_or_no)` → exit 0 if yes
  - `marker_path(stage_id)` → path string
  - `marker_done(stage_id)` / `marker_clear(stage_id)` / `marker_is_done(stage_id)`
  - `retry(n, command...)` — run command up to n times
  - `dnf_install(packages...)` — `sudo dnf install -y` with one retry via `retry`
  - `require_cmd(name)` — abort if missing
  - `ensure_path_line(file, line)` — append to bashrc-like file if absent

- [ ] **Step 1: Write failing tests for markers and retry**

Create `tests/test_common.sh`:

```bash
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
```

Create `tests/run-tests.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ec=0
for t in "$ROOT"/tests/test_*.sh; do
  echo "=== $(basename "$t") ==="
  bash "$t" || ec=1
done
exit "$ec"
```

- [ ] **Step 2: Run tests — expect fail (missing lib)**

Run: `bash tests/run-tests.sh`  
Expected: FAIL sourcing `lib/common.sh` (No such file or directory)

- [ ] **Step 3: Implement `lib/common.sh`**

```bash
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

ensure_path_line() {
  local file="$1" line="$2"
  mkdir -p "$(dirname "$file")"
  touch "$file"
  grep -Fqx "$line" "$file" 2>/dev/null || printf '%s\n' "$line" >>"$file"
}
```

- [ ] **Step 4: Run tests — expect pass**

Run: `bash tests/run-tests.sh`  
Expected: all PASS, exit 0

- [ ] **Step 5: Commit**

```bash
git add lib/common.sh tests/test_common.sh tests/run-tests.sh
git commit -m "feat: add common bootstrap helpers and unit tests"
```

---

### Task 2: Environment detection library

**Files:**
- Create: `lib/detect.sh`
- Create: `tests/test_detect.sh`
- Modify: none

**Interfaces:**
- Consumes: `log_*` from `common.sh` (optional; detection should work without)
- Produces:
  - `dmi_read(field)` — read `/sys/class/dmi/id/<field>` or empty
  - `detect_environment()` — prints exactly one of: `virtualbox` | `thinkpad` | `unknown` (also sets `FEDORADANK_ENV`)
  - `detect_gpu()` — prints `intel` | `amd` | `nvidia` | `none` (sets `FEDORADANK_GPU`); NVIDIA wins if present alongside iGPU
  - `has_fingerprint()` — exit 0 if `/sys/class/fingerprint` or lsusb/libfprint hints; prefer checking `/sys/bus/usb/devices` for known fingerprint vendors OR `ls /dev/bus/usb` + `lsusb` if available — simpler: return 0 if `lsusb` output matches `Fingerprint|Synaptics|Validity|Goodix` else 1

- [ ] **Step 1: Write failing detection tests**

Create `tests/test_detect.sh`:

```bash
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
```

- [ ] **Step 2: Run detect tests — expect fail**

Run: `bash tests/test_detect.sh`  
Expected: FAIL missing `lib/detect.sh`

- [ ] **Step 3: Implement `lib/detect.sh`**

```bash
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
  if printf '%s' "$info" | grep -Eiq 'amd|ati|advanced micro devices'; then
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
```

- [ ] **Step 4: Run all tests — expect pass**

Run: `bash tests/run-tests.sh`  
Expected: PASS for common + detect

- [ ] **Step 5: Commit**

```bash
git add lib/detect.sh tests/test_detect.sh
git commit -m "feat: add VirtualBox/ThinkPad/GPU detection helpers"
```

---

### Task 3: `run.sh` orchestrator

**Files:**
- Create: `run.sh`
- Create: `stages/.gitkeep` (placeholder until stages exist — or create stub stages that `log_info` and `marker_done`)

**Interfaces:**
- Consumes: `lib/common.sh`, stage scripts that export nothing but must be executable bash with `stage_main` or just run top-level
- Produces: CLI behavior documented below

**Stage contract:** each `stages/NN-name.sh` is executed as `bash stages/NN-name.sh` with env:
- `FEDORADANK_ROOT`, `FEDORADANK_CACHE` set
- libs already … actually stages should `source` libs themselves for independent runs:

```bash
# top of every stage:
STAGE_ID=00
STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$STAGE_DIR/../lib/common.sh"
source "$STAGE_DIR/../lib/detect.sh"
```

`run.sh` skips if `marker_is_done STAGE_ID` unless forced.

- [ ] **Step 1: Implement `run.sh`**

```bash
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
  id="${base%%-*}"   # e.g. 00, 10, 40

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
```

**Only `run.sh` writes markers** after a successful stage exit so a partial failure (especially Dank) is not marked done. Stages must **not** call `marker_done`.

- [ ] **Step 2: Create stub stages for orchestration smoke test**

For each of `00-preflight.sh`, `10-system-base.sh`, `20-drivers.sh`, `30-audio.sh`, `40-apps.sh`, `50-dank.sh`, `99-finish.sh`, create a temporary stub:

```bash
#!/usr/bin/env bash
set -euo pipefail
STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$STAGE_DIR/../lib/common.sh"
log_info "stub $(basename "$0") — replace in later tasks"
```

- [ ] **Step 3: Smoke-test orchestrator**

Run: `FEDORADANK_CACHE=/tmp/fd-test-cache ./run.sh`  
Expected: runs all stubs, creates `*.done` markers  
Run again: all skipped  
Run: `FEDORADANK_CACHE=/tmp/fd-test-cache ./run.sh --from 40`  
Expected: runs 40, 50, 99 only (after clearing those markers or using fresh cache)

- [ ] **Step 4: Commit**

```bash
chmod +x run.sh stages/*.sh
git add run.sh stages/
git commit -m "feat: add run.sh stage orchestrator with --force/--from"
```

---

### Task 4: Stage 00 — Preflight

**Files:**
- Modify: `stages/00-preflight.sh` (replace stub)

**Interfaces:**
- Consumes: `ask_yes_no`, `log_*`, `require_cmd`
- Produces: abort on non-Fedora; optional confirm if not 44

- [ ] **Step 1: Implement preflight**

```bash
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
```

- [ ] **Step 2: Syntax check**

Run: `bash -n stages/00-preflight.sh`  
Expected: no output, exit 0

- [ ] **Step 3: Commit**

```bash
git add stages/00-preflight.sh
git commit -m "feat: implement Fedora preflight stage"
```

---

### Task 5: Stage 10 — System base

**Files:**
- Modify: `stages/10-system-base.sh`

**Interfaces:**
- Consumes: `dnf_install`, `retry`, `ensure_path_line`
- Produces: RPM Fusion enabled; CLI tools; python3; uv; nodejs/npm

- [ ] **Step 1: Implement system base**

```bash
#!/usr/bin/env bash
set -euo pipefail
STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$STAGE_DIR/../lib/common.sh"

log_info "upgrading system packages"
retry 2 sudo dnf upgrade -y

log_info "enabling RPM Fusion"
release="$(rpm -E %fedora)"
retry 2 sudo dnf install -y \
  "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${release}.noarch.rpm" \
  "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${release}.noarch.rpm" \
  || log_warn "RPM Fusion may already be enabled"

dnf_install \
  git curl wget jq ripgrep fd-find fzf bash-completion unzip tar which fontconfig \
  pciutils usbutils dmidecode \
  python3 python3-devel python3-pip \
  nodejs npm

# fd package provides `fd` or `fdfind` depending on distro — on Fedora it is `fd`
# ripgrep provides `rg`

log_info "installing uv"
if ! command -v uv >/dev/null 2>&1; then
  curl -fsSL https://astral.sh/uv/install.sh | sh
fi
ensure_path_line "$HOME/.bashrc" 'export PATH="$HOME/.local/bin:$PATH"'
# shellcheck disable=SC1090
[[ -f "$HOME/.local/bin/env" ]] && source "$HOME/.local/bin/env" || true
export PATH="$HOME/.local/bin:$PATH"

require_cmd git
require_cmd node
require_cmd npm
require_cmd npx
command -v uv >/dev/null || log_warn "uv not on PATH yet — open a new shell or source ~/.bashrc"

log_success "system base installed"
```

- [ ] **Step 2: Syntax check**

Run: `bash -n stages/10-system-base.sh`

- [ ] **Step 3: Commit**

```bash
git add stages/10-system-base.sh
git commit -m "feat: system base with RPM Fusion, CLI, Python, uv, Node"
```

---

### Task 6: Stage 20 — Drivers

**Files:**
- Modify: `stages/20-drivers.sh`

**Interfaces:**
- Consumes: `detect_environment`, `detect_gpu`, `has_fingerprint`, `dnf_install`
- Produces: env-specific packages; writes `$FEDORADANK_CACHE/env.txt` and `gpu.txt` for finish summary

- [ ] **Step 1: Implement drivers stage**

```bash
#!/usr/bin/env bash
set -euo pipefail
STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$STAGE_DIR/../lib/common.sh"
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
    log_info "VirtualBox guest path"
    dnf_install kernel-devel kernel-headers gcc make perl elfutils-libelf-devel
    if ! dnf_install virtualbox-guest-additions; then
      log_warn "RPM Fusion guest additions unavailable."
      log_warn "Insert Guest Additions ISO from VirtualBox UI and run the installer manually."
    fi
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
```

- [ ] **Step 2: Syntax check + dry logic test**

Run: `bash -n stages/20-drivers.sh`  
Optional: with `FEDORADANK_DMI_ROOT` mocked, `bash -c 'source lib/...; detect_environment'` already covered by unit tests.

- [ ] **Step 3: Commit**

```bash
git add stages/20-drivers.sh
git commit -m "feat: VirtualBox and ThinkPad driver stage with GPU branching"
```

---

### Task 7: Stage 30 — Audio (PipeWire + EasyEffects)

**Files:**
- Modify: `stages/30-audio.sh`

- [ ] **Step 1: Implement audio stage**

```bash
#!/usr/bin/env bash
set -euo pipefail
STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$STAGE_DIR/../lib/common.sh"

# Explicitly avoid classic pulseaudio daemon packages
dnf_install \
  pipewire pipewire-pulseaudio pipewire-alsa pipewire-jack-audio-connection-kit \
  wireplumber \
  bluez bluez-tools \
  easyeffects

# Fedora package names: confirm pipewire-pulse vs pipewire-pulseaudio during implement
# If `pipewire-pulseaudio` missing, try `pipewire-pulse`.

systemctl --user enable --now pipewire pipewire-pulse wireplumber 2>/dev/null || \
  log_warn "user pipewire services will start at graphical login"

log_success "PipeWire + EasyEffects installed"
```

During implementation: run `dnf search pipewire-pulse` on F44 (or docs) and lock the exact package names in the script — prefer whatever Fedora 44 ships.

- [ ] **Step 2: Assert no pulseaudio daemon pull**

After install on a test VM, run:  
`rpm -q pulseaudio && echo BAD || echo OK`  
Expected: package not installed as daemon (pulseaudio-libs as dependency of pipewire-pulse is OK).

- [ ] **Step 3: Commit**

```bash
git add stages/30-audio.sh
git commit -m "feat: PipeWire stack and EasyEffects audio stage"
```

---

### Task 8: Stage 40 — Applications

**Files:**
- Modify: `stages/40-apps.sh`
- Create: `scripts/install-nerd-fonts.sh` (optional helper sourced/called by stage)

- [ ] **Step 1: Implement apps stage**

```bash
#!/usr/bin/env bash
set -euo pipefail
STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$STAGE_DIR/../lib/common.sh"

dnf_install kitty

# Yazi
if ! dnf_install yazi; then
  log_info "trying COPR for yazi"
  sudo dnf copr enable -y lihaohong/yazi || sudo dnf copr enable -y appimagenerd/yazi || true
  dnf_install yazi
fi

# Google Chrome
if ! rpm -q google-chrome-stable >/dev/null 2>&1; then
  sudo dnf install -y \
    https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm
fi

# VS Code (Microsoft repo)
if [[ ! -f /etc/yum.repos.d/vscode.repo ]]; then
  sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
  sudo tee /etc/yum.repos.d/vscode.repo >/dev/null <<'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
fi
dnf_install code

# Cursor — official RPM
if ! command -v cursor >/dev/null 2>&1; then
  tmp="$(mktemp -d)"
  # Resolve current RPM URL from Cursor download API/page during implementation.
  # Preferred pattern (verify live URL when implementing):
  curl -fsSL -o "$tmp/cursor.rpm" \
    "https://downloader.cursor.sh/linux/rpm/x64" \
    || curl -fsSL -o "$tmp/cursor.rpm" \
    "https://api2.cursor.sh/updates/download/golden/linux-x64-rpm/cursor/latest"
  sudo dnf install -y "$tmp/cursor.rpm"
  rm -rf "$tmp"
fi

# Nerd Fonts
font_dir="$HOME/.local/share/fonts/NerdFonts"
mkdir -p "$font_dir"
for font in JetBrainsMono FiraCode; do
  zip="$font_dir/${font}.zip"
  if [[ ! -d "$font_dir/$font" ]]; then
    curl -fsSL -o "$zip" \
      "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${font}.zip"
    mkdir -p "$font_dir/$font"
    unzip -qo "$zip" -d "$font_dir/$font"
    rm -f "$zip"
  fi
done
fc-cache -fv "$HOME/.local/share/fonts" || true

# fetch (areofyl/fetch)
if ! command -v fetch >/dev/null 2>&1; then
  if sudo dnf copr enable -y realorangekun/fetch && dnf_install fetch; then
    log_success "fetch from COPR"
  else
    log_info "building fetch from source"
    dnf_install make gcc
    src="$(mktemp -d)"
    git clone --depth 1 https://github.com/areofyl/fetch.git "$src/fetch"
    make -C "$src/fetch"
    sudo make -C "$src/fetch" install
    rm -rf "$src"
  fi
fi

log_success "applications installed"
```

**Implementation note:** Before committing, verify Cursor RPM URL with a HEAD request; if Cursor changes endpoints, pin the working URL in-script with a comment dated in the commit message.

- [ ] **Step 2: Syntax check**

Run: `bash -n stages/40-apps.sh`

- [ ] **Step 3: Commit**

```bash
git add stages/40-apps.sh
git commit -m "feat: install Kitty Yazi Chrome VS Code Cursor fonts fetch"
```

---

### Task 9: Stage 50 — Dank interactive

**Files:**
- Modify: `stages/50-dank.sh`

- [ ] **Step 1: Implement Dank stage**

```bash
#!/usr/bin/env bash
set -euo pipefail
STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$STAGE_DIR/../lib/common.sh"

sudo -v

cat <<'EOF'

============================================
  Dank Linux interactive installer next
============================================
When prompted, choose:
  • Compositor: niri
  • Terminal:   Kitty

Do NOT use headless flags; this is intentional.
============================================

EOF

ask_yes_no "Launch Dank installer now?" "yes" || {
  log_warn "skipped Dank installer — re-run with: ./run.sh --from 50"
  exit 1
}

# Interactive — no -c/-t/-y
curl -fsSL https://install.danklinux.com | sh

log_success "Dank installer finished"
```

- [ ] **Step 2: Syntax check**

Run: `bash -n stages/50-dank.sh`

- [ ] **Step 3: Commit**

```bash
git add stages/50-dank.sh
git commit -m "feat: interactive Dank Linux install stage"
```

---

### Task 10: Stage 99 — Finish + README

**Files:**
- Modify: `stages/99-finish.sh`
- Modify: `README.md`

- [ ] **Step 1: Implement finish stage**

```bash
#!/usr/bin/env bash
set -euo pipefail
STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$STAGE_DIR/../lib/common.sh"

sudo systemctl set-default graphical.target

env_name="$(cat "$FEDORADANK_CACHE/env.txt" 2>/dev/null || echo unknown)"
gpu_name="$(cat "$FEDORADANK_CACHE/gpu.txt" 2>/dev/null || echo unknown)"

cat <<EOF

======== FedoraDank summary ========
Environment: $env_name
GPU:         $gpu_name

Check binaries (open a new shell if PATH stale):
  git rg fd fzf uv node npx kitty yazi code cursor fetch
  google-chrome-stable | google-chrome

Next:
  1. Reboot
  2. Log into the niri / DankMaterialShell session from the greeter
====================================

EOF

if ask_yes_no "Reboot now?" "no"; then
  sudo systemctl reboot
fi
```

- [ ] **Step 2: Write README**

```markdown
# FedoraDank

Bootstrap a **Fedora 44** netinstall (minimal) into a Dank Linux desktop (**niri** + DankMaterialShell) plus a fixed native app set.

## Requirements

- Fedora (44 preferred)
- Network + sudo
- No Flatpak/Snap — native RPM only

## Usage

```bash
git clone https://github.com/jenyaalt/FedoraDank.git
cd FedoraDank
chmod +x run.sh
./run.sh
```

Flags:

- `./run.sh --force` — redo all stages
- `./run.sh --from 40` — resume from applications stage

## Install order

00 preflight → 10 system base → 20 drivers → 30 audio → 40 apps → 50 Dank (interactive) → 99 finish

During Dank, select **niri** and **Kitty**.

## Drivers

Auto-detects **VirtualBox** (Guest Additions) or **Lenovo ThinkPad** (firmware, TLP, Intel/AMD/NVIDIA branch).

## Docs

- Design: `docs/superpowers/specs/2026-07-21-fedoradank-bootstrap-design.md`
- Plan: `docs/superpowers/plans/2026-07-21-fedoradank-bootstrap.md`
```

- [ ] **Step 3: Run unit tests once more**

Run: `bash tests/run-tests.sh`  
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add stages/99-finish.sh README.md
git commit -m "feat: finish stage and README usage docs"
```

---

### Task 11: End-to-end verification checklist (on VM)

**Files:** none (manual QA)

- [ ] **Step 1: On Fedora 44 VirtualBox netinstall VM**

```bash
git clone https://github.com/jenyaalt/FedoraDank.git
cd FedoraDank
./run.sh
```

Complete Dank TUI with niri + Kitty; reboot; log in.

- [ ] **Step 2: Verify commands**

```bash
command -v code cursor kitty yazi google-chrome-stable rg fd fzf git uv node npx fetch easyeffects
systemctl get-default   # graphical.target
```

- [ ] **Step 3: Document any package-name fixes** discovered on F44 as a follow-up commit (`fix: ...`)

---

## Spec coverage self-review

| Spec requirement | Task |
|------------------|------|
| Modular stages + run.sh | 3 |
| Markers / --force / --from | 3 |
| Preflight Fedora/44/network/sudo/disk | 4 |
| RPM Fusion, CLI, git, Python, uv, Node | 5 |
| VBox vs ThinkPad + GPU branch | 2, 6 |
| PipeWire + EasyEffects, no pulse daemon | 7 |
| Kitty, Yazi, Chrome, VS Code, Cursor, fonts, fetch | 8 |
| Interactive Dank, niri+Kitty instructions | 9 |
| graphical.target, summary, reboot ask | 10 |
| README | 10 |
| Unit tests for libs | 1, 2 |
| No Flatpak/Snap | Global + stages never call them |

## Placeholder / consistency check

- Cursor download URL must be verified live in Task 8 (called out explicitly; not left as vague TBD).
- PipeWire package exact names verified in Task 7 against F44.
- Markers written only by `run.sh` after success (Dank partial failure does not mark done) — consistent with design §Error handling.
- `detect_environment` / `detect_gpu` names consistent across Tasks 2, 6, 10.
