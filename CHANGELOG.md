# Changelog

All notable changes to edge-installer are documented here.
Format based on [Keep a Changelog](https://keepachangelog.com/), versioning
per semantic versioning.

## [Unreleased]

### Added

- `preflight.sh` and `check-prereqs.sh` now accept **Ubuntu 26.04 LTS** as a
  supported OS, alongside the existing Ubuntu 22.04/24.04 LTS and RHEL 8/9.
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
- `lib/generate-certs.sh` now self-heals if `certs/keystore.p12` is a
  directory instead of a file (the exact artifact the bug above used to
  leave behind, and which Docker's bind mount creates any time this file
  is missing when `docker compose up` runs) - it's removed automatically,
  with a warning, before generation is attempted, instead of failing with
  an opaque `pkcs12: Can't open ... Is a directory` error.

### Changed

- Rewrote `README.md` for its actual audience: it ships inside the bundle
  and is read by hospital IT, not engineering. Removed internal ticket/ADR
  references, release-pipeline instructions, and implementation detail
  (e.g. the internal edge-api keystore) that a hospital installer doesn't
  need to know about; kept the numbered Troubleshooting section's meaning
  and ordering unchanged since `install.sh`/`preflight.sh`/etc. reference
  those numbers directly. The release-engineer-facing "building a release
  bundle" instructions moved out of scope for this file entirely (that
  audience should read `release/*.sh`'s own comments instead).
- Bundle now loads a **single combined, gzipped image archive**
  (`images/edge-images-{semver}.tar.gz`, `docker save img1 img2 img3 |
  gzip`) instead of separate per-image tarballs.
- Added post-load **image digest verification** against a `images/DIGESTS`
  manifest — aborts on mismatch.
- **Removed the API-only / edge-ui-optional install mode** (previous
  Compose `ui` profile). Bundle format ships all three images
  together with no partial-install path; `images/PLACEHOLDER-edge-ui.md`
  is now a release-blocker note rather than a runtime fallback.
- Renamed image tag variables to `UI_IMAGE_TAG` / `API_IMAGE_TAG` /
  `DB_IMAGE_TAG`; image repo names (`snn-edge-ui`,
  `snn-edge-api`, `snn-edge-db`) are now fixed in `docker-compose.yml`.
- `preflight.sh` rewritten to check CPU (>=4 cores), RAM (>=8GB), disk
  (>=100GB), Docker Engine (>=24), Docker Compose (>=2.20), OpenSSL, and
  supported OS (Ubuntu 22.04/24.04 LTS, RHEL 8/9); writes
  `preflight-report.txt` with remediation hints.
- `install.sh` rewritten to match installation sequence: preflight
  → load+verify images → prompt for static IP/bind port → TLS cert +
  fingerprint → DB credentials → `compose up` → 2-minute health poll →
  print setup URL. Adds audit logging to `/var/log/edge-agent/install.log`
  and troubleshooting-section references in error messages.
- Cert files renamed `certs/edge.crt` / `certs/edge.key`, both mode 600,
  SAN now `IP:<static-ip>` instead of `DNS:<hostname>`.
- Healthchecks corrected: Nginx checks its own
  process (was a raw TCP probe), Spring Boot hits `GET /actuator/health`
  directly, and `retries: 3` everywhere (was 12) so Docker restarts after
  3 consecutive failures.
- Added a shared `edge-logs` volume mounted at `/var/log/edge-snn` in
  edge-ui and edge-api, plus `LOG_RETENTION_DAYS` in `.env.example`.
  Enforcement (logrotate) is provided as an opt-in example
  under `config/`, not auto-installed.
- Moved `generate-certs.sh` and `health-check.sh` into `lib/` so the
  bundle's top-level contents match specification (`docker-compose.yml`,
  `.env.example`, `install.sh`, `preflight.sh`, `images/`, `certs/`,
  `README.md`).
- README rewritten with a numbered troubleshooting guide
  and an explicit "out of scope" section for what belongs in the
  edge-ui/edge-api/edge-db repos and the CI pipeline instead.

### Known gaps / open items

- Image naming confirmed as `snn-edge-ui` / `snn-edge-api` / `snn-edge-db` - resolves the earlier discrepancy with example commands and older names.
- edge-ui image not yet delivered; no valid release bundle can be cut
  until it exists (see `images/PLACEHOLDER-edge-ui.md`).
- CI/S3 publication, signed URLs, 7-day expiry, and 12-month retention
  are release-pipeline responsibilities outside this repo.
- Schema migration tooling is out of scope — owned by edge-db.

## [0.1.0] - initial scaffold

- Initial edge-installer scaffold before validation against acceptance criteria.
