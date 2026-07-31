#!/usr/bin/env bash
# Dev-side release tool: pulls versioned images from ECR (ADR-002) and
# produces the single combined, gzipped archive install.sh expects
# (EDG-15 AC3): images/edge-images-{semver}.tar.gz, plus a DIGESTS manifest
# install.sh uses to verify loaded image integrity (EDG-15 AC11).
#
# Requires AWS credentials and internet access - this is NOT run on the
# hospital host (ADR-007).
#
# All three images must exist before a release can be cut.
#
# Usage:
#   AWS_REGION=us-east-1 AWS_ACCOUNT_ID=123456789012 \
#     ./release/download-images.sh <bundle-semver> <ui-tag> <api-tag> <db-tag>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

[[ $# -eq 4 ]] || die "Usage: $0 <bundle-semver> <ui-tag> <api-tag> <db-tag>"

SEMVER="$1"
UI_TAG="$2"
API_TAG="$3"
DB_TAG="$4"

: "${AWS_REGION:?Set AWS_REGION}"
: "${AWS_ACCOUNT_ID:?Set AWS_ACCOUNT_ID}"

REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

command -v aws > /dev/null 2>&1 || die "aws CLI is required"
command -v docker > /dev/null 2>&1 || die "docker is required"

log "Logging in to ECR (${REGISTRY})..."
aws ecr get-login-password --region "${AWS_REGION}" | docker login --username AWS --password-stdin "${REGISTRY}"

mkdir -p "${IMAGES_DIR}"

# ECR repository names (include the sandbox/bridge/ org prefix) vs. the
# short local names docker-compose.yml and install.sh expect once loaded.
declare -A ECR_REPOS=(
    [snn-edge-ui]="sandbox/bridge/snn-edge-ui"
    [snn-edge-api]="sandbox/bridge/snn-edge-api"
    [snn-edge-db]="sandbox/bridge/snn-edge-db"
)
declare -A TAGS=(
    [snn-edge-ui]="${UI_TAG}"
    [snn-edge-api]="${API_TAG}"
    [snn-edge-db]="${DB_TAG}"
)

LOCAL_REFS=()
for repo in snn-edge-ui snn-edge-api snn-edge-db; do
    tag="${TAGS[${repo}]}"
    remote_ref="${REGISTRY}/${ECR_REPOS[${repo}]}:${tag}"
    local_ref="${repo}:${tag}"

    log "Pulling ${remote_ref}"
    docker pull "${remote_ref}"

    # Re-tag without the registry prefix so the image loaded on the
    # hospital host matches what docker-compose.yml expects.
    docker tag "${remote_ref}" "${local_ref}"
    LOCAL_REFS+=("${local_ref}")
done

ARCHIVE="${IMAGES_DIR}/edge-images-${SEMVER}.tar.gz"
log "Saving ${LOCAL_REFS[*]} -> $(basename "${ARCHIVE}")"
docker save "${LOCAL_REFS[@]}" | gzip > "${ARCHIVE}"

log "Recording image digests to images/DIGESTS"
: > "${IMAGES_DIR}/DIGESTS"
for ref in "${LOCAL_REFS[@]}"; do
    id="$(docker image inspect "${ref}" --format '{{.Id}}')"
    printf '%s %s\n' "${ref}" "${id}" >> "${IMAGES_DIR}/DIGESTS"
done

log "Syncing .env.example with the pulled tags..."
sed -i.bak \
    -e "s|^UI_IMAGE_TAG=.*|UI_IMAGE_TAG=${UI_TAG}|" \
    -e "s|^API_IMAGE_TAG=.*|API_IMAGE_TAG=${API_TAG}|" \
    -e "s|^DB_IMAGE_TAG=.*|DB_IMAGE_TAG=${DB_TAG}|" \
    "${SCRIPT_DIR}/.env.example"
rm -f "${SCRIPT_DIR}/.env.example.bak"

log "Done. $(basename "${ARCHIVE}") and DIGESTS are in images/"
log "Next: ./release/package-release.sh to build the shippable bundle."
