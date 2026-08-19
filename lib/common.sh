#!/usr/bin/env bash
# Shared helpers sourced by install.sh, preflight.sh, and lib/*.sh.
# Not meant to be run directly.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
IMAGES_DIR="${SCRIPT_DIR}/images"
CERTS_DIR="${SCRIPT_DIR}/certs"

log()  { printf '[edge-installer] %s\n' "$*"; }
warn() { printf '[edge-installer] WARNING: %s\n' "$*" >&2; }
die()  { printf '[edge-installer] ERROR: %s\n' "$*" >&2; exit 1; }

# Loads .env into the current shell's environment, creating it from
# .env.example on first run (mode 600 - EDG-15 AC11).
load_env() {
    if [[ ! -f "${ENV_FILE}" ]]; then
        log "No .env found - creating from .env.example"
        cp "${SCRIPT_DIR}/.env.example" "${ENV_FILE}"
        chmod 600 "${ENV_FILE}"
    fi
    set -a
    # shellcheck disable=SC1090
    source "${ENV_FILE}"
    set +a
}

# Idempotently sets KEY=VALUE in .env - updates an existing line in place,
# or appends if the key isn't present yet.
set_env_var() {
    local key="$1" value="$2"
    if grep -q "^${key}=" "${ENV_FILE}" 2>/dev/null; then
        sed -i.bak "s|^${key}=.*|${key}=${value}|" "${ENV_FILE}"
        rm -f "${ENV_FILE}.bak"
    else
        printf '%s=%s\n' "${key}" "${value}" >> "${ENV_FILE}"
    fi
}

# version_ge A B --> exit 0 if A >= B (dotted-numeric version compare).
version_ge() {
    [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)" == "$1" ]]
}

os_pretty_name() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        (. /etc/os-release && echo "${PRETTY_NAME:-${ID}-${VERSION_ID}}")
    else
        echo "unknown"
    fi
}

# Supported OSes per EDG-15 AC5: Ubuntu 22.04/24.04/26.04 LTS, RHEL 8, RHEL 9.
os_supported() {
    [[ -f /etc/os-release ]] || return 1
    # shellcheck disable=SC1091
    source /etc/os-release
    case "${ID}" in
        ubuntu) [[ "${VERSION_ID}" == "22.04" || "${VERSION_ID}" == "24.04" || "${VERSION_ID}" == "26.04" ]] ;;
        rhel)   [[ "${VERSION_ID}" == 8* || "${VERSION_ID}" == 9* ]] ;;
        *)      return 1 ;;
    esac
}

# Verifies the combined image archive's SHA-256 against the value recorded
# in images/DIGESTS at release-build time (EDG-15 AC11), before docker load
# touches it. Deliberately a plain file checksum rather than a per-image
# Docker ID comparison - Docker's internal image IDs are computed
# differently across Engine versions/storage backends for identical image
# content, which caused false-positive mismatches between the build host
# and the install host.
verify_archive_checksum() {
    local archive="$1" archive_name expected actual
    archive_name="$(basename "${archive}")"
    expected="$(awk -v f="${archive_name}" '$1==f {print $2}' "${IMAGES_DIR}/DIGESTS" 2>/dev/null || true)"
    [[ -n "${expected}" ]] || die "No pinned checksum found for ${archive_name} in images/DIGESTS. See README.md Troubleshooting #6."
    actual="$(sha256sum "${archive}" | awk '{print $1}')"
    [[ "${actual}" == "${expected}" ]] || die "Checksum mismatch for ${archive_name}: expected ${expected}, got ${actual}. See README.md Troubleshooting #6."
    log "OK   - ${archive_name} checksum verified"
}

# Polls `docker compose ps` health status for all three services until
# healthy or the timeout (seconds) elapses (EDG-15 AC11).
wait_for_health() {
    local timeout="$1" elapsed=0 all_healthy svc status
    log "Waiting for containers to become healthy (up to ${timeout}s)..."
    while (( elapsed < timeout )); do
        all_healthy=1
        for svc in edge-db edge-api edge-ui; do
            status="$(docker compose ps --format '{{.Health}}' "${svc}" 2>/dev/null || true)"
            [[ "${status}" == "healthy" ]] || all_healthy=0
        done
        if [[ "${all_healthy}" -eq 1 ]]; then
            log "All containers healthy."
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    die "Containers did not become healthy within ${timeout}s. See README.md Troubleshooting #8."
}
