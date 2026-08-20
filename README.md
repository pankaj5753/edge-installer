# Edge Agent Platform — Installer

This package installs the Smith+Nephew Edge Agent Platform on your
server. Installation runs entirely from the files included in this
package — your server does **not** need internet access to install or
run it.

The platform consists of three services that work together:

```text
edge-ui   (web interface, HTTPS)      port 443 (and port 80, which redirects to 443)
edge-api  (application server)        internal only, not reachable from outside this host
edge-db   (database)                  internal only, not reachable from outside this host
```

If your network team needs to open a firewall port for this server, only
port 443 (and optionally 80, for the automatic redirect) needs to be
reachable from the workstations that will use it.

## What's in this package

```text
edge-installer/
├── install.sh              # Run this to install
├── uninstall.sh            # Run this to remove the installation
├── check-prereqs.sh        # Optional: installs Docker/Compose/OpenSSL if your server is missing them
├── preflight.sh            # Run automatically by install.sh - checks your server meets the requirements below
├── docker-compose.yml      # Defines the three services
├── .env.example            # Configuration template (install.sh copies this to .env on first run)
├── VERSION
├── lib/                    # Helper scripts used by install.sh
│   └── health-check.sh     # Run any time after install to check that everything is still healthy
├── certs/                  # Ships empty - install.sh creates your TLS certificate here
└── images/                 # The application images, plus a checksum file used to verify them
```

## Before you install

Your server needs:

- **Operating system**: Ubuntu 22.04, 24.04, or 26.04 LTS, or RHEL 8/9 (x86_64)
- **CPU**: 4 cores or more
- **Memory**: 8 GB RAM or more
- **Disk space**: 100 GB or more free
- **Docker Engine** version 24 or newer, with the **Docker Compose** plugin version 2.20 or newer
- **OpenSSL** installed

If Docker, Compose, or OpenSSL aren't already installed, you can run
`./check-prereqs.sh` first — it detects what's missing and, with your
confirmation, installs it automatically. This is the only step that
requires internet access, and only if something needs installing.

## Installing

**Step 1 — Verify the download.** Before extracting anything, confirm the
package hasn't been corrupted or tampered with in transit:

```bash
sha256sum edge-install-{version}-linux-x64.tar.gz
```

Compare the result against the SHA-256 value provided by your Smith+Nephew
representative. **The two values must match exactly.** If they don't,
do not extract the package — contact your Smith+Nephew representative
instead.

**Step 2 — Extract and install:**

```bash
tar xzf edge-install-{version}-linux-x64.tar.gz -C /opt/edge-agent/ --strip-components=1
cd /opt/edge-agent
sudo ./install.sh
```

`install.sh` will, in order:

1. Check that your server meets the requirements above (writes a
   `preflight-report.txt` file with details if anything fails).
2. Load and verify the application images included in this package.
3. Ask for your server's static LAN IP address and which port to use
   (default `443`) — only asked the first time you install.
4. Generate a TLS certificate for secure browser access, and print its
   fingerprint. **Write this fingerprint down** — you'll need it in the
   next section, "Opening the setup wizard."
5. Generate secure, random database credentials.
6. Start all three services.
7. Wait for all three services to report healthy (up to 2 minutes).
8. Print the web address to open in your browser.

You can run `install.sh` again safely at any time (for example, to
install a newer package version) — it will not ask for the IP/port again,
regenerate your certificate, or reset your database credentials. Everything
is logged to `/var/log/edge-agent/install.log`.

## Opening the setup wizard

Open the address `install.sh` printed
(`https://<your-server-ip>/setup`) in a browser on your hospital network.

Your browser will show a security warning because the certificate is
self-signed. This is expected. Click to view the certificate details and
confirm its fingerprint matches exactly what `install.sh` printed, then
accept the warning to continue. From there, the on-screen setup wizard
will guide you through the rest of configuration.

## Checking status after install

At any time after installation, you can check that all three services are
still running correctly:

```bash
./lib/health-check.sh
```

## Installing a newer version

When Smith+Nephew provides an updated package:

1. Verify its checksum the same way as in Step 1 above.
2. Extract it over your existing installation folder (same command as
   Step 2 — it will not disturb your existing configuration).
3. Run `sudo ./install.sh` again.

Your server's IP/port, TLS certificate, and database credentials all stay
the same; only the application images are updated.

## Uninstalling

```bash
sudo ./uninstall.sh
```

This stops and removes the three services. Your database, logs, and TLS
certificate are kept by default, so you can reinstall later without
losing anything — just run `./install.sh` again.

To permanently remove everything, including the database and certificate:

```bash
sudo ./uninstall.sh --purge-data
```

This cannot be undone — you'll be asked to type `yes` to confirm.

## Troubleshooting

1. **Docker not installed, or the Docker daemon isn't reachable** —
   install Docker Engine (https://docs.docker.com/engine/install/), or
   run `./check-prereqs.sh`. Make sure the current user can run
   `docker info` (add the user to the `docker` group, or run with `sudo`).
2. **Docker Engine or Compose version too old** — see
   `preflight-report.txt` for the version detected, then upgrade per
   https://docs.docker.com/engine/install/ or
   https://docs.docker.com/compose/install/, or run `./check-prereqs.sh`.
3. **Unsupported operating system** — only Ubuntu 22.04/24.04/26.04 LTS
   and RHEL 8/9 (x86_64) are supported.
4. **Insufficient CPU / RAM / disk space** — see `preflight-report.txt`
   for the values detected and the minimums required; use a larger server
   or free up disk space.
5. **Missing image file** (`images/edge-images-{version}.tar.gz`) — re-extract
   the package. If it's still missing, the download may not have completed
   fully — re-download it.
6. **Checksum mismatch on the image file** — do not proceed. Re-download
   the package and re-verify it (see Step 1). This indicates the download
   is corrupted or incomplete.
7. **Static IP or port not provided** — a static IP is required. Re-run
   `./install.sh` and enter a valid value when prompted.
8. **Services don't become healthy within 2 minutes** — run
   `docker compose logs` to see what a specific service reported. Common
   causes are another application already using the chosen port, or the
   database taking longer than usual to start on a slow disk. You can also
   run `./lib/health-check.sh` at any time for a status snapshot.
9. **Checksum mismatch on the package itself (Step 1, before extracting)**
   — do not extract the package. Contact your Smith+Nephew representative;
   do not proceed with a package that fails verification.
10. **Certificate generation failed** — an error from the `openssl`
    command will be shown above the failure message. Re-run
    `./install.sh`; if the problem persists, confirm `openssl version`
    reports 1.1.1 or newer and that the `certs/` folder is writable.

## Getting help

If you run into an issue not covered above, contact your Smith+Nephew
representative.
