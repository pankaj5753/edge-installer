# Containerization Review — edge-ui / edge-api / edge-db

Date: 2026-07-29
Scope: DevOps/containerization compliance against EDG-15 and EDG-16
acceptance criteria only — application/business logic is out of scope.
Source: `edge-containers/edge-containers-main/` (downloaded copies of all
three repos).

**Note on secrets**: this report deliberately does not reproduce any of
the actual secret values found in the codebase, even though they were
readable in the reviewed files. Treat every credential named below as
already compromised (see Finding 1) and rotate it regardless of any other
remediation.

**Update 2026-07-29 (later same day)**: Findings 3 and 4 (edge-ui
containerization) are addressed - `Dockerfile`, `nginx.conf`,
`docker-compose.yml`, `Jenkinsfile`, and `VERSION` added directly to the
edge-ui repo, and `environment.production.ts` was added as a minimal
unblocking fix so `ng build --configuration=production` succeeds (build
verified locally with real `npm ci` + `ng build` - output lands at
`dist/edge-ui/browser/` as the Dockerfile assumes). edge-api (Findings
1, 2, 5-9) is explicitly deferred per user direction - not addressed in
this pass. See "Recommended next steps" at the bottom for what's still

**Correction 2026-07-29 (found via a real `docker compose up --build`
run)**: EDG-16 AC1's "Node 20" is not actually achievable - Angular CLI
22 (pinned in `package.json`) requires Node `^22.22.3 || ^24.15.0 ||
>=26.0.0` and refuses to run on Node 20 at all (confirmed by the actual
build error). `Dockerfile` and `Jenkinsfile` now both use Node 22
instead - this matches what the *original* (pre-review) Jenkinsfile
already had (`NodeJS-22`) before this session incorrectly "corrected" it
to 20 to match the ticket text literally. Worth flagging back to
whoever owns EDG-16 that AC1's Node version assumption predates the
Angular 22 choice and no longer holds.
needed to actually run this pipeline (ECR repo creation, Jenkins Node 20
tool).

---

## Summary

| Repo | Dockerfile | Matches EDG-16 spec | Blocking issues |
|---|---|---|---|
| edge-db | Yes | Yes, closely | None — minor tagging nit only |
| edge-api | Yes | Partially | **Real secrets baked into the image**, entrypoint ignores environment selection |
| edge-ui | **No** | Not started | No Docker artifacts at all; production build is currently broken |

edge-db is in good shape and can serve as the reference pattern for the
other two. edge-api has real containerization work done but contains a
critical security defect. edge-ui has application code but zero
containerization — EDG-16 AC1 hasn't been started on the Docker side.

---

## Critical findings

### 1. edge-api bakes live secrets into the Docker image and commits them to git

`edge-api-EDG-16-Dockerize_EdgeApi/.gitignore` explicitly re-includes
`.env.dev` and `.env.qa`:

```
# Generic .env ignored
.env

# These are committed with real values
!.env.dev
!.env.qa
```

Both files contain live-looking credentials — an Okta OAuth client
secret and an RDS database password — committed directly to git, not
placeholders.

The `Dockerfile` then makes this worse by baking QA's copy into the
image itself:

```dockerfile
COPY .env.qa /app/.env.qa
...
ENTRYPOINT ["sh", "-c", "set -a && . /app/.env.qa && set +a && java $JAVA_OPTS ..."]
```

Anyone who can `docker pull`/`docker save`/inspect layers of this image
can extract the QA Okta client secret and DB password — regardless of
which environment the image is actually deployed to. This is a direct
violation of **EDG-16 AC6** ("No secrets are stored in the .env file or
any image") and **ADR-005** ("Do not embed credentials in images").

**Action**: rotate the exposed Okta client secret and DB password
immediately (git history retains them even if removed going forward).
Then rework config loading to pull secrets from environment/secrets
manager at runtime, never `COPY`'d into the image. edge-db's pattern
(below) is the template to follow.

### 2. edge-api's ENTRYPOINT hardcodes the QA environment regardless of how the container is launched

Independent of the above, the `ENTRYPOINT` unconditionally sources
`/app/.env.qa` on every container start:

```dockerfile
ENTRYPOINT ["sh", "-c", "set -a && . /app/.env.qa && set +a && java $JAVA_OPTS org.springframework.boot.loader.launch.JarLauncher"]
```

This runs *after* `docker-compose.yml`'s `env_file: - .env.${ENV:-dev}`
has already set the container's environment, and a shell `source`
reassigns those variables — so no matter what `ENV` is passed at
`docker compose up` time, the process actually starts with QA's Okta
domain, QA's Cognito pool, and QA's DB endpoint. A "dev" run silently
talks to QA. This needs fixing independent of the secrets issue (e.g.
select the env file by `${SPRING_PROFILES_ACTIVE}` at runtime, or better,
drop file-based secrets entirely per Finding 1).

### 3. edge-ui has no containerization artifacts at all

No `Dockerfile`, no `nginx.conf`, no `docker-compose.yml` anywhere in the
repo. The Angular application code, routing, and components exist, but
none of EDG-16 AC1's containerization requirements (two-stage Node
20/Nginx 1.27 Alpine build, custom `nginx.conf` with SPA fallback, TLS
termination, `/v1/**` and `/api/**` reverse proxy to `edge-api:8080`)
have been started. This is the single largest gap blocking EDG-15 end to
end (installer team is already blocked waiting on this image — see
`docs/HANDOFF.md`).

### 4. edge-ui's production build is currently broken

`angular.json`'s `production` configuration (the default used by
`ng build`, and what EDG-16 AC1 explicitly specifies) does a file
replacement:

```json
"production": {
  "fileReplacements": [
    { "replace": "src/environments/environment.ts",
      "with": "src/environments/environment.production.ts" }
  ]
}
```

`src/environments/` only contains `environment.ts`, `environment.dev.ts`,
`environment.qa.ts`, `environment.model.ts`, and `environment.token.ts`
— **no `environment.production.ts`**. Running `ng build` (or
`ng build --configuration=production`) as-is will fail on a missing
file. This blocks producing the static assets that would even go into a
Dockerfile's build stage — worth flagging to the edge-ui team as a
pre-requisite for any Docker work, independent of who owns the fix.

---

## Other findings

### 5. Image naming is inconsistent even within the edge-api repo itself

Three different names show up across edge-api's own files, none of which
is the confirmed `snn-edge-api` (ADR-011):

| Source | Name used |
|---|---|
| `Jenkinsfile` (`ECR_REPO`) | `sandbox/bridge/snn-edge`, tagged `snn-edge-api-${BUILD_NUMBER}` |
| `docker-compose.yml` (`image:`) | `snn/edge-api:${IMAGE_TAG}` (note the slash) |
| Confirmed (ADR-011) | `sandbox/bridge/snn-edge-api`, semver tag e.g. `2.1.0` |

This is the same underlying issue already raised with Naresh separately,
but now confirmed at the source — the Jenkinsfile is where the wrong
repo name and build-counter tagging actually originate.

### 6. edge-api and edge-db's own `docker-compose.yml` files publish ports that should be internal-only

`edge-api/docker-compose.yml` maps `8080:8080` to the host; `edge-db`'s
maps `3306:3306`. EDG-16 AC4 specifies edge-api and edge-db as
internal-only (no host port publishing) — only edge-ui's 443 is
external. These per-repo compose files are reasonable as local
single-service dev conveniences, and the canonical 3-service
orchestration is correctly scoped in `edge-installer/docker-compose.yml`
already. Worth confirming explicitly with both teams that their repo's
own `docker-compose.yml` is dev-only and never the one used for hospital
deployment, so it doesn't get promoted by mistake.

### 7. edge-api runtime image doesn't match the Alpine JRE base specified in EDG-16 AC2

Both build and runtime stages use `FROM amazoncorretto:21` (the full
Amazon Linux–based image). EDG-16 AC2 specifically calls for "Corretto 21
JRE Alpine for runtime" in the second stage. The two-stage structure and
layered JAR extraction are implemented correctly — only the runtime base
image choice deviates. Effect: a larger image than intended and a
different (non-Alpine) attack surface.

### 8. Tagging is "build-counter dressed as semver," not really semver, on both edge-api and edge-db

- edge-api: `snn-edge-api-${BUILD_NUMBER}` — not semver-shaped at all.
- edge-db: `1.0.${BUILD_NUMBER}` — *shaped* like semver but is really
  just a fixed `1.0` prefix plus a raw, ever-incrementing Jenkins build
  number. Nothing in the pipeline bumps major/minor for breaking changes
  or features, so it doesn't deliver what ADR-008 intends ("supports
  controlled upgrades").

edge-db's version is closer to compliant and lower priority to fix;
edge-api's needs to change regardless of the naming fix in Finding 5.

### 9. Log volume naming doesn't match EDG-16 AC10 / the installer's compose

`edge-api/docker-compose.yml` mounts a volume at `/var/log/edge-api`
(named `edge-logs`). EDG-16 AC10 and `edge-installer/docker-compose.yml`
expect a *shared* volume mounted at `/var/log/edge-snn` in both edge-ui
and edge-api, with retention driven by `LOG_RETENTION_DAYS`. edge-db has
no log volume at all in its compose file (MySQL logs go to stdout only,
which is fine on its own but wasn't a deliberate decision to confirm).

---

## What's already correct — use as reference patterns

- **edge-db's secret handling is the right model**: `.gitignore` excludes
  `.env`, `.env.local`, `.env.dev`, `.env.prod`; only `.env.template`
  (with `CHANGE_ME` placeholders) is committed. No real credentials in
  git or in the image. edge-api should be brought in line with this
  pattern, not the other way around.
- edge-db's `Dockerfile` `HEALTHCHECK` (`mysqladmin ping`) matches
  EDG-16 AC7 exactly, and is defined at the image level (not just in
  compose), so it works correctly however the image is later run.
- edge-db's `mysql/init.sql` creates exactly the three tables specified
  in EDG-16 AC5 / `docs/ARCHITECTURE.md`: `edge_credentials`,
  `edge_auth_sessions`, `edge_local_audit_log`.
- edge-db's ECR repo name (`sandbox/bridge/snn-edge-db`) and Jenkinsfile
  `APP_NAME` (`snn-edge-db`) already match ADR-011.
- edge-api's two-stage build structure and Spring Boot layered JAR
  extraction are implemented correctly (this is the harder part of
  AC2 to get right, and it's done right).
- edge-api runs as a non-root user (`edgeapi`, uid 1001) — good practice
  beyond what either ticket explicitly requires.
- edge-api's healthcheck correctly targets `GET /actuator/health`,
  matching EDG-16 AC7's intent (base image question in Finding 7 aside).
- Both edge-api and edge-db set `restart: unless-stopped` in their
  compose files, matching EDG-16 AC8.

---

## Recommended next steps, in order

1. **Rotate the exposed Okta client secret and RDS password** (edge-api)
   — highest priority, independent of any code fix, since they're
   already in git history.
2. Rework edge-api's secret handling to match edge-db's template
   pattern (`.env.template` + gitignored real files + no `COPY` of env
   files into the image); fix the entrypoint to stop hardcoding
   `.env.qa`.
3. ~~Get edge-ui's production build unblocked~~ **DONE 2026-07-29** -
   `environment.production.ts` added, build verified locally.
4. ~~Scaffold edge-ui's `Dockerfile` + `nginx.conf` per EDG-16 AC1~~
   **DONE 2026-07-29** - `Dockerfile`, `nginx.conf`, `docker-compose.yml`,
   `Jenkinsfile`, `VERSION` added. Still needed before the pipeline can
   actually run: create ECR repo `sandbox/bridge/snn-edge-ui`, configure a
   `NodeJS-20` Jenkins tool, then run it once to produce the first image.
5. Align edge-api's Jenkinsfile to push to `sandbox/bridge/snn-edge-api`
   with semver tags.
6. Switch edge-api runtime stage to a Corretto 21 JRE Alpine base image.
7. Align edge-db's tagging to real semver (low priority, already
   functional).
8. Reconcile log volume naming (`/var/log/edge-snn`, `LOG_RETENTION_DAYS`)
   across edge-api and edge-ui once edge-ui exists.
9. Confirm with both teams that their repo-local `docker-compose.yml`
   files are dev-only, and `edge-installer/docker-compose.yml` remains
   the single source of truth for the hospital deployment topology.
