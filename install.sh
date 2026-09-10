#!/usr/bin/env bash
# Installs the Smith+Nephew Hub stack (hub-db, hub-api, hub-ui) from
# local artifacts only - no ECR/AWS access is used at install time.
# Aborts on first failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
cd "${SCRIPT_DIR}"

VERSION="$(cat "${SCRIPT_DIR}/VERSION")"

# --- Audit logging: everything below is captured ----------------------------
LOG_DIR="/var/log/hub-agent"
if mkdir -p "${LOG_DIR}" 2>/dev/null && [[ -w "${LOG_DIR}" ]]; then
    LOG_FILE="${LOG_DIR}/install.log"
else
    LOG_FILE="${SCRIPT_DIR}/install.log"
    printf '[hub-installer] WARNING: cannot write to %s (run as root/sudo for the audit log) - logging to %s instead\n' "${LOG_DIR}" "${LOG_FILE}" >&2
fi
exec > >(tee -a "${LOG_FILE}") 2>&1

log "==================================================================="
log "Smith+Nephew Hub installer v${VERSION} - $(date -u +%Y-%m-%dT%H:%M:%SZ)"
log "==================================================================="

load_env

# --- 0. Sync release-pinned image tags from this bundle's .env.example -----
# (always refreshed, unlike the network/DB values below - see
# sync_image_tags in lib/common.sh)
sync_image_tags
load_env

# --- 1. Preflight (writes preflight-report.txt, aborts on failure) --------
"${SCRIPT_DIR}/preflight.sh"

# --- 2. Verify archive checksum, then load images ---------------------------
ARCHIVE="${IMAGES_DIR}/hub-images-${VERSION}.tar.gz"
[[ -f "${ARCHIVE}" ]] || die "Missing ${ARCHIVE}. See README.md Troubleshooting #5."
verify_archive_checksum "${ARCHIVE}"
log "Loading images from $(basename "${ARCHIVE}")..."
docker load -i "${ARCHIVE}"

# --- 3. Static LAN IP and bind port (first run only) ------------------------
if [[ -z "${STATIC_IP:-}" ]]; then
    read -r -p "Enter the static LAN IP for this host: " STATIC_IP
    [[ -n "${STATIC_IP}" ]] || die "A static IP is required. See README.md Troubleshooting #7."
    set_env_var STATIC_IP "${STATIC_IP}"
fi
if [[ -z "${BIND_PORT:-}" ]]; then
    read -r -p "Enter the bind port [443]: " BIND_PORT_INPUT
    BIND_PORT="${BIND_PORT_INPUT:-443}"
    set_env_var BIND_PORT "${BIND_PORT}"
fi
export STATIC_IP BIND_PORT

# --- 4/5. TLS certificate + fingerprint, plus hub-api's internal keystore
# (idempotent) ----------------------------------------------------------------
"${SCRIPT_DIR}/lib/generate-certs.sh" --cn "${STATIC_IP}"
FINGERPRINT="$(openssl x509 -in "${CERTS_DIR}/hub.crt" -noout -fingerprint -sha256 | cut -d= -f2)"
log "Certificate SHA-256 fingerprint (record for first-connection trust verification):"
log "  ${FINGERPRINT}"

# --- 6. Database credentials (idempotent) -----------------------------------
# Infra-level MySQL connection password only - distinct from
# hospital/cloud-facility credentials, which are entered later via the
# Cloud Configuration screen and are never written here.
if [[ -z "${HUB_DB_PASSWORD:-}" ]]; then
    set_env_var HUB_DB_PASSWORD "$(openssl rand -base64 24)"
    log "Generated database password"
fi
if [[ -z "${HUB_DB_ROOT_PASSWORD:-}" ]]; then
    set_env_var HUB_DB_ROOT_PASSWORD "$(openssl rand -base64 24)"
    log "Generated database root password"
fi
chmod 600 "${ENV_FILE}"
load_env

# --- 7. Start the stack ------------------------------------------------------
log "Starting stack (docker compose up -d)..."
docker compose up -d

# --- 8. Poll health for up to 2 minutes --------------------------------------
wait_for_health 120

# --- 9. Done -----------------------------------------------------------------
log "Installation complete."
log "Open https://${STATIC_IP}:${BIND_PORT}/setup to continue setup."
