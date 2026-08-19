# edge-installer

Offline installer for the Smith+Nephew Edge Agent Platform (EDG-15),
packaging the three-container stack defined in EDG-16:

```text
edge-ui   (Nginx + Angular, TLS)   :443 external
edge-api  (Spring Boot)            :8080 internal
edge-db   (MySQL 8)                :3306 internal
```

See `../docs/ARCHITECTURE.md` for the architecture and
`../docs/DECISIONS.md` for the ADRs this repo follows.

## Current status

All three images (`snn-edge-ui`, `snn-edge-api`, `snn-edge-db`) are
available in ECR at `1.0.0` as of 2026-07-30. See `docs/HANDOFF.md`
for what's still pending before the first real bundle ships.

## Layout

```text
edge-installer/
├── install.sh               # main entry point - EDG-15 AC11 sequence, aborts on first failure
├── preflight.sh              # CPU/RAM/disk/Docker/Compose/OS checks -> preflight-report.txt
├── docker-compose.yml         # 3-service stack (EDG-16 AC4, AC7, AC8, AC10)
├── .env.example                # config template; install.sh copies this to .env (mode 600)
├── lib/
│   ├── common.sh                # shared shell helpers (env, digests, health polling)
│   ├── generate-certs.sh         # self-signed TLS cert for edge-ui (called by install.sh)
│   └── health-check.sh            # on-demand health snapshot (not used by install.sh's own poll)
├── certs/                    # ships empty; install.sh writes edge.crt/edge.key here (mode 600)
├── images/                   # combined image archive + digest manifest (see images/README.md)
├── config/
│   └── logrotate-edge-snn.example  # optional log retention policy (EDG-16 AC10) - not auto-installed
└── release/                  # dev-side tools for building a release bundle (not shipped to hospitals)
    ├── download-images.sh     # pulls all 3 images from ECR, saves combined archive + DIGESTS
    ├── package-release.sh     # builds edge-install-{semver}-linux-x64.tar.gz
    └── publish-bundle.sh      # uploads to S3, prints the 7-day signed URL + SHA-256
```

## Installing on the hospital host (EDG-15 Steps 1-3)

```bash
# Step 1 (Hospital IT, manual): download the bundle, then verify it
sha256sum edge-install-{semver}-linux-x64.tar.gz
# compare against the SHA-256 in the S+N rep's email - must match exactly.
# If it doesn't match: do NOT extract, contact your S+N representative.

# Step 2: extract and install
tar xzf edge-install-{semver}-linux-x64.tar.gz -C /opt/edge-agent/ --strip-components=1
cd /opt/edge-agent
sudo ./install.sh
```

`install.sh` runs this sequence, aborting on first failure (EDG-15 AC11):

1. Preflight checks (CPU >= 4 cores, RAM >= 8GB, disk >= 100GB, Docker
   Engine >= 24, Docker Compose >= 2.20, OpenSSL present, OS in the
   supported list) — writes `preflight-report.txt` with remediation hints
   for any failures.
2. `docker load`s `images/edge-images-{semver}.tar.gz` and verifies each
   loaded image's digest against `images/DIGESTS` — aborts on mismatch.
3. Prompts for the static LAN IP and bind port (first run only) and writes
   them to `.env`.
4. Generates a self-signed TLS certificate (`certs/edge.crt`,
   `certs/edge.key`, mode 600, CN/SAN = the configured IP, 825-day
   validity, 2048-bit RSA) if one doesn't already exist.
5. Prints the certificate's SHA-256 fingerprint for first-connection trust
   verification.
6. Generates random database passwords into `.env` (mode 600) if not
   already set. This is the internal MySQL connection password only —
   distinct from hospital/cloud-facility credentials, which are entered
   later via the Cloud Configuration screen and never stored here
   (EDG-16 AC6).
7. `docker compose up -d`. No outbound pulls occur — images are already
   loaded locally (EDG-15 AC13).
8. Polls container health for up to 2 minutes; all three must be healthy.
9. Prints `https://<configured-ip>/setup`.

**Idempotent**: re-running `install.sh` reloads images (a no-op if
digests are unchanged) but does **not** regenerate the TLS cert, database
passwords, or prompt again for IP/port. To force regeneration, remove the
relevant files first (`certs/edge.crt` + `certs/edge.key` for the cert;
clear the password lines in `.env` for credentials) — see
`lib/generate-certs.sh --force`.

All install actions are logged to `/var/log/edge-agent/install.log` for
audit (falls back to `./install.log` with a warning if that path isn't
writable — run as root/sudo to get the real audit path).

## Step 3: open the setup wizard (Hospital IT)

Navigate to the printed `https://<configured-ip>/setup` URL. The browser
will show a TLS warning (self-signed cert) — verify the displayed
fingerprint matches the one `install.sh` printed, then accept it. The
wizard itself (Environment health screen, /setup wireframe v2 flow) is
served by the running `edge-ui`/`edge-api` containers and is out of scope
for this repo.

## Updating a single service (offline equivalent of EDG-16 AC9)

EDG-16 AC9 describes `docker compose pull edge-ui && docker compose up -d
edge-ui` for a UI-only release. Hospital hosts don't have outbound
registry access (ADR-007, EDG-15 AC13), so the offline equivalent is:

```bash
# after obtaining a new images/edge-images-{semver}.tar.gz + DIGESTS
# for the patched release, and updating UI_IMAGE_TAG (or API_IMAGE_TAG) in .env:
docker load -i images/edge-images-{semver}.tar.gz
docker compose up -d edge-ui   # or edge-api - only the changed service restarts
```

Per EDG-15's patch strategy, a full bundle re-download is still required
for every patched release (the combined archive always contains all three
images) even though only one service's tag actually changes.

## Troubleshooting

Numbered so `install.sh`/`preflight.sh` error messages can reference a
section directly.

1. **Docker not installed / daemon unreachable** — install Docker Engine
   (https://docs.docker.com/engine/install/) and ensure the current user
   can run `docker info` (add to the `docker` group or run with sudo).
2. **Docker Engine or Compose version too old** — see
   `preflight-report.txt` for the detected version; upgrade per
   https://docs.docker.com/engine/install/ /
   https://docs.docker.com/compose/install/.
3. **Unsupported OS** — only Ubuntu 22.04/24.04/26.04 LTS and RHEL 8/9
   x86_64 are supported; Windows is out of scope (separate future story).
4. **Insufficient CPU / RAM / disk** — see `preflight-report.txt` for the
   detected values and required minimums; provision a larger host or free
   up disk space.
5. **Missing image archive** — `images/edge-images-{semver}.tar.gz` isn't
   present. Re-extract the bundle; if it's still missing, re-download the
   bundle (it may not have transferred completely).
6. **Image archive checksum mismatch** — `images/edge-images-{semver}.tar.gz`
   doesn't match `images/DIGESTS`. Do not proceed; re-download the bundle
   and re-verify its checksum (see Step 1). This indicates a corrupted or
   tampered archive.
7. **Static IP / bind port not provided** — install.sh requires a
   non-empty static LAN IP; re-run `./install.sh` and enter a valid value
   when prompted.
8. **Containers fail to become healthy within 2 minutes** — run
   `docker compose logs` for the unhealthy service; common causes are a
   port conflict on the bind port, or a database that hasn't finished
   initializing on a slow disk. `lib/health-check.sh` gives a point-in-time
   snapshot at any time after install.
9. **Bundle checksum mismatch (Step 1, before extraction)** — do not
   extract the bundle. Contact your S+N representative; do not attempt to
   proceed with a bundle that fails checksum verification.
10. **Certificate generation failed** — `openssl req` printed an error
    (shown above the failure message). Re-run `./install.sh`; if it
    persists, verify `openssl version` is 1.1.1 or newer and that
    `certs/` is writable.

## Building a release bundle (dev/release engineer, not hospital IT)

Requires AWS credentials and internet access — this happens before the
bundle is shipped, never on the hospital host. All three images
(`snn-edge-ui`, `snn-edge-api`, `snn-edge-db`) must exist in ECR first.

```bash
AWS_REGION=us-east-1 AWS_ACCOUNT_ID=123456789012 \
  ./release/download-images.sh 1.0.0 <ui-tag> <api-tag> <db-tag>

./release/package-release.sh
```

This produces `dist/edge-install-{semver}-linux-x64.tar.gz` plus a
`.sha256` checksum file.

```bash
./release/publish-bundle.sh
```

Uploads the bundle to S3 (`sportsmed-edge-installer-app-bucket`) with
`--checksum-algorithm SHA256` and prints a 7-day signed URL plus the
SHA-256 value to send the hospital IT contact (EDG-15 AC1, AC4, Step 1).
Override the bucket with `S3_BUCKET=...`.

## Versioning

Semantic versioning (ADR-008, EDG-15 AC5); see `VERSION` and
`CHANGELOG.md`. Per EDG-15 AC5, prior bundle versions remain downloadable
for at least 12 months — an S3 retention-policy concern for the release
pipeline, not this repo.

## Out of scope for this repo

- Angular UI build (Node 20, `ng build --configuration=production`),
  Dockerfile, and `nginx.conf` reverse-proxy config — `edge-ui` repo
  (EDG-16 AC1).
- Spring Boot build (Corretto 21, layered JAR) and Dockerfile — `edge-api`
  repo (EDG-16 AC2).
- `init.sql` and MySQL schema — `edge-db` repo (EDG-16 AC5).
- Building images and running Jenkins pipelines — each app repo's own
  Jenkinsfile (EDG-16). `publish-bundle.sh` here only handles the S3
  upload step once a bundle already exists.
- Actually emailing the checksum/link to hospital IT, and S3 bucket
  lifecycle/retention for the 12-month prior-version requirement
  (EDG-15 AC5, AC7-9) — process/infra, not a script.
- The setup wizard flow itself (Environment health screen, /setup
  wireframe v2) — served by `edge-ui`/`edge-api`, not this repo
  (EDG-15 AC15).
