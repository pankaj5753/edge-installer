#!/usr/bin/env bash
# Uploads a built bundle to S3 and generates the signed download URL hospital IT
# uses. Requires AWS credentials - not run on the hospital host.
#
# Usage: ./release/publish-bundle.sh [bundle-dir]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

BUNDLE_DIR="${1:-${SCRIPT_DIR}/dist}"
VERSION="$(cat "${SCRIPT_DIR}/VERSION")"
BUNDLE_NAME="snn-hub-install-${VERSION}-linux-x64"
BUNDLE_FILE="${BUNDLE_DIR}/${BUNDLE_NAME}.tar.gz"
CHECKSUM_FILE="${BUNDLE_FILE}.sha256"

S3_BUCKET="${S3_BUCKET:-sportsmed-edge-installer-app-bucket}"
S3_KEY="${BUNDLE_NAME}.tar.gz"
PRESIGN_EXPIRY_SECONDS="${PRESIGN_EXPIRY_SECONDS:-604800}"  # 7 days

command -v aws > /dev/null 2>&1 || die "aws CLI is required"
[[ -f "${BUNDLE_FILE}" ]] || die "Missing ${BUNDLE_FILE} - run release/package-release.sh first"
[[ -f "${CHECKSUM_FILE}" ]] || die "Missing ${CHECKSUM_FILE} - run release/package-release.sh first"

log "Uploading ${BUNDLE_NAME}.tar.gz to s3://${S3_BUCKET}/${S3_KEY}"
aws s3api put-object \
    --bucket "${S3_BUCKET}" \
    --key "${S3_KEY}" \
    --body "${BUNDLE_FILE}" \
    --checksum-algorithm SHA256 > /dev/null

log "Uploading checksum sidecar"
aws s3 cp "${CHECKSUM_FILE}" "s3://${S3_BUCKET}/${S3_KEY}.sha256" > /dev/null

log "Generating signed URL (requested expiry: ${PRESIGN_EXPIRY_SECONDS}s)"
PRESIGNED_URL="$(aws s3 presign "s3://${S3_BUCKET}/${S3_KEY}" --expires-in "${PRESIGN_EXPIRY_SECONDS}")"
CHECKSUM_VALUE="$(awk '{print $1}' "${CHECKSUM_FILE}")"

log "Done."
log "Bundle:  s3://${S3_BUCKET}/${S3_KEY}"
log "SHA-256: ${CHECKSUM_VALUE}"
log "Signed URL (send both this and the SHA-256 above to the hospital IT contact):"
log "  ${PRESIGNED_URL}"
log ""
warn "If these are temporary/assumed-role credentials, the URL's real"
warn "validity is capped at that session's remaining lifetime, not the"
warn "full 7 days requested - use long-lived IAM user credentials for a"
warn "genuine 7-day window."
