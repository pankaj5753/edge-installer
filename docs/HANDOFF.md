# Handoff Document

## Project Name

Smith+Nephew Edge Agent Platform

## Related Stories

EDG-16 - Dockerize Edge Agent Deployment on Linux (Three-Container Stack)

EDG-15 - Edge Agent Setup at Hospital Facility

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
├── images/             (single combined archive + digest manifest, ADR-014)
└── lib/                (shared install/cert/health-check scripts)
```

---

# Repositories

- `edge-installer` (EDG-15)
- `edge-containers` (EDG-16) - contains `edge-ui/`, `edge-api/`, `edge-db/`

Official source: Smith+Nephew GitLab
(`gitlab.com/smithandnephew/sportsmed/aet/edge-app/*`).

---

# Current Status

## edge-db

ECR: `sandbox/bridge/snn-edge-db`, version `1.0.0` (ADR-015 - the prior
`1.0.4` tag predates the tagging convention and is superseded, not
continued).

Jenkinsfile updated 2026-07-30 for the dual-tag scheme (`VERSION` file
added, per-build tag added). Otherwise complete since Phase 1: Dockerfile,
docker-compose.yml, health checks, backup/restore/status scripts, Jenkins
CI, ECR publishing all validated.

## edge-api

ECR: `sandbox/bridge/snn-edge-api`, version `1.0.0` (repo name fixed by
Naresh 2026-07-29, correcting the old `sandbox/bridge/snn-edge`; Jenkinsfile
tagging updated 2026-07-30 for the dual-tag scheme).

**Known issues explicitly deferred (ADR-016, client-facing decision -
proceed as-is for now, must resolve before hospital shipment):**

- Real Okta client secret + RDS DB password baked into the image via
  `.env.qa`, and committed to git (containerization review Finding 1).
- Entrypoint hardcodes `.env.qa` regardless of environment - in a 3-container
  test, edge-api will likely reach the real QA RDS, not the local `edge-db`
  container (Finding 2).
- Runtime base image is full `amazoncorretto:21`, not the JRE Alpine variant
  EDG-16 AC2 specifies (Finding 7).

Full detail: `containerization-review-2026-07-29.md`.

## edge-ui

ECR: `sandbox/bridge/snn-edge-ui`, version `1.0.0`. Containerization added
2026-07-29 (Dockerfile, nginx.conf, docker-compose.yml, Jenkinsfile,
VERSION) - closed containerization review Findings 3 and 4. First real
Jenkins pipeline run succeeded 2026-07-30 after fixing, in order:

1. Wrong npm script name in an earlier, since-abandoned Jenkinsfile draft.
2. Angular CLI 22 requires Node ≥22.22.3 - EDG-16 AC1's "Node 20" doesn't
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

## edge-installer (EDG-15)

Scaffolded and implemented against the finalized EDG-15/EDG-16 acceptance
criteria. All three images now exist in ECR, so a real bundle can be built
- not yet actually built/tested end to end (see Pending Items below).

Completed:

- Bundle layout matching EDG-15 AC2
- `install.sh` implementing the full EDG-15 AC11 sequence
- `preflight.sh` (CPU/RAM/disk/Docker/Compose/OS checks + report)
- Idempotent re-run behavior (AC12), offline-only operation (AC13), audit
  logging (AC16), numbered troubleshooting (AC17)
- `docker-compose.yml` per EDG-16 (healthchecks, restart policy, log volume)
- `release/download-images.sh`, `release/package-release.sh`,
  `release/publish-bundle.sh` (S3 upload + presigned URL, added 2026-07-30)
- Image naming confirmed (ADR-011), dual-tag convention (ADR-015)

Two bugs found and fixed 2026-07-29 in `download-images.sh` before its
first real run: missing `sandbox/bridge/` prefix on the ECR pull path, and
`.env.example` tags never syncing with what was actually pulled.

---

# Pending Items for Delivery

Cross-checked against EDG-15's acceptance criteria, 2026-07-30.

**Genuinely untested - highest-value next step:**
- First real EC2 install attempts started 2026-08-06. Amazon Linux 2023
  host: preflight correctly failed (Compose plugin not installed on that
  host, and AL2023 is not in EDG-15 AC5's supported OS list - Ubuntu
  22.04/24.04 and RHEL 8/9 only). Retried on Ubuntu 24.04: preflight
  passed cleanly.
- Two real packaging bugs found and fixed 2026-08-06:
  1. `package-release.sh` never copied the root `VERSION` file into the
     bundle - every bundle built by this script has shipped without it.
     Fixed: now copied into the bundle root.
  2. Digest mismatch on `snn-edge-ui` when installing a bundle from a
     second Jenkins trigger (same images, published to a new S3 bucket).
     Root cause: `images/edge-images-{ver}.tar.gz` and `images/DIGESTS`
     must come from the same `download-images.sh` run to match - a
     re-triggered Jenkins build reusing a workspace can leave a stale file
     from an earlier run paired with a fresh one from the new run. Fixed:
     `download-images.sh` now deletes any leftover archive/DIGESTS at the
     start of every run, so a fresh run can never mix with stale files.
  - Not yet re-tested end-to-end with a freshly-built bundle since these
    fixes landed - still the highest-value next step.
- `release/download-images.sh` / `package-release.sh` / `publish-bundle.sh`
  had never been run for real until 2026-08; issues above found by actual
  execution, not by reading.

**Real gaps against EDG-15 ACs:**
- **12-month prior-version retention (AC5)**: needs S3 versioning/lifecycle
  policy on `sportsmed-edge-installer-app-bucket` - a bucket-level config,
  not a script.
- **7-day signed URL (AC1, Step 1)**: confirmed broken 2026-08-04 - the
  July 31 build's URL was dead within days (`ExpiredToken`). Jenkins signs
  with temporary/STS credentials (`ASIA...` + security token, confirmed
  from the actual URL), which cap real validity regardless of
  `--expires-in`. Needs a long-lived IAM user access key (`AKIA...`)
  scoped to just this bucket, used specifically for presigning - an
  AWS/Jenkins credentials change, not a script fix. Workaround added:
  `release/presign.sh` re-signs a fresh URL for an already-uploaded
  bundle on demand, without rebuilding/republishing anything.
- **"CI builds the bundle once"**: currently a manual script run
  (`download-images.sh` → `package-release.sh` → `publish-bundle.sh`), not
  an automated CI trigger. A root `Jenkinsfile` exists to automate this
  once set up on the official Jenkins instance. Acceptable for first
  delivery either way.
- Emailing the checksum/link to the hospital IT contact (Step 1) is a
  process step, not something to automate here.

**Explicitly deferred (not blocking, must resolve before hospital shipment):**
- edge-api's secret handling and entrypoint bug (ADR-016).

**Unconfirmed:**
- Two open questions (DB password scope, digest-pinning approach) - see
  ADR-012, ADR-013.

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
6. Post the EDG-15 status update.
7. Resolve edge-api's deferred issues (ADR-016) before any hospital-facing
   release.

---

# Pending Follow-Ups

- Follow up on the two open questions in ADR-012/ADR-013.
- Post the EDG-15 status update.
- Draft and post the EDG-16 status update.
- edge-api ECR naming - already resolved, no action needed.
