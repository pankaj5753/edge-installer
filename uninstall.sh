#!/usr/bin/env bash
# Removes the Smith+Nephew Hub stack from this host: stops and removes
# the hub-db/hub-api/hub-ui containers, their images, and the hub-net
# network. Database data, logs, and the TLS certificate are kept by
# default - pass --purge-data to permanently remove those too.
#
# Usage: ./uninstall.sh [--purge-data] [--yes]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
cd "${SCRIPT_DIR}"

PURGE_DATA=0
ASSUME_YES=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --purge-data) PURGE_DATA=1; shift ;;
        --yes) ASSUME_YES=1; shift ;;
        *) die "Unknown argument: $1" ;;
    esac
done

command -v docker > /dev/null 2>&1 || die "Docker Engine is required. See Smith-Nephew-Hub-Installation-Guide.md Troubleshooting #1."

# --- Audit logging: everything below is captured ----------------------------
LOG_DIR="/var/log/hub-agent"
if mkdir -p "${LOG_DIR}" 2>/dev/null && [[ -w "${LOG_DIR}" ]]; then
    LOG_FILE="${LOG_DIR}/uninstall.log"
else
    LOG_FILE="${SCRIPT_DIR}/uninstall.log"
    printf '[hub-installer] WARNING: cannot write to %s (run as root/sudo for the audit log) - logging to %s instead\n' "${LOG_DIR}" "${LOG_FILE}" >&2
fi
exec > >(tee -a "${LOG_FILE}") 2>&1

log "==================================================================="
log "Smith+Nephew Hub uninstaller - $(date -u +%Y-%m-%dT%H:%M:%SZ)"
log "==================================================================="

log "This will stop and remove the hub-db/hub-api/hub-ui containers, their images, and the hub-net network."
if [[ "${PURGE_DATA}" -eq 1 ]]; then
    warn "PURGE MODE: this will ALSO permanently delete the database volume, logs, and the TLS certificate/key. This cannot be undone."
fi

if [[ "${ASSUME_YES}" -ne 1 ]]; then
    if [[ "${PURGE_DATA}" -eq 1 ]]; then
        read -r -p "Type 'yes' to confirm permanent data deletion: " CONFIRM
        [[ "${CONFIRM}" == "yes" ]] || die "Aborted - confirmation not received."
    else
        read -r -p "Continue? [y/N] " CONFIRM
        [[ "${CONFIRM}" =~ ^[Yy]$ ]] || die "Aborted."
    fi
fi

# Load known image tags so the right images get removed - falls back to
# VERSION if .env is missing (e.g. install never completed).
if [[ -f "${ENV_FILE}" ]]; then
    load_env
else
    warn ".env not found - falling back to the VERSION file for image tags"
    FALLBACK_TAG="$(cat "${SCRIPT_DIR}/VERSION" 2>/dev/null || echo "")"
    UI_IMAGE_TAG="${UI_IMAGE_TAG:-${FALLBACK_TAG}}"
    API_IMAGE_TAG="${API_IMAGE_TAG:-${FALLBACK_TAG}}"
    DB_IMAGE_TAG="${DB_IMAGE_TAG:-${FALLBACK_TAG}}"
fi

log "Stopping and removing containers..."
if [[ "${PURGE_DATA}" -eq 1 ]]; then
    docker compose down -v --remove-orphans
else
    docker compose down --remove-orphans
fi

log "Removing images..."
for ref in "snn-hub-ui:${UI_IMAGE_TAG:-}" "snn-hub-api:${API_IMAGE_TAG:-}" "snn-hub-db:${DB_IMAGE_TAG:-}"; do
    if [[ "${ref}" == *: ]]; then
        warn "No tag known for ${ref%:} - skipping"
        continue
    fi
    docker rmi "${ref}" 2>/dev/null || warn "Image ${ref} was already removed or not found"
done

if [[ "${PURGE_DATA}" -eq 1 ]]; then
    log "Removing generated TLS certificate and .env (database credentials)..."
    rm -f "${CERTS_DIR}/hub.crt" "${CERTS_DIR}/hub.key" "${ENV_FILE}" "${ENV_PROD_FILE}"
fi

log "Uninstall complete."
if [[ "${PURGE_DATA}" -ne 1 ]]; then
    log "Database data, logs, and the TLS certificate were kept."
    log "Re-run ./install.sh to reinstall using the same data, or ./uninstall.sh --purge-data to remove everything permanently."
fi