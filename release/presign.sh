#!/usr/bin/env bash
# Regenerates a presigned download URL for an already-published bundle,
# without re-uploading anything. Useful when the original URL from
# publish-bundle.sh expired early - see that script's warning: real
# validity is capped by the signing credentials' own lifetime, not just
# --expires-in.
#
# Usage: ./release/presign.sh [bundle-dir]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

BUNDLE_DIR="${1:-${SCRIPT_DIR}/dist}"
VERSION="$(cat "${SCRIPT_DIR}/VERSION")"
BUNDLE_NAME="edge-install-${VERSION}-linux-x64"
CHECKSUM_FILE="${BUNDLE_DIR}/${BUNDLE_NAME}.tar.gz.sha256"

S3_BUCKET="${S3_BUCKET:-sportsmed-edge-installer-app-bucket}"
S3_KEY="${BUNDLE_NAME}.tar.gz"
PRESIGN_EXPIRY_SECONDS="${PRESIGN_EXPIRY_SECONDS:-604800}"  # 7 days, EDG-15 Step 1

command -v aws > /dev/null 2>&1 || die "aws CLI is required"

log "Confirming s3://${S3_BUCKET}/${S3_KEY} still exists..."
aws s3api head-object --bucket "${S3_BUCKET}" --key "${S3_KEY}" > /dev/null \
    || die "Not found in S3 - run download-images.sh, package-release.sh, and publish-bundle.sh first"

log "Generating fresh signed URL (requested expiry: ${PRESIGN_EXPIRY_SECONDS}s)"
PRESIGNED_URL="$(aws s3 presign "s3://${S3_BUCKET}/${S3_KEY}" --expires-in "${PRESIGN_EXPIRY_SECONDS}")"

if [[ -f "${CHECKSUM_FILE}" ]]; then
    CHECKSUM_VALUE="$(awk '{print $1}' "${CHECKSUM_FILE}")"
else
    warn "Local checksum file not found - fetching the one already in S3 instead"
    CHECKSUM_VALUE="$(aws s3 cp "s3://${S3_BUCKET}/${S3_KEY}.sha256" - | awk '{print $1}')"
fi

log "Bundle:  s3://${S3_BUCKET}/${S3_KEY}"
log "SHA-256: ${CHECKSUM_VALUE}"
log "Signed URL:"
log "  ${PRESIGNED_URL}"
log ""
warn "Same caveat as publish-bundle.sh: real validity is capped by these"
warn "credentials' own lifetime, not just --expires-in."
