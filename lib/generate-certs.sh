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
