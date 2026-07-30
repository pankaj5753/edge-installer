# AI Handoff Document

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

Two repos, each tracking one JIRA story:

- **`edge-installer`** (EDG-15) - https://github.com/pankaj5753/edge-installer
- **`edge-containers`** (EDG-16) - https://github.com/pankaj5753/edge-containers
  (contains `edge-ui/`, `edge-api/`, `edge-db/`)

Both are personal GitHub mirrors, not the official repos. The official
source is Smith+Nephew's GitLab (`gitlab.com/smithandnephew/sportsmed/aet/
edge-app/*`), reachable only from the work laptop + VPN, which doesn't have
Claude Code. Workflow: fixes happen here against GitHub, then get manually
ported to GitLab from the work laptop and tested via the real Jenkins
(VPN-only). **This means GitHub and GitLab can drift** - always confirm
what's actually on GitLab before assuming a fix landed there.

`edge-installer` was local-only until 2026-07-30; both repos are now
pushed to GitHub as of this session.

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
6. `Dockerfile` on GitLab was accidentally swapped with `docker-compose.yml`
   content during manual porting - corrected.

App code itself (components, routing, wizard flow) is unowned by this
session - still the edge-ui dev team's.

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
- `install.sh` has never been run end-to-end against real, ECR-pulled
  images on a real Linux host. All testing so far is edge-ui-only, locally,
  via Docker Desktop on Windows. The full 3-container stack, `preflight.sh`
  on real Linux, and the complete install sequence are unverified.
- `release/download-images.sh` / `package-release.sh` / `publish-bundle.sh`
  have never been run for real (no working AWS credentials on this
  machine) - reviewed and fixed by reading, not by executing.

**Real gaps against EDG-15 ACs:**
- **12-month prior-version retention (AC5)**: needs S3 versioning/lifecycle
  policy on `sportsmed-edge-installer-app-bucket` - a bucket-level config,
  not a script.
- **7-day signed URL (AC1, Step 1)**: `publish-bundle.sh` requests this,
  but if run with temporary/assumed-role AWS credentials, the actual URL
  validity is capped at that session's remaining lifetime, not the full 7
  days. Use long-lived IAM user credentials to get a genuine 7-day window.
- **"CI builds the bundle once"**: currently a manual script run
  (`download-images.sh` → `package-release.sh` → `publish-bundle.sh`), not
  an automated CI trigger. Acceptable for first delivery; worth automating
  later.
- Emailing the checksum/link to the hospital IT contact (Step 1) is a
  process step, not something to automate here.

**Explicitly deferred (not blocking, must resolve before hospital shipment):**
- edge-api's secret handling and entrypoint bug (ADR-016).

**Unconfirmed:**
- Two open questions (DB password scope, digest-pinning approach) - Teams
  message drafted, not yet sent (ADR-012, ADR-013).
- Whether all three `1.0.0` images are actually confirmed pushed to ECR
  right now, or still pending a Jenkins run on the GitLab side for
  edge-api/edge-db.

---

# Next Priorities

1. Run `release/download-images.sh 1.0.0 1.0.0 1.0.0 1.0.0` (once all three
   `1.0.0` images are confirmed in ECR) → `package-release.sh` →
   `publish-bundle.sh` to produce and publish the first real bundle.
2. Run `install.sh` end-to-end on a real Linux host - the single biggest
   unverified piece of this whole project.
3. Configure S3 lifecycle/versioning on `sportsmed-edge-installer-app-bucket`
   for the 12-month retention requirement.
4. Get confirmation on ADR-012/ADR-013 (Teams message drafted, not sent).
5. Post the EDG-15 JIRA status update (drafted, not posted).
6. Resolve edge-api's deferred issues (ADR-016) before any hospital-facing
   release.

---

# Pending Human Actions

Drafted but not sent/posted - checked into `docs/drafts/`:

1. **Teams message** (ADR-012/ADR-013 open questions) -
   `docs/drafts/teams-message-open-questions.md`
2. **JIRA EDG-15 status comment** - `docs/drafts/jira-edg15-status-update.md`
3. **JIRA EDG-16 status comment** - not yet drafted
4. **Message to Naresh** (edge-api ECR naming) -
   `docs/drafts/message-naresh-ecr-consistency.md` - resolved/moot, Naresh
   already fixed this; can be marked done
