# Architecture Decision Record (ADR)

## ADR-001

Decision:

EDG-16 must be implemented before EDG-15.

Reason:

EDG-15 consumes EDG-16 outputs.

Status:

Accepted

---

## ADR-002

Decision:

Use ECR as the source of truth.

Reason:

Supports image versioning and release management.

Status:

Accepted

---

## ADR-003

Decision:

Use Docker images instead of source code in hospital deployments.

Reason:

Hospitals receive offline installation bundles.

Status:

Accepted

---

## ADR-004

Decision:

Use custom edge-db image.

Reason:

Supports versioned releases.

Image:

snn-edge-db

Status:

Accepted

---

## ADR-005

Decision:

Do not embed credentials in images.

Reason:

Security requirement.

Implementation:

install.sh generates credentials at installation time.

Status:

Accepted

---

## ADR-006

Decision:

Use Docker named volume for database persistence.

Volume:

edge-db-data

Reason:

Survives:

- Restart
- Rebuild
- Upgrade
- Host reboot

Status:

Accepted

---

## ADR-007

Decision:

Installer works without internet access.

Reason:

Hospital environments may block outbound access.

Implementation:

docker load from local package.

Status:

Accepted

---

## ADR-008

Decision:

Use semantic versioning.

Examples:

1.0.0
1.1.0
2.0.0

Reason:

Supports controlled upgrades.

Status:

Accepted

---

## ADR-009

Decision:

Future schema changes should be migration-based.

Example:

V1__init.sql
V2__add_tables.sql
V3__indexes.sql

Reason:

Supports upgrades without rebuilding environments.

Status:

Proposed

---

## ADR-010

Decision:

Create dedicated edge-installer repository.

Purpose:

Implement EDG-15.

Status:

Accepted

---

## ADR-011

Decision:

Final image names are `snn-edge-ui`, `snn-edge-api`, `snn-edge-db`.

Reason:

HANDOFF.md/ADR-004 (`snn-edge-db`, `snn-edge`), EDG-16
(`snn-edge-ui`, `snn-edge-api`), and EDG-15's example command
(`edge-agent`, `edge-db`, `nginx`) all used different names. Confirmed
by the requester on 2026-07-29 as `snn-edge-ui` / `snn-edge-api` /
`snn-edge-db`.

Follow-up:

`sandbox/bridge/snn-edge` (current edge-api ECR repo name) predates this
confirmation and diverges on two counts: repo name lacks the `-api`
suffix, and existing tags (`snn-edge-api-2/3/5`) are a build counter
rather than semver. edge-db's repo (`sandbox/bridge/snn-edge-db`,
tagged `1.0.4`) is the correct reference pattern. ECR can't rename a
repo in place, so this needs a new repo, not a fix to the existing one.
See HANDOFF.md edge-api section. Since resolved.

Status:

Accepted

---

## ADR-012

Decision:

The database password install.sh writes to `.env` (EDG-15 AC11) is an
internal/infrastructure credential - used only for container-to-container
MySQL connections - and is distinct from hospital/cloud-facility
credentials, which are entered later via the Cloud Configuration screen
and are never stored in `.env` (EDG-16 AC6).

Reason:

EDG-15 AC11 explicitly requires install.sh to generate and store a DB
password in `.env`; EDG-16 AC6 explicitly forbids storing secrets in
`.env`. Read literally these conflict. Treating them as two different
credential types resolves the conflict without contradicting either
ticket.

Status:

Proposed - working assumption, pending confirmation from the stakeholder.

---

## ADR-013

Decision:

Post-load image digest verification (EDG-15 AC11) is implemented via a
separate `images/DIGESTS` manifest file, checked by install.sh after
`docker load`, rather than by pinning digests directly in the `image:`
field of `docker-compose.yml`.

Reason:

EDG-15 AC11 says loaded image digests must be verified against values
"pinned in docker-compose.yml." EDG-16 AC3/AC9 requires image versions to
stay configurable via `.env` (`UI_IMAGE_TAG`/`API_IMAGE_TAG`), which is
incompatible with hardcoding a digest into the same `image:` field. A
separate manifest satisfies the verification intent of AC11 without
breaking AC3/AC9's tag-based update flow.

Status:

Proposed, pending confirmation from the stakeholder.

---

## ADR-014

Decision:

A release bundle ships all three images (`snn-edge-ui`, `snn-edge-api`,
`snn-edge-db`) in a single combined, gzipped archive
(`images/edge-images-{semver}.tar.gz`, produced by
`docker save img1 img2 img3 | gzip`). There is no partial/API-only
install mode - `install.sh` requires all three images to be present and
aborts otherwise.

Reason:

EDG-15 AC3 specifies this exact command and archive format. It implies a
release can't be cut until all three images exist, which is a change
from an earlier interim scaffold that supported installing edge-db +
edge-api only while edge-ui was pending.

Status:

Accepted

---

## ADR-015

Decision:

All three Jenkinsfiles (edge-ui, edge-api, edge-db) push every build under
three tags: `{VERSION}` (e.g. `1.0.0`), `{VERSION}-{BUILD_NUMBER}` (e.g.
`1.0.0-42`), and `latest`. `VERSION` is a file in each repo, only bumped
deliberately. `BUILD_NUMBER` comes from Jenkins and is never reused.

Reason:

A VERSION-only tag (no build number) means every CI run overwrites the
same ECR tag - old builds become unrecoverable, and there's no way to
tell which Jenkins run produced a given image. A BUILD_NUMBER-only tag
(edge-db/edge-api's original pattern) solves that but makes the "version"
meaningless - it increments on every run regardless of whether anything
release-worthy happened. Pushing both solves both problems: the
build-number tag is permanent and unique (rollback/traceability), the
VERSION tag is a deliberate, meaningful pointer to "the current release"
(what `edge-installer` and hospital bundles reference).

First aligned version: all three images start at `1.0.0` under this
scheme (edge-db's prior `1.0.4` tag predates this ADR and is superseded,
not continued).

Status:

Accepted

---

## ADR-016

Decision:

edge-api's known secret-handling issues (`.env.qa`/`.env.dev` baked into
the image with real credentials, entrypoint hardcoding `.env.qa`
regardless of environment - containerization review Findings 1-2) are
explicitly deferred. The team proceeds with delivery using the current
image as-is.

Reason:

Client-facing decision: this is flagged as a discussion item with the
client, not something to block delivery on. Must be resolved before the
image ships to a real hospital - acceptable to defer only while still in
internal delivery/testing.

Status:

Accepted (deferred, not resolved) - 2026-07-30. Must be revisited before
any hospital-facing release.

---

## ADR-017

Decision:

`preflight.sh` remains offline-first and fails fast by default (EDG-15
AC13), but now offers an opt-in exception: when only software
(Docker Engine, Docker Compose plugin, OpenSSL) is missing - CPU, RAM,
disk, and OS all pass - and a terminal is attached, the operator is
interactively prompted to attempt automatic installation via the OS
package manager (`lib/install-prereqs.sh`, Docker's official apt/dnf repo,
not the distro's). Declining, or running non-interactively (CI, scripted
installs), falls back to today's fail-fast behavior unchanged.

Reason:

EDG-15's original assumption was that hospital hosts have no internet
access during install. Confirmed with the client (via Veera) that this
isn't always true - some hosts may have internet. Rather than changing
the default (which would break the offline guarantee for hosts that
genuinely have none), this adds a narrow, explicit, opt-in path for hosts
that do, without weakening the strict preflight-and-abort behavior
everywhere else.

Status:

Accepted - 2026-08-07.