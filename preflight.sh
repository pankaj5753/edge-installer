#!/usr/bin/env bash
# Verifies the host meets the requirements before install.sh touches anything.
# Writes preflight-report.txt and aborts on any failure. Safe to run
# repeatedly and on its own.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

REPORT="${SCRIPT_DIR}/preflight-report.txt"
FAILED=0

printf 'Smith+Nephew Hub preflight report - %s\n\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "${REPORT}"

# record <PASS|FAIL> <description> [remediation]
record() {
    local status="$1" desc="$2" remediation="${3:-}"
    printf '[%s] %s\n' "${status}" "${desc}" >> "${REPORT}"
    if [[ "${status}" == "PASS" ]]; then
        log "PASS - ${desc}"
    else
        printf '[hub-installer] FAIL - %s\n' "${desc}" >&2
        if [[ -n "${remediation}" ]]; then
            printf '[hub-installer]        Remediation: %s\n' "${remediation}" >&2
            printf '    Remediation: %s\n' "${remediation}" >> "${REPORT}"
        fi
        FAILED=1
    fi
}

log "Running preflight checks..."

# --- CPU ---------------------------------------------------------------
CPU_COUNT="$(nproc 2>/dev/null || echo 0)"
if [[ "${CPU_COUNT}" -ge 4 ]]; then
    record PASS "CPU cores: ${CPU_COUNT} (>= 4 required)"
else
    record FAIL "CPU cores: ${CPU_COUNT} (>= 4 required)" "Provision a host with at least 4 vCPUs."
fi

# --- RAM ---------------------------------------------------------------
RAM_KB="$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
RAM_GB=$(( RAM_KB / 1024 / 1024 ))
if [[ "${RAM_KB}" -ge 8388608 ]]; then
    record PASS "RAM: ${RAM_GB}GB (>= 8GB required)"
else
    record FAIL "RAM: ${RAM_GB}GB (>= 8GB required)" "Provision a host with at least 8GB RAM."
fi

# --- Disk (sized for loaded images plus headroom) -----------------------
AVAIL_KB="$(df -Pk "${SCRIPT_DIR}" | awk 'NR==2 {print $4}')"
AVAIL_GB=$(( AVAIL_KB / 1024 / 1024 ))
if [[ "${AVAIL_KB}" -ge 104857600 ]]; then
    record PASS "Available disk: ${AVAIL_GB}GB (>= 100GB required)"
else
    record FAIL "Available disk: ${AVAIL_GB}GB (>= 100GB required)" "Free up disk space, or install to a volume with >= 100GB available."
fi

# --- Docker Engine >= 24 ------------------------------------------------
if command -v docker > /dev/null 2>&1 && DOCKER_VERSION="$(docker version --format '{{.Server.Version}}' 2>/dev/null)" && [[ -n "${DOCKER_VERSION}" ]]; then
    if version_ge "${DOCKER_VERSION}" "24.0.0"; then
        record PASS "Docker Engine: ${DOCKER_VERSION} (>= 24 required)"
    else
        record FAIL "Docker Engine: ${DOCKER_VERSION} (>= 24 required)" "Upgrade Docker Engine: https://docs.docker.com/engine/install/"
    fi
else
    record FAIL "Docker Engine installed and reachable" "Install Docker Engine >= 24: https://docs.docker.com/engine/install/"
fi

# --- Docker Compose >= 2.20 ---------------------------------------------
if COMPOSE_VERSION="$(docker compose version --short 2>/dev/null)" && [[ -n "${COMPOSE_VERSION}" ]]; then
    if version_ge "${COMPOSE_VERSION}" "2.20.0"; then
        record PASS "Docker Compose: ${COMPOSE_VERSION} (>= 2.20 required)"
    else
        record FAIL "Docker Compose: ${COMPOSE_VERSION} (>= 2.20 required)" "Upgrade the Docker Compose plugin: https://docs.docker.com/compose/install/"
    fi
else
    record FAIL "Docker Compose plugin installed" "Install the Docker Compose plugin (v2.20+): https://docs.docker.com/compose/install/"
fi

# --- OpenSSL --------------------------------------------------------------
if command -v openssl > /dev/null 2>&1; then
    record PASS "OpenSSL installed ($(openssl version))"
else
    record FAIL "OpenSSL installed" "Install openssl via your OS package manager."
fi

# --- Supported OS -------------------------------------------------------
if os_supported; then
    record PASS "OS supported: $(os_pretty_name)"
else
    record FAIL "OS supported: $(os_pretty_name)" "Supported OSes: Ubuntu 22.04 LTS, Ubuntu 24.04 LTS, Ubuntu 26.04 LTS, RHEL 8, RHEL 9."
fi

{
    echo
    if [[ "${FAILED}" -ne 0 ]]; then
        echo "Result: FAILED"
    else
        echo "Result: PASSED"
    fi
} >> "${REPORT}"

if [[ "${FAILED}" -ne 0 ]]; then
    die "Preflight checks failed. See ${REPORT} and README.md Troubleshooting for remediation."
fi

log "All preflight checks passed. Report written to $(basename "${REPORT}")"