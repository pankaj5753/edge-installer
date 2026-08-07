#!/usr/bin/env bash
# Refreshes the locally-downloaded install bundle on a test host (EC2, etc.)
# from S3, for repeat install.sh testing. Dev/test tooling only - never
# shipped in the hospital bundle, never run on a real hospital host.
#
# Usage: ./tools/refresh-test-bundle.sh [s3-key]
#   S3_BUCKET env var overrides the default bucket.
set -euo pipefail

S3_BUCKET="${S3_BUCKET:-bridge-dev1-bucket-edge-web-portal}"
S3_KEY="${1:-edge-install-1.0.0-linux-x64.tar.gz}"

command -v aws > /dev/null 2>&1 || { echo "aws CLI is required" >&2; exit 1; }

shopt -s nullglob
EXISTING=(edge-install-*)
shopt -u nullglob

if [[ ${#EXISTING[@]} -gt 0 ]]; then
    echo "Removing existing bundle file(s): ${EXISTING[*]}"
    rm -f "${EXISTING[@]}"
else
    echo "No existing edge-install-* file found."
fi

echo "Pulling s3://${S3_BUCKET}/${S3_KEY}..."
aws s3 cp "s3://${S3_BUCKET}/${S3_KEY}" .

if aws s3 cp "s3://${S3_BUCKET}/${S3_KEY}.sha256" . 2>/dev/null; then
    if sha256sum -c "${S3_KEY}.sha256"; then
        echo "Checksum verified."
    else
        echo "ERROR: checksum verification failed - do not extract this bundle." >&2
        exit 1
    fi
else
    echo "WARNING: no .sha256 sidecar found in S3 - skipped checksum verification." >&2
fi

echo "${S3_KEY} has been replaced with the latest version from S3."
