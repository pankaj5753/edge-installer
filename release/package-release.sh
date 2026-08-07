#!/usr/bin/env bash
# Dev-side release tool: builds the offline installer bundle
# (edge-install-{semver}-linux-x64.tar.gz, EDG-15 AC1-3) from the current
# working tree plus the combined image archive in images/.
#
# Bundle contents match EDG-15 AC2 exactly: docker-compose.yml,
# .env.example, install.sh, uninstall.sh, preflight.sh, check-prereqs.sh
# (optional, standalone), images/ (with the combined archive + DIGESTS),
# an empty certs/, README.md, and the lib/ scripts install.sh/uninstall.sh
# depend on.
#
# Usage: ./release/package-release.sh [output-dir]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

OUT_DIR="${1:-${SCRIPT_DIR}/dist}"
VERSION="$(cat "${SCRIPT_DIR}/VERSION")"
BUNDLE_NAME="edge-install-${VERSION}-linux-x64"
STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "${STAGE_DIR}"' EXIT

ARCHIVE="${IMAGES_DIR}/edge-images-${VERSION}.tar.gz"
[[ -f "${ARCHIVE}" ]] || die "Missing ${ARCHIVE} - run: ./release/download-images.sh ${VERSION} <ui-tag> <api-tag> <db-tag>"
[[ -f "${IMAGES_DIR}/DIGESTS" ]] || die "Missing images/DIGESTS - run release/download-images.sh first"

mkdir -p "${OUT_DIR}"
BUNDLE_ROOT="${STAGE_DIR}/${BUNDLE_NAME}"
mkdir -p "${BUNDLE_ROOT}/certs" "${BUNDLE_ROOT}/images" "${BUNDLE_ROOT}/lib"

log "Staging bundle contents (EDG-15 AC2)..."
cp "${SCRIPT_DIR}/VERSION" "${BUNDLE_ROOT}/"
cp "${SCRIPT_DIR}/docker-compose.yml" "${BUNDLE_ROOT}/"
cp "${SCRIPT_DIR}/.env.example" "${BUNDLE_ROOT}/"
cp "${SCRIPT_DIR}/install.sh" "${BUNDLE_ROOT}/"
cp "${SCRIPT_DIR}/uninstall.sh" "${BUNDLE_ROOT}/"
cp "${SCRIPT_DIR}/preflight.sh" "${BUNDLE_ROOT}/"
cp "${SCRIPT_DIR}/check-prereqs.sh" "${BUNDLE_ROOT}/"
cp "${SCRIPT_DIR}/README.md" "${BUNDLE_ROOT}/"
cp "${SCRIPT_DIR}/lib/common.sh" "${SCRIPT_DIR}/lib/generate-certs.sh" "${SCRIPT_DIR}/lib/health-check.sh" "${BUNDLE_ROOT}/lib/"
cp "${ARCHIVE}" "${BUNDLE_ROOT}/images/"
cp "${IMAGES_DIR}/DIGESTS" "${BUNDLE_ROOT}/images/"
chmod +x "${BUNDLE_ROOT}"/*.sh "${BUNDLE_ROOT}"/lib/*.sh
# certs/ ships empty (EDG-15 AC2) - install.sh populates it.

log "Creating ${BUNDLE_NAME}.tar.gz..."
tar -C "${STAGE_DIR}" -czf "${OUT_DIR}/${BUNDLE_NAME}.tar.gz" "${BUNDLE_NAME}"

# Bundle-level SHA-256 for IT's manual verification step (EDG-15 AC6/AC8-9).
# CI's S3 upload with --checksum-algorithm SHA256 is a separate,
# storage-layer check performed by the release pipeline, not this script.
(cd "${OUT_DIR}" && sha256sum "${BUNDLE_NAME}.tar.gz" > "${BUNDLE_NAME}.tar.gz.sha256")

log "Bundle written to ${OUT_DIR}/${BUNDLE_NAME}.tar.gz"
log "Checksum written to ${OUT_DIR}/${BUNDLE_NAME}.tar.gz.sha256"
log "NOTE: uploading to S3 with --checksum-algorithm SHA256 and emailing the"
log "hash to the hospital IT contact is a CI/release-pipeline responsibility"
log "outside this repo (EDG-15 AC4, AC8-9)."
