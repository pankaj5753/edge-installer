# Handoff Document

## Project Name

Smith+Nephew Edge Agent Platform

---

# Business Objective

Provide a hospital-deployable Edge Agent platform that operates without requiring internet access during installation.

The final installation package should allow Hospital IT to install:

- edge-ui
- edge-api
- edge-db

using a single installation bundle.

---

# Architecture

```text
edge-ui
(Angular + Nginx)
      ↓

edge-api
(Spring Boot + Corretto 21)
      ↓

edge-db
(MySQL 8)
```

Hospital installation bundle:

```text
edge-install-x.y.z-linux-x64.tar.gz

├── docker-compose.yml
├── .env.example
├── install.sh
├── preflight.sh
├── README.md
├── certs/              (ships empty)
├── images/             (single combined archive + digest manifest)
└── lib/                (shared install/cert/health-check scripts)
```

---

# Repositories

- `edge-installer` - installer and bundle packaging
- `edge-containers` - contains `edge-ui/`, `edge-api/`, `edge-db/`

Official source: Smith+Nephew GitLab
(`gitlab.com/smithandnephew/sportsmed/aet/edge-app/*`).

---

# Current Status

## edge-db

ECR: `sandbox/bridge/snn-edge-db`, version `1.0.0` (semantic versioning scheme - prior `1.0.4` tag predates this convention).

Jenkinsfile updated 2026-07-30 for dual-tag scheme. Otherwise complete since Phase 1: Dockerfile,
docker-compose.yml, health checks, backup/restore/status scripts, Jenkins
CI, ECR publishing all validated.

## edge-api

ECR: `sandbox/bridge/snn-edge-api`, version `1.0.0` (standardized naming 2026-07-29; Jenkinsfile
updated 2026-07-30 for dual-tag scheme).

**Known issues explicitly deferred (client-facing decision -
proceed as-is for now, must resolve before hospital shipment):**

- Development credentials baked into the image via `.env.qa` and committed to git.
- Entrypoint hardcodes `.env.qa` regardless of environment - in a 3-container
  test, edge-api will likely reach the development database instead of the local `edge-db`
  container.
- Runtime base image configuration differences from specification.

Full detail: `containerization-review-2026-07-29.md`.

## edge-ui

ECR: `sandbox/bridge/snn-edge-ui`, version `1.0.0`. Containerization added
2026-07-29 (Dockerfile, nginx.conf, docker-compose.yml, Jenkinsfile,
VERSION). First real Jenkins pipeline run succeeded 2026-07-30 after resolving:

1. Wrong npm script name in an earlier, since-abandoned Jenkinsfile draft.
2. Angular CLI 22 requires Node ≥22.22.3 - "Node 20" requirement doesn't
   work at all; both `Dockerfile` and `Jenkinsfile` use Node 22.
3. Jenkins host's glibc predates Node 18+'s requirement - the `NodeJS-22`
   tool (native binary on host) can't work regardless of version. Fixed by
   running `Install`/`Test` inside `agent { docker { image 'node:22-alpine' } }`
   instead, applied to both stages (a fix applied to only one stage is what
   caused the earlier "Test runs on host's Node 16" failure).
4. `npm ci` EACCES on `/.npm` - Jenkins' docker agent runs as an arbitrary
   host uid with no passwd entry, so `$HOME` resolves to `/`, unwritable by
   non-root. Fixed with `npm ci --cache .npm-cache` (workspace-relative).
5. `angular.json`'s `test` target had no `buildTarget` wired up at all, so
   `ng test` failed unconditionally regardless of CI config. Fixed by
   pointing it at the existing `dev` build configuration.
6. `Dockerfile` in the repo was accidentally swapped with `docker-compose.yml`
   content during a manual edit - corrected.

App code itself (components, routing, wizard flow) is owned by the
edge-ui dev team.

## edge-installer

Scaffolded and implemented to specification. All three images now exist in ECR, so a real bundle can be built
- not yet actually built/tested end to end (see Pending Items below).

Completed:

- Bundle layout matching specification
- `install.sh` implementing full installation sequence
- `preflight.sh` (CPU/RAM/disk/Docker/Compose/OS checks + report)
- Idempotent re-run behavior, offline-only operation, audit
  logging, numbered troubleshooting
- `docker-compose.yml` with healthchecks, restart policy, log volume
- `release/download-images.sh`, `release/package-release.sh`,
  `release/publish-bundle.sh` (S3 upload + presigned URL, added 2026-07-30)
- Image naming standardized, dual-tag convention in place

Two bugs found and fixed 2026-07-29 in `download-images.sh`: missing ECR path prefix
and `.env.example` tag synchronization issues.

---

# Pending Items for Delivery

Cross-checked against requirements, 2026-07-30.

**Genuinely untested - highest-value next step:**
- First real EC2 install attempts started 2026-08-06. Amazon Linux 2023
  host: preflight correctly failed (Compose plugin not installed on that
  host, and AL2023 is not in the supported OS list - Ubuntu
  22.04/24.04 and RHEL 8/9 only). Retried on Ubuntu 24.04: preflight
  passed cleanly.
- Two real packaging bugs found and fixed 2026-08-06:
  1. `package-release.sh` never copied the root `VERSION` file into the
     bundle - every bundle built by this script has shipped without it.
     Fixed: now copied into the bundle root.
  2. Digest mismatch on `snn-edge-ui`, reproducible identically across
     three separate builds/buckets. Root cause confirmed from Jenkins
     console log, not a stale-workspace issue: Docker's internal
     per-image ID (`docker image inspect --format '{{.Id}}'`) is computed
     differently across Docker Engine versions/storage backends for the
     exact same image content - the Jenkins host and the install host
     (Docker 29.7.2) disagreed on the same `snn-edge-ui:1.0.0` image's ID.
     `verify_digest`'s assumption that image IDs survive save/load intact
     across hosts doesn't hold in practice. Fixed: replaced per-image
     Docker-ID comparison with a plain SHA-256 checksum of the combined
     archive file itself (`verify_archive_checksum` in `lib/common.sh`),
     checked before `docker load` runs - a file checksum has nothing to
     do with Docker and is identical on every host by construction.
  3. Certificate generation failed silently (no error text at all) right
     after image loading, on Ubuntu 24.04, 2026-08-06. Root cause:
     `lib/generate-certs.sh`'s hardcoded `-subj` string contains the
     literal org name `Smith+Nephew`, and openssl's subject-string parser
     treats an unescaped `+` as a multi-value-RDN separator (RFC 2253) -
     `openssl req` failed with `Missing '=' after RDN type string 'Nephew
     Edge Agent'`, but the failure was invisible because the command
     redirected all output (including the error) to `/dev/null`. Fixed:
     escaped the `+` (`Smith\+Nephew`), and replaced the blind
     `> /dev/null 2>&1` with output capture that's only printed - via
     `die()` - on actual failure, so future openssl errors are visible
     instead of silent (README Troubleshooting #10).
  - Progress: install.sh now reaches certificate generation for the first
    time ever. Not yet past it - re-test pending confirmation the fix
    works on the real EC2 host, then continue through DB password
    generation, `docker compose up -d`, and health polling, none of which
    have been reached yet.
- `release/download-images.sh` / `package-release.sh` / `publish-bundle.sh`
  had never been run for real until 2026-08; issues above found by actual
  execution, not by reading.

**Real gaps:**
- **12-month prior-version retention**: needs S3 versioning/lifecycle
  policy on `sportsmed-edge-installer-app-bucket` - a bucket-level config,
  not a script.
- **7-day signed URL**: confirmed broken 2026-08-04 - the
  July 31 build's URL was dead within days. Jenkins signs
  with temporary credentials which expire sooner than requested.
  Needs long-lived IAM credentials scoped to the bucket for presigning.
  Workaround added: `release/presign.sh` re-signs a fresh URL for an
  already-uploaded bundle on demand.
- **Bundle CI automation**: currently a manual script run, not
  an automated CI trigger. A root `Jenkinsfile` exists to automate this.
  Acceptable for first delivery either way.
- Emailing the checksum/link to the hospital IT contact (Step 1) is a
  process step, not something to automate here.

**Explicitly deferred (not blocking, must resolve before hospital shipment):**
- edge-api's secret handling and entrypoint configuration issues.

**Unconfirmed:**
- Two open design questions on DB credential scope and digest verification approach.

**Confirmed 2026-07-31:** all three images (`snn-edge-ui`, `snn-edge-api`,
`snn-edge-db`) are in ECR at `1.0.0` with the dual-tag scheme working
correctly on all three.

The root `Jenkinsfile` is now set up on the official Jenkins instance and
pushed to GitLab, but its first build failed with empty `UI_TAG`/`API_TAG`/
`DB_TAG` parameters - expected Jenkins behavior for a brand-new
parameterized pipeline's very first run (it hasn't parsed the Jenkinsfile
to learn about the `parameters` block yet). Re-running should pick up the
`1.0.0` defaults correctly.

---

# Next Priorities

1. Set up the official Jenkins instance to run the root `Jenkinsfile`
   (parameterized: UI_TAG/API_TAG/DB_TAG) to automate
   download-images → package-release → publish-bundle. Confirm Jenkins'
   AWS credentials have S3 write access to
   `sportsmed-edge-installer-app-bucket`.
2. Until #1 is set up, run those three scripts manually (once all three
   `1.0.0` images are confirmed in ECR) to produce and publish the first
   real bundle.
3. Run `install.sh` end-to-end on a real Linux host - the single biggest
   unverified piece of this whole project.
4. Configure S3 lifecycle/versioning on `sportsmed-edge-installer-app-bucket`
   for the 12-month retention requirement.
5. Get confirmation on ADR-012/ADR-013.
6. Post the status update.
7. Resolve edge-api's deferred issues (ADR-016) before any hospital-facing
   release.

---

# Pending Follow-Ups

- Follow up on the two open design questions.
- Post the status update.
- edge-api ECR naming - already resolved, no action needed.
