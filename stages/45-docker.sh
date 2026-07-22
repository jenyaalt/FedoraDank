#!/usr/bin/env bash
set -euo pipefail
STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$STAGE_DIR/../lib/common.sh"

log_info "installing Docker Engine + Compose"

# Prefer official Docker CE (docs.docker.com) on Fedora 41+ / DNF5.
add_docker_ce_repo() {
  local repo=/etc/yum.repos.d/docker-ce.repo
  if [[ -f "$repo" ]]; then
    return 0
  fi
  if sudo dnf config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo 2>/dev/null; then
    return 0
  fi
  if sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo 2>/dev/null; then
    return 0
  fi
  return 1
}

install_docker_ce() {
  add_docker_ce_repo || return 1
  dnf_install \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin
}

# Fedora-maintained alternative (moby) if Docker CE repo/packages fail.
install_docker_fedora() {
  dnf_install moby-engine docker-compose \
    || dnf_install docker docker-compose
}

if install_docker_ce; then
  log_success "Docker CE + Compose plugin installed"
else
  log_warn "Docker CE install failed — trying Fedora moby-engine packages"
  if ! install_docker_fedora; then
    log_error "could not install Docker from Docker CE or Fedora repos"
    exit 1
  fi
  log_success "Fedora Docker (moby) + docker-compose installed"
fi

service_enable_now docker

# Allow current user to run docker without sudo (takes effect after re-login)
if getent group docker >/dev/null 2>&1; then
  sudo usermod -aG docker "$USER" \
    || log_warn "could not add $USER to docker group"
else
  log_warn "docker group missing after install"
fi

# Provide classic `docker-compose` command when only the Compose V2 plugin exists.
if ! command -v docker-compose >/dev/null 2>&1; then
  if docker compose version >/dev/null 2>&1; then
    log_info "creating /usr/local/bin/docker-compose wrapper → docker compose"
    sudo tee /usr/local/bin/docker-compose >/dev/null <<'EOF'
#!/bin/sh
exec docker compose "$@"
EOF
    sudo chmod 755 /usr/local/bin/docker-compose
  else
    log_warn "neither docker-compose nor 'docker compose' is available yet"
  fi
fi

require_cmd docker
if command -v docker-compose >/dev/null 2>&1; then
  log_success "docker-compose ready: $(command -v docker-compose)"
elif docker compose version >/dev/null 2>&1; then
  log_success "docker compose plugin ready"
else
  log_warn "Compose CLI not verified — check after re-login"
fi

log_info "Docker group membership needs a new login (or: newgrp docker)"
log_success "Docker stage finished"
