# Changelog

All notable changes to edge-installer are documented here.
Format based on [Keep a Changelog](https://keepachangelog.com/), versioning
per ADR-008 / EDG-15 AC5 (semantic versioning).

## [Unreleased]

### Added

- `preflight.sh` and `check-prereqs.sh` now accept **Ubuntu 26.04 LTS** as a
  supported OS, alongside the existing Ubuntu 22.04/24.04 LTS and RHEL 8/9
  (EDG-15 AC5).
- `lib/generate-certs.sh` now also generates `certs/keystore.p12`, a
  self-signed PKCS12 keystore edge-api uses to serve HTTPS on its internal,
  container-to-container-only listener (`application.yml`'s
  `server.ssl.*`), mounted read-only into the container at
  `/etc/edge-api/keystore.p12`. Idempotent alongside `edge.crt`/`edge.key`.
  edge-api's healthcheck in `docker-compose.yml` now hits
  `https://localhost:443/api/health` instead of the previous plain-HTTP
  actuator endpoint.
- Fixed `docker-compose.yml` setting the wrong env var names for edge-api's
  database connection (`SPRING_DATASOURCE_*`, which `application.yml`
  never reads) - now sets `DB_URL`/`DB_USERNAME`/`DB_PASSWORD`, the names
  it actually binds to, so the container connects to the local `edge-db`
  rather than falling through to whatever `.env.qa` bakes in.
- `edge-ui` now also publishes port 80 (`docker-compose.yml` and nginx)
  for the plain-HTTP-to-HTTPS redirect, alongside the existing 443.
- `install.sh` now force-syncs `UI_IMAGE_TAG`/`API_IMAGE_TAG`/
  `DB_IMAGE_TAG` from the bundle's `.env.example` into `.env` on every
  run, via the new `sync_image_tags` helper in `lib/common.sh`. Previously
  these were only written once (on first `.env` creation) and never
  refreshed, so re-running `install.sh` with a newer bundle over an
  already-installed host silently kept running the old images - `.env`'s
  stale tags pointed `docker-compose.yml` at whatever was already cached
  locally instead of the newly-loaded images.

### Fixed

- `lib/generate-certs.sh` exited immediately after logging "certs/edge.crt
  and certs/edge.key already exist - skipping", before ever reaching the
  `keystore.p12` generation block added below it - so on any host that
  already had `edge.crt`/`edge.key` from a prior install, `keystore.p12`
  was never created. Docker's bind mount then silently created an empty
  *directory* at that path instead of failing, which edge-api's Spring
  Boot then tried to parse as a PKCS12 keystore (`Tag number over 30 is
  not supported`), crash-looping. The pre-existing-cert branch no longer
  exits early - it now falls through to the keystore check either way.

### Changed (revised against EDG-15 and EDG-16 acceptance criteria)

- Bundle now loads a **single combined, gzipped image archive**
  (`images/edge-images-{semver}.tar.gz`, `docker save img1 img2 img3 |
  gzip`) instead of separate per-image tarballs, per EDG-15 AC3.
- Added post-load **image digest verification** against a `images/DIGESTS`
  manifest — aborts on mismatch (EDG-15 AC11).
- **Removed the API-only / edge-ui-optional install mode** (previous
  Compose `ui` profile). EDG-15's bundle format ships all three images
  together with no partial-install path; `images/PLACEHOLDER-edge-ui.md`
  is now a release-blocker note rather than a runtime fallback.
- Renamed image tag variables to `UI_IMAGE_TAG` / `API_IMAGE_TAG` /
  `DB_IMAGE_TAG` (EDG-16 AC3); image repo names (`snn-edge-ui`,
  `snn-edge-api`, `snn-edge-db`) are now fixed in `docker-compose.yml`.
- `preflight.sh` rewritten to check CPU (>=4 cores), RAM (>=8GB), disk
  (>=100GB), Docker Engine (>=24), Docker Compose (>=2.20), OpenSSL, and
  supported OS (Ubuntu 22.04/24.04 LTS, RHEL 8/9); writes
  `preflight-report.txt` with remediation hints (EDG-15 AC11).
- `install.sh` rewritten to match EDG-15 AC11's exact sequence: preflight
  → load+verify images → prompt for static IP/bind port → TLS cert +
  fingerprint → DB credentials → `compose up` → 2-minute health poll →
  print setup URL. Adds audit logging to `/var/log/edge-agent/install.log`
  (AC16) and troubleshooting-section references in error messages (AC17).
- Cert files renamed `certs/edge.crt` / `certs/edge.key`, both mode 600,
  SAN now `IP:<static-ip>` instead of `DNS:<hostname>` (EDG-15 AC11).
- Healthchecks corrected to match EDG-16 AC7: Nginx checks its own
  process (was a raw TCP probe), Spring Boot hits `GET /actuator/health`
  directly, and `retries: 3` everywhere (was 12) so Docker restarts after
  3 consecutive failures as specified.
- Added a shared `edge-logs` volume mounted at `/var/log/edge-snn` in
  edge-ui and edge-api, plus `LOG_RETENTION_DAYS` in `.env.example`
  (EDG-16 AC10). Enforcement (logrotate) is provided as an opt-in example
  under `config/`, not auto-installed — not part of EDG-15's install.sh
  sequence.
- Moved `generate-certs.sh` and `health-check.sh` into `lib/` so the
  bundle's top-level contents match EDG-15 AC2 exactly (`docker-compose.yml`,
  `.env.example`, `install.sh`, `preflight.sh`, `images/`, `certs/`,
  `README.md`).
- README rewritten with a numbered troubleshooting guide (EDG-15 AC17)
  and an explicit "out of scope" section for what belongs in the
  edge-ui/edge-api/edge-db repos and the CI pipeline instead.

### Known gaps / open items

- Image naming confirmed as `snn-edge-ui` / `snn-edge-api` / `snn-edge-db`
  (EDG-16 + ADR-004) - resolves the earlier discrepancy with EDG-15's
  example command and HANDOFF.md/ADR-004's older names.
- edge-ui image not yet delivered; no valid release bundle can be cut
  until it exists (see `images/PLACEHOLDER-edge-ui.md`).
- CI/S3 publication, signed URLs, 7-day expiry, and 12-month retention
  (EDG-15 AC1, AC4, AC7-9) are release-pipeline responsibilities outside
  this repo.
- Schema migration tooling (ADR-009, proposed) is out of scope — owned by
  edge-db.

## [0.1.0] - initial scaffold

- Initial edge-installer scaffold (EDG-15 / ADR-010) before validation
  against the finalized EDG-15/EDG-16 acceptance criteria.
