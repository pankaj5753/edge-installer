#!/usr/bin/env bash
# Installs missing Docker Engine, Docker Compose plugin, and/or OpenSSL via
# the OS package manager, using Docker's official repo (not the distro's,
# which is often too old to meet the >= 24 requirement).
#
# Only ever invoked interactively from preflight.sh after the operator
# explicitly opts in - EDG-15 AC13's offline-first design stays the default;
# this is a deliberate, opt-in exception for hosts confirmed to have
# internet access.
#
# Usage: ./lib/install-prereqs.sh [--docker] [--compose] [--openssl]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/lib/common.sh"

NEED_DOCKER=0
NEED_COMPOSE=0
NEED_OPENSSL=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --docker)  NEED_DOCKER=1; shift ;;
        --compose) NEED_COMPOSE=1; shift ;;
        --openssl) NEED_OPENSSL=1; shift ;;
        *) die "Unknown argument: $1" ;;
    esac
done

[[ -f /etc/os-release ]] || die "Cannot detect OS - /etc/os-release not found."
# shellcheck disable=SC1091
source /etc/os-release

case "${ID}" in
    ubuntu)
        log "Installing missing software via apt (Ubuntu)..."
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
        log "Installing missing software via dnf (RHEL)..."
        if [[ "${NEED_DOCKER}" -eq 1 || "${NEED_COMPOSE}" -eq 1 ]]; then
            sudo dnf -y install dnf-plugins-core
            sudo dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
            sudo dnf -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin
            sudo systemctl enable --now docker
        fi
        [[ "${NEED_OPENSSL}" -eq 1 ]] && sudo dnf -y install openssl
        ;;
    *)
        die "Automatic installation isn't supported on '${ID}'. See README.md Troubleshooting #1/#2 for manual steps."
        ;;
esac

log "Automatic installation finished."
