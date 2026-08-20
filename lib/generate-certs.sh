#!/usr/bin/env bash
# Generates the self-signed TLS certificate for edge-ui's Nginx (EDG-15
# AC11). Idempotent unless --force is passed - install.sh must not
# regenerate an existing cert on re-run (EDG-15 AC12).
#
# Usage: ./lib/generate-certs.sh --cn <static-ip> [--force]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/lib/common.sh"

CN=""
FORCE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --cn) CN="$2"; shift 2 ;;
        --force) FORCE=1; shift ;;
        *) die "Unknown argument: $1" ;;
    esac
done

[[ -n "${CN}" ]] || die "generate-certs.sh requires --cn <static-ip>"

mkdir -p "${CERTS_DIR}"

if [[ -f "${CERTS_DIR}/edge.crt" && -f "${CERTS_DIR}/edge.key" && "${FORCE}" -eq 0 ]]; then
    log "certs/edge.crt and certs/edge.key already exist - skipping (use --force to regenerate)"
    exit 0
fi

log "Generating self-signed certificate for CN/SAN=${CN}"

# "+" in the -subj value must be escaped - openssl's subject-string parser
# treats an unescaped "+" as a multi-value-RDN separator (RFC 2253), which
# silently breaks on the literal "Smith+Nephew" organization name.
if ! OPENSSL_OUTPUT="$(openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout "${CERTS_DIR}/edge.key" \
    -out "${CERTS_DIR}/edge.crt" \
    -days 825 \
    -subj "/CN=${CN}/O=Smith\+Nephew Edge Agent" \
    -addext "subjectAltName=IP:${CN}" 2>&1)"; then
    warn "${OPENSSL_OUTPUT}"
    die "Certificate generation failed. See README.md Troubleshooting #10."
fi

chmod 600 "${CERTS_DIR}/edge.crt" "${CERTS_DIR}/edge.key"

log "Wrote certs/edge.crt and certs/edge.key (mode 600)"
log "NOTE: self-signed - IT verifies the printed fingerprint on first connection (EDG-15 AC11/AC14)."

# --- edge-api internal keystore (container-to-container only) -------------
# Nginx proxies to edge-api over HTTPS but with proxy_ssl_verify off - this
# keystore only satisfies Spring's server.ssl.enabled requirement, it is
# never identity-checked. CN/SAN are therefore arbitrary, unlike edge.crt
# above (which IS checked, by IT via the printed fingerprint).
KEYSTORE="${CERTS_DIR}/keystore.p12"
if [[ -f "${KEYSTORE}" && "${FORCE}" -eq 0 ]]; then
    log "certs/keystore.p12 already exists - skipping (use --force to regenerate)"
else
    log "Generating internal TLS keystore for edge-api"

    KEYSTORE_TMP="$(mktemp -d)"
    trap 'rm -rf "${KEYSTORE_TMP}"' EXIT

    if ! OPENSSL_OUTPUT="$( { openssl req -x509 -nodes -newkey rsa:2048 \
        -keyout "${KEYSTORE_TMP}/edge-api.key" \
        -out "${KEYSTORE_TMP}/edge-api.crt" \
        -days 825 \
        -subj "/CN=edge-api/O=Smith\+Nephew Edge Agent" \
        -addext "subjectAltName=DNS:edge-api" && \
      openssl pkcs12 -export \
        -in "${KEYSTORE_TMP}/edge-api.crt" \
        -inkey "${KEYSTORE_TMP}/edge-api.key" \
        -name edge-api \
        -out "${KEYSTORE}" \
        -passout pass:changeit; } 2>&1)"; then
        warn "${OPENSSL_OUTPUT}"
        die "Keystore generation failed. See README.md Troubleshooting #10."
    fi

    # Mode 644 (not 600 like edge.crt/edge.key above): edge-api's container
    # runs entirely as a non-root uid with no root/worker privilege split
    # (unlike nginx), so it must be able to read this bind-mounted file
    # directly. Safe to relax since, per the comment above, this artifact
    # is never identity-checked.
    chmod 644 "${KEYSTORE}"
    log "Wrote certs/keystore.p12 (mode 644)"
fi
