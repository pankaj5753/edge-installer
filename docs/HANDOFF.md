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

Implemented against the finalized EDG-15/EDG-16 acceptance criteria.
**First fully successful end-to-end install completed 2026-08-07** - all
three containers healthy, setup wizard reachable in a browser. See
Pending Items below for remaining gaps and history.

Completed:

- Bundle layout matching EDG-15 AC2
- `install.sh` implementing the full EDG-15 AC11 sequence
- `uninstall.sh` (keeps data by default; `--purge-data` for a full wipe)
- `preflight.sh` (CPU/RAM/disk/Docker/Compose/OS checks + report), with an
  opt-in prompt to auto-install missing software when internet is
  available (ADR-017)
- Idempotent re-run behavior (AC12), offline-first by default with the
  ADR-017 opt-in exception (AC13), audit logging (AC16, shared via
  `lib/common.sh`'s `setup_audit_log`), numbered troubleshooting (AC17)
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
  - Progress: install.sh got all the way through `docker compose up -d`
    for the first time, 2026-08-07. All three containers attempted;
    edge-db came up healthy, edge-api came up running but reported
    "unhealthy," and edge-ui was never created at all.
  4. edge-api's `docker-compose.yml` healthcheck used `wget --spider`, but
     `wget` isn't present in the `amazoncorretto:21` base image (confirmed
     via `docker exec` - `which`/`wget` both missing; `curl` and `bash`
     are). The healthcheck was failing on a missing binary, not on actual
     app health - Spring Boot had fully started, connected to `edge-db`,
     and was serving on 8080. Because `edge-ui`'s compose service has
     `depends_on: edge-api: condition: service_healthy`, this alone was
     enough to block edge-ui from ever starting. Fixed: healthcheck now
     uses `curl -f`, confirmed present in the image.
  - Separately, and NOT fixed here (application-level, edge-api's own
    scope per the standing agreement to defer edge-api internals):
    edge-api's logs show repeating `Table 'edge_agent.file_uploads'
    doesn't exist` errors from two `@Scheduled` jobs - a DB
    schema/migration gap, not a containerization issue. Doesn't appear to
    affect `/actuator/health` (DB connectivity itself is fine), but
    flagging for the edge-api app team.
  - Re-tested 2026-08-07: curl fix confirmed working - edge-api now
    reports healthy and edge-ui started. edge-ui itself then reported
    unhealthy, so `wait_for_health` still timed out overall.
  5. edge-ui's healthcheck (`pgrep -x nginx`) never matched, even though
     nginx logs proved it was running - nginx rewrites its own process
     title to `nginx: master process ...` at startup (standard nginx
     behavior), and Alpine's `pgrep -x` matches against that full
     rewritten command line, not the short process name, so an exact
     match against literal `nginx` can never succeed. Container had been
     unhealthy since creation, not just this run. Fixed: dropped `-x` for
     a substring match, still a process-level check per EDG-16 AC7's
     intent.
  - **Re-tested 2026-08-07: first fully successful end-to-end install.**
    All three containers came up healthy, `install.sh` completed, and the
    setup wizard was reachable in a browser. First time the full EDG-15
    AC11 sequence has run clean on a real host.
- `release/download-images.sh` / `package-release.sh` / `publish-bundle.sh`
  had never been run for real until 2026-08; issues above found by actual
  execution, not by reading.

**New capabilities added 2026-08-07, after the first successful install:**
- `uninstall.sh`: stops/removes the containers, images, and `edge-net`
  network. Keeps DB data, logs, and the TLS cert by default; `--purge-data`
  does a full, irreversible wipe. Shipped in the bundle now
  (`package-release.sh` updated to include it and `lib/install-prereqs.sh`).
- Opt-in automatic prerequisite installation (ADR-017): `preflight.sh` now
  offers to install missing Docker/Compose/OpenSSL via the OS package
  manager when the only failures are software (not CPU/RAM/disk/OS) and a
  terminal is attached - confirmed with the client (via Veera) that
  hospital hosts may sometimes have internet access, unlike the original
  EDG-15 AC13 assumption. Declining or running non-interactively keeps
  today's strict offline fail-fast behavior. See `lib/install-prereqs.sh`.

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

Updated 2026-08-07 - the root `Jenkinsfile` is live on the official
Jenkins instance and `install.sh` has now completed successfully
end-to-end, so both former #1 priorities are done.

1. Get a long-lived IAM user access key set up for Jenkins' S3 presigning,
   so the signed URL actually holds for the full 7 days (see "Real gaps"
   above) - AWS/Jenkins admin action.
2. Configure S3 lifecycle/versioning on `sportsmed-edge-installer-app-bucket`
   (or whichever bucket is current - confirm) for the 12-month retention
   requirement.
3. Get confirmation on ADR-012/ADR-013.
4. Post the EDG-15 and EDG-16 status updates.
5. Resolve edge-api's deferred issues (ADR-016) and the newly-found
   `file_uploads` schema gap before any hospital-facing release.
6. Test `uninstall.sh` end-to-end (both plain and `--purge-data` paths) and
   the ADR-017 auto-install prompt on a host without Docker/Compose
   pre-installed - neither has been exercised on a real host yet.

---

# Pending Follow-Ups

- Follow up on the two open questions in ADR-012/ADR-013.
- Post the EDG-15 status update.
- Draft and post the EDG-16 status update.
- edge-api ECR naming - already resolved, no action needed.
