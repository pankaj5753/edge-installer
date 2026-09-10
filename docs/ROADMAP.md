# Edge Agent Platform Roadmap

## Completed

### Container Images

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
- [x] Jenkins CI Pipeline (dual-tag scheme)
- [x] ECR publishing - `1.0.0`

#### edge-api

- [x] Container image available
- [x] Published to ECR - `sandbox/bridge/snn-edge-api`, `1.0.0`
      (repo name standardized 2026-07-29; dual-tag scheme added 2026-07-30)
- [ ] Secret handling / entrypoint / base image fixes - deferred

#### edge-ui

- [x] Angular application development (app team)
- [x] Dockerfile
- [x] Nginx configuration
- [x] ECR publication - `sandbox/bridge/snn-edge-ui`, `1.0.0`

---

### Installer

#### Installer Repository

- [x] Create repository
- [x] Create README
- [x] Create CHANGELOG

#### Installation

- [x] install.sh (full installation sequence)
- [x] preflight.sh (CPU/RAM/disk/Docker/Compose/OpenSSL/OS + report)
- [x] health-check.sh (`lib/health-check.sh`)
- [x] generate-certs.sh (`lib/generate-certs.sh`)

#### Packaging

- [x] download-images.sh (combined archive + DIGESTS manifest)
- [x] package-release.sh
- [x] publish-bundle.sh (S3 upload + `--checksum-algorithm SHA256` +
      7-day presigned URL, `sportsmed-edge-installer-app-bucket`)

## Pending

#### Release

- [ ] Generate the first real installer bundle (all three `1.0.0` images
      now exist - not yet actually run)
- [ ] Upload bundle via `publish-bundle.sh` - not yet run for real (no
      working AWS credentials on this machine)
- [ ] S3 lifecycle/versioning for 12-month prior-version retention

#### Validation

- [ ] End-to-end `install.sh` run on a real Linux host - never done
- [ ] Upgrade testing
- [ ] Recovery testing

#### Open items

- [ ] Confirm database credential scope design
- [ ] Confirm digest manifest verification approach

---

## Future

### Release 1.0.0

edge-db, edge-api, edge-ui all at `1.0.0` - images done, bundle not yet
built/published/tested.

### Release 1.1.0

Schema migration support; edge-api secret/entrypoint fixes

### Release 2.0.0

Production hospital rollout
