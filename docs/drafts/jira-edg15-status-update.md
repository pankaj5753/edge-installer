Drafted: 2026-07-29
Status: NOT YET POSTED
Target: JIRA EDG-15 comment

---

**Status: In Progress**

**Summary**
edge-installer repo has been scaffolded end-to-end against the Step 2 install sequence (AC11) and bundle layout (AC2). Core install/preflight logic is implemented and internally verified; we're blocked from producing a real, testable release bundle until the edge-ui image is delivered.

**Completed**
- Repo structure matches the bundle contents defined in AC2 (docker-compose.yml, .env.example, install.sh, preflight.sh, images/, certs/, README.md).
- install.sh implements the full AC11 sequence: preflight → load images + verify digests → prompt for static IP/bind port → generate TLS cert + print fingerprint → generate DB credentials → docker compose up → poll health (2 min) → print setup URL.
- preflight.sh checks CPU (≥4 cores), RAM (≥8GB), disk (≥100GB), Docker Engine (≥24), Docker Compose (≥2.20), OpenSSL, and supported OS (Ubuntu 22.04/24.04 LTS, RHEL 8/9) — writes preflight-report.txt with remediation hints (AC5, AC11).
- Idempotency confirmed: re-running install.sh does not regenerate the TLS cert or DB passwords, or re-prompt for IP/port (AC12).
- Install runs entirely from local artifacts, no ECR/AWS calls (AC13).
- All install actions logged to /var/log/edge-agent/install.log for audit (AC16).
- Numbered troubleshooting guide added to README.md, referenced directly from error messages (AC17).
- Dev-side release tooling (download-images.sh, package-release.sh) builds the combined image archive and bundle per AC1/AC3.
- Image naming confirmed and finalized: snn-edge-ui / snn-edge-api / snn-edge-db.

**Blocked / Pending**
- edge-ui image has not been delivered yet — a real, ticket-compliant bundle can't be produced or tested end-to-end until all three images exist. This blocks full validation of the install flow on the supported OS list.
- CI/S3 publishing pipeline (upload with --checksum-algorithm SHA256, signed URL generation with 7-day expiry, 12-month version retention) is a separate release-pipeline task and hasn't been started (AC1, AC4, AC7–AC9).

**Open questions (raised separately, awaiting confirmation)**
- Digest verification: AC11 specifies verifying loaded image digests against values "pinned in docker-compose.yml." Since AC3 (EDG-16) requires image versions to stay configurable via .env, we've implemented digest verification via a separate manifest file instead of pinning inside docker-compose.yml itself — pending confirmation this satisfies intent.
- DB password storage: clarifying that the database password AC11 asks install.sh to write into .env is an internal/infra credential, distinct from hospital/facility credentials referenced elsewhere — confirmation requested.

**Next steps**
1. Await edge-ui image delivery, then produce the first real bundle via download-images.sh / package-release.sh.
2. Run a full end-to-end install test on each supported OS (Ubuntu 22.04, Ubuntu 24.04, RHEL 8, RHEL 9).
3. Confirm the two open items above.
4. Coordinate with the CI/release pipeline owner on S3 publishing, signed URLs, and retention (AC1, AC4, AC7–AC9).
