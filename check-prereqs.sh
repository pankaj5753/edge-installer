#!/usr/bin/env bash
# Usage: ./check-prereqs.sh [--yes]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

ASSUME_YES=0
[[ "${1:-}" == "--yes" ]] && ASSUME_YES=1

NEED_DOCKER=0
NEED_COMPOSE=0
NEED_OPENSSL=0

log "Checking for Docker Engine, Docker Compose, and OpenSSL..."

if command -v docker > /dev/null 2>&1 && DOCKER_VERSION="$(docker version --format '{{.Server.Version}}' 2>/dev/null)" \
   && [[ -n "${DOCKER_VERSION}" ]] && version_ge "${DOCKER_VERSION}" "24.0.0"; then
    log "OK      - Docker Engine ${DOCKER_VERSION}"
else
    log "MISSING - Docker Engine >= 24"
    NEED_DOCKER=1
fi

if COMPOSE_VERSION="$(docker compose version --short 2>/dev/null)" \
   && [[ -n "${COMPOSE_VERSION}" ]] && version_ge "${COMPOSE_VERSION}" "2.20.0"; then
    log "OK      - Docker Compose ${COMPOSE_VERSION}"
else
    log "MISSING - Docker Compose plugin >= 2.20"
    NEED_COMPOSE=1
fi

if command -v openssl > /dev/null 2>&1; then
    log "OK      - OpenSSL ($(openssl version))"
else
    log "MISSING - OpenSSL"
    NEED_OPENSSL=1
fi

if [[ "${NEED_DOCKER}" -eq 0 && "${NEED_COMPOSE}" -eq 0 && "${NEED_OPENSSL}" -eq 0 ]]; then
    log "Everything required is already present. Run ./install.sh next."
    exit 0
fi

log ""
log "Missing software can be installed automatically via this host's package manager."
log "This requires internet access and will use sudo."
if [[ "${ASSUME_YES}" -ne 1 ]]; then
    read -r -p "Install missing software now? [y/N] " REPLY
    if [[ ! "${REPLY}" =~ ^[Yy] ]]; then
        log "Skipped - install the above manually (README.md Troubleshooting #1/#2), or re-run with --yes."
        exit 0
    fi
fi

[[ -f /etc/os-release ]] || die "Cannot detect OS - /etc/os-release not found."
# shellcheck disable=SC1091
source /etc/os-release

case "${ID}" in
    ubuntu)
        log "Installing via apt (Ubuntu)..."
        sudo apt-get update
        if [[ "${NEED_DOCKER}" -eq 1 || "${NEED_COMPOSE}" -eq 1 ]]; then
            sudo apt-get install -y ca-certificates curl gnupg
            sudo install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            sudo chmod a+r /etc/apt/keyrings/docker.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
                | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            sudo apt-get update
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            sudo systemctl enable --now docker
        fi
        [[ "${NEED_OPENSSL}" -eq 1 ]] && sudo apt-get install -y openssl
        ;;
    rhel)
        log "Installing via dnf (RHEL)..."
        if [[ "${NEED_DOCKER}" -eq 1 || "${NEED_COMPOSE}" -eq 1 ]]; then
            sudo dnf -y install dnf-plugins-core
            sudo dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
            sudo dnf -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin
            sudo systemctl enable --now docker
        fi
        [[ "${NEED_OPENSSL}" -eq 1 ]] && sudo dnf -y install openssl
        ;;
    *)
        die "Automatic installation isn't supported on '${ID}' - install Docker Engine >= 24, the Compose plugin >= 2.20, and OpenSSL manually. See README.md Troubleshooting #1/#2."
        ;;
esac

log ""
log "Done. Run ./install.sh next."