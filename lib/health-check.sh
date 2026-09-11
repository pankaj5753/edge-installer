#!/usr/bin/env bash
# On-demand health snapshot for the running stack. Run any time after
# install to check status; install.sh uses wait_for_health() in common.sh
# for its own timed poll rather than this script.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/lib/common.sh"

load_env
cd "${SCRIPT_DIR}"

FAILED=0
log "Checking service health..."
for svc in hub-db hub-api hub-ui; do
    status=$(docker compose ps --format '{{.Health}}' "${svc}" 2>/dev/null || true)
    if [[ "${status}" == "healthy" ]]; then
        log "OK   - ${svc} is healthy"
    elif [[ -z "${status}" ]]; then
        printf '[hub-installer] FAIL - %s is not running\n' "${svc}" >&2
        FAILED=1
    else
        printf '[hub-installer] FAIL - %s is %s\n' "${svc}" "${status}" >&2
        FAILED=1
    fi
done

if [[ "${FAILED}" -ne 0 ]]; then
    die "One or more services are unhealthy. Check 'docker compose logs' or Smith-Nephew-Hub-Installation-Guide.md Troubleshooting #8."
fi

log "All services are healthy."
