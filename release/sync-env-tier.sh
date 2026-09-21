#!/usr/bin/env bash
# Merges a filtered edge-api env-tier snippet (published by edge-api's
# Jenkinsfile ECR_PUSH mode, see "Publish Env Config" stage) into this
# repo's .env.prod.example, key by key - so JWT/Okta/proxy values stay in
# sync with edge-api's own .env.<tier> instead of being hand-copied.
#
# Not run on the hospital host - dev/CI only, same as download-images.sh.
#
# Usage: ./release/sync-env-tier.sh <path-to-filtered-env-file>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

[[ $# -eq 1 ]] || die "Usage: $0 <path-to-filtered-env-file>"
SOURCE_FILE="$1"
TARGET_FILE="${SCRIPT_DIR}/.env.prod.example"

[[ -f "${SOURCE_FILE}" ]] || die "${SOURCE_FILE} not found - did the matching ECR_PUSH build publish its env-tier artifact?"
[[ -f "${TARGET_FILE}" ]] || die "${TARGET_FILE} not found - repo is corrupt."

log "Syncing keys from $(basename "${SOURCE_FILE}") into .env.prod.example..."
UPDATED=0 APPENDED=0
while IFS= read -r line || [[ -n "${line}" ]]; do
    # Skip blank lines and comments.
    [[ "${line}" =~ ^[[:space:]]*$ ]] && continue
    [[ "${line}" =~ ^[[:space:]]*# ]] && continue
    key="${line%%=*}"
    value="${line#*=}"
    [[ -n "${key}" ]] || continue

    if grep -q "^${key}=" "${TARGET_FILE}" 2>/dev/null; then
        UPDATED=$((UPDATED + 1))
    else
        APPENDED=$((APPENDED + 1))
    fi
    set_env_var "${key}" "${value}" "${TARGET_FILE}"
done < "${SOURCE_FILE}"

log "Done. ${UPDATED} key(s) updated, ${APPENDED} new key(s) appended in .env.prod.example."
