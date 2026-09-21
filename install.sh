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

# --- 0b. Sync APP_RELEASE_TAG into .env.prod from this bundle's VERSION ----
# (always refreshed - see sync_release_tag in lib/common.sh)
sync_release_tag

# --- 1. Preflight (writes preflight-report.txt, aborts on failure) --------
"${SCRIPT_DIR}/preflight.sh"

# --- 2. Verify archive checksum, then load images ---------------------------
ARCHIVE="${IMAGES_DIR}/hub-images-${VERSION}.tar.gz"
[[ -f "${ARCHIVE}" ]] || die "Missing ${ARCHIVE}. See Smith-Nephew-Hub-Installation-Guide.md Troubleshooting #5."
verify_archive_checksum "${ARCHIVE}"
log "Loading images from $(basename "${ARCHIVE}")..."
docker load -i "${ARCHIVE}"

# --- 3. Static LAN IP and bind port (first run only) ------------------------
if [[ -z "${STATIC_IP:-}" ]]; then
    read -r -p "Enter the static LAN IP for this host: " STATIC_IP
    [[ -n "${STATIC_IP}" ]] || die "A static IP is required. See Smith-Nephew-Hub-Installation-Guide.md Troubleshooting #7."
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

# --- 6. Docker-secret files: DB passwords + facility-credentials encryption
# key (idempotent) ------------------------------------------------------------
# Generated as standalone files under ./secrets/, not written into .env or
# .env.prod, since those are the files most likely to be copied, emailed, or
# bundled for support - see docker-compose.yml's top-level `secrets:` block
# and application.yml's configtree import. Mode 400, owned by the container's
# UID:GID (1001:1001, pinned in edge-api's Dockerfile) so only that process
# can read them. Never regenerated once present - the DB passwords are
# baked into hub-db's data volume on first init, and rotating the encryption
# key would make previously-encrypted facility/cloud credentials undecryptable.
CONTAINER_UID=1001
CONTAINER_GID=1001
mkdir -p "${SECRETS_DIR}"
chmod 700 "${SECRETS_DIR}"

generate_secret_file() {
    local file="$1" bytes="$2" label="$3"
    if [[ ! -s "${file}" ]]; then
        umask 077
        openssl rand -base64 "${bytes}" | tr -d '\n' > "${file}"
        log "Generated ${label}."
    else
        log "Existing ${label} found - keeping it."
    fi
    chown "${CONTAINER_UID}:${CONTAINER_GID}" "${file}"
    chmod 400 "${file}"
}

generate_secret_file "${SECRETS_DIR}/encryption_key" 32 "facility credentials encryption key"
generate_secret_file "${SECRETS_DIR}/db_password" 24 "database password"
generate_secret_file "${SECRETS_DIR}/db_root_password" 24 "database root password"

log "Encryption key fingerprint (record for restore verification): $(sha256sum "${SECRETS_DIR}/encryption_key" | cut -d' ' -f1)"

# --- 7. Start the stack ------------------------------------------------------
log "Starting stack (docker compose up -d)..."
docker compose up -d

# --- 8. Poll health for up to 3 minutes --------------------------------------
wait_for_health 180

# --- 9. Done -----------------------------------------------------------------
log "Installation complete."
log "Open https://${STATIC_IP}:${BIND_PORT}/setup to continue setup."
