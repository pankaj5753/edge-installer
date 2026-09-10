# Architecture Decision Record (ADR)

## ADR-001

Decision:

Container images must be built before the installer.

Reason:

The installer consumes container image outputs.

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

Implement hospital deployment and installation infrastructure.

Status:

Accepted

---

## ADR-011

Decision:

Final image names are `snn-edge-ui`, `snn-edge-api`, `snn-edge-db`.

Reason:

Multiple naming conventions were in use across different parts of the
project. Standardized on `snn-edge-ui` / `snn-edge-api` / `snn-edge-db`
as the canonical names on 2026-07-29.

Follow-up:

Legacy ECR repository `sandbox/bridge/snn-edge` predates the naming
standardization and uses older tag conventions. The canonical approach is
to use the standardized image names with semantic versioning (e.g., `1.0.0`).

Status:

Accepted

---

## ADR-012

Decision:

The database password install.sh writes to `.env` is an
internal/infrastructure credential - used only for container-to-container
MySQL connections - and is distinct from hospital/cloud-facility
credentials, which are entered later via the Cloud Configuration screen
and are never stored in `.env`.

Reason:

Installation requires generating a database password for the local MySQL
container. This internal/infrastructure credential is separate from
hospital and cloud-facility credentials, which are facility-specific and
must be managed through the application's UI instead.

Status:

Proposed - working assumption, pending confirmation from the stakeholder.

---

## ADR-013

Decision:

Post-load image digest verification is implemented via a
separate `images/DIGESTS` manifest file, checked by install.sh after
`docker load`, rather than by pinning digests directly in the `image:`
field of `docker-compose.yml`.

Reason:

Image digests must be verified after loading the offline bundle, but
image versions need to remain configurable via `.env` (`UI_IMAGE_TAG`/
`API_IMAGE_TAG`) to support future updates. A separate manifest file
satisfies verification requirements while maintaining version flexibility
in docker-compose.yml.

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

A unified bundle simplifies the installation process and ensures all
required components are present. All three images must be built and
available before a release bundle can be packaged.

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

A VERSION-only tag means every CI run overwrites the same tag (old
builds become unrecoverable). A BUILD_NUMBER-only tag makes the version
meaningless. Using both provides: the build-number tag for permanent
traceability and rollback capability, and the VERSION tag as a deliberate
pointer to "the current release" (what installer bundles reference).

First aligned version: all three images use `1.0.0` under this scheme.

Status:

Accepted

---

## ADR-016

Decision:

edge-api's known secret-handling issues (development credentials baked
into the image, entrypoint environment configuration) are explicitly
deferred. The team proceeds with delivery using the current image as-is.

Reason:

This is flagged as a discussion item with the client, not something to
block delivery on. Must be resolved before the image ships to a real
hospital - acceptable to defer only while still in internal delivery/testing.

Status:

Accepted (deferred, not resolved) - 2026-07-30. Must be revisited before
any hospital-facing release.