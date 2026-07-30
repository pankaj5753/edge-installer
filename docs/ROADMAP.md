# Edge Agent Platform Roadmap

## Completed

### EDG-16

#### edge-db

- [x] Repository created
- [x] Dockerfile created
- [x] Docker Compose deployment
- [x] Health checks
- [x] Volume persistence
- [x] Backup script
- [x] Restore script
- [x] Status script
- [x] README
- [x] Deployment Guide
- [x] Jenkins CI Pipeline (dual-tag scheme, ADR-015)
- [x] ECR publishing - `1.0.0`

#### edge-api

- [x] Container image available
- [x] Published to ECR - `sandbox/bridge/snn-edge-api`, `1.0.0`
      (repo name fixed 2026-07-29; dual-tag scheme added 2026-07-30)
- [ ] Secret handling / entrypoint / base image fixes - deferred, ADR-016

#### edge-ui

- [x] Angular application development (app team)
- [x] Dockerfile
- [x] Nginx configuration
- [x] ECR publication - `sandbox/bridge/snn-edge-ui`, `1.0.0`

---

### EDG-15

#### Installer Repository

- [x] Create repository - `github.com/pankaj5753/edge-installer`
- [x] Create README
- [x] Create CHANGELOG

#### Installation

- [x] install.sh (full EDG-15 AC11 sequence)
- [x] preflight.sh (CPU/RAM/disk/Docker/Compose/OpenSSL/OS + report)
- [x] health-check.sh (`lib/health-check.sh`)
- [x] generate-certs.sh (`lib/generate-certs.sh`)

#### Packaging

- [x] download-images.sh (combined archive + DIGESTS manifest)
- [x] package-release.sh
- [x] publish-bundle.sh (S3 upload + `--checksum-algorithm SHA256` +
      7-day presigned URL, `sportsmed-edge-installer-app-bucket`)

## Pending

#### Release (EDG-15)

- [ ] Generate the first real installer bundle (all three `1.0.0` images
      now exist - not yet actually run)
- [ ] Upload bundle via `publish-bundle.sh` - not yet run for real (no
      working AWS credentials on this machine)
- [ ] S3 lifecycle/versioning for 12-month prior-version retention (AC5)

#### Validation (EDG-15)

- [ ] End-to-end `install.sh` run on a real Linux host - never done
- [ ] Upgrade testing
- [ ] Recovery testing

#### Open items (EDG-15)

- [ ] Confirm ADR-012 (DB password vs. facility credentials split)
- [ ] Confirm ADR-013 (digest manifest vs. compose-pinned digest)

---

## Future

### Release 1.0.0

edge-db, edge-api, edge-ui all at `1.0.0` - images done, bundle not yet
built/published/tested.

### Release 1.1.0

Schema migration support; edge-api secret/entrypoint fixes (ADR-016)

### Release 2.0.0

Production hospital rollout
