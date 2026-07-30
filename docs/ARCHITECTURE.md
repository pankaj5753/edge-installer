# Edge Agent Platform Architecture

## Overview

The Edge Agent Platform consists of three containers deployed using Docker Compose.

```text
edge-ui
(Angular + Nginx)
      ↓

edge-api
(Spring Boot)
      ↓

edge-db
(MySQL 8)
```

---

# Components

## edge-ui

Purpose:

User interface for Hospital IT.

Technology:

- Angular (Node 20 build, `ng build --configuration=production`)
- Nginx 1.27 Alpine, two-stage build with Node 20 Alpine (EDG-16 AC1)
- TLS termination (mounted `./certs`)
- Reverse-proxies `/v1/**` and `/api/**` to edge-api:8080

Image:

`snn-edge-ui`, tag controlled via `UI_IMAGE_TAG` in `.env` (ADR-011)

External Port:

443 (configurable via `BIND_PORT`)

Health check:

Process-level check (nginx running), 3 consecutive failures triggers a
Docker restart (EDG-16 AC7)

Responsibilities:

- Dashboard
- Login
- Cloud Configuration
- Initial setup

---

## edge-api

Purpose:

Application backend. Pure API server, serves no static content
(EDG-16 AC2).

Technology:

- Spring Boot
- Amazon Corretto 21, two-stage build (JDK compile w/ layered JAR
  extraction, JRE Alpine runtime)

Image:

`snn-edge-api`, tag controlled via `API_IMAGE_TAG` in `.env` (ADR-011).
NOTE: current ECR repo is `sandbox/bridge/snn-edge` with image tag
`snn-edge-api-3` - predates ADR-011, needs reconciling (see
AI-HANDOFF.md).

Port:

8080 (internal only)

Health check:

`GET /actuator/health`, 3 consecutive failures triggers a Docker
restart (EDG-16 AC7)

Responsibilities:

- Business logic
- Database access
- Authentication
- Provisioning

---

## edge-db

Purpose:

Persistent local database.

Technology:

- MySQL 8

Image:

`snn-edge-db`, tag controlled via `DB_IMAGE_TAG` in `.env` (ADR-011)

Port:

3306 (internal only)

Health check:

`mysqladmin ping`, 3 consecutive failures triggers a Docker restart
(EDG-16 AC7)

Persistence:

edge-db-data volume

Current Version:

1.0.4

Tables (via `init.sql` on first boot):

- edge_credentials
- edge_auth_sessions
- edge_local_audit_log

---

# Logging

A shared named volume (`edge-logs`) is mounted at `/var/log/edge-snn` in
both edge-ui and edge-api, for persistent log retention beyond Docker's
own stdout/stderr capture. Retention is configurable via
`LOG_RETENTION_DAYS` in `.env` (EDG-16 AC10). Enforcement (e.g.
logrotate) is provided as an opt-in example
(`edge-installer/config/logrotate-edge-snn.example`), not automated by
install.sh.

---

# Release Bundle Format

A release bundle ships all three images in a single combined, gzipped
archive (`images/edge-images-{semver}.tar.gz`, produced by
`docker save snn-edge-ui snn-edge-api snn-edge-db | gzip`), plus a
`images/DIGESTS` manifest used by install.sh to verify loaded image
integrity post-load. There is no partial/API-only install path - all
three images must exist before a bundle can be built (ADR-014).

---

# Deployment Model

EDG-16 creates versioned images.

EDG-15 packages them.

```text
GitLab
 ↓

Jenkins
 ↓

ECR
 ↓

docker save
 ↓

Installer Bundle
 ↓

Hospital Host
```

---

# Security Model

Images contain:

- Application code
- SQL initialization
- Configuration templates

Images do NOT contain:

- Passwords
- Secrets
- Hospital-specific configuration

Secrets generated during installation.

---

# Installation Flow

1. Download package (resumable download, 7-day signed URL).
2. Validate bundle checksum (`sha256sum`, manual - IT compares against
   the value emailed by the S+N rep; must not extract on mismatch).
3. Extract bundle to `/opt/edge-agent/`.
4. Run preflight checks (CPU/RAM/disk/Docker/Compose/OpenSSL/OS) -
   writes `preflight-report.txt`, aborts on failure.
5. Load images from the combined archive; verify loaded digests against
   `images/DIGESTS` - aborts on mismatch.
6. Prompt for static LAN IP and bind port (first run only); write to
   `.env`.
7. Generate self-signed TLS certificate + print its SHA-256 fingerprint
   (idempotent - skipped on re-run unless forced).
8. Generate database credentials into `.env`, mode 600 (idempotent -
   skipped on re-run; see ADR-012 for the credential-scope distinction).
9. Start stack (`docker compose up -d`) - no outbound pulls, images
   already loaded locally.
10. Poll container health for up to 2 minutes; all three must be
    healthy.
11. Print `https://<configured-ip>/setup`.
12. Open setup wizard in browser; verify TLS fingerprint before
    accepting the certificate trust prompt.

All of steps 3-11 are logged to `/var/log/edge-agent/install.log` for
audit. Full detail: `edge-installer/README.md`.