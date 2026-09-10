# Install the Smith+Nephew Hub

To install the Smith+Nephew Hub, you must ensure that the following system requirements are met, verify your installation package, and then run the installer.

Installation runs entirely from the files included in this package. Your server does not need internet access to install or run the platform.

> \*\*Note\*\* The only step that may require internet access is `./check-prereqs.sh`, and only if Docker, Docker Compose, or OpenSSL are missing from your server.

## Architecture

The platform consists of three services that work together:

|Service|Role|Network exposure|
|-|-|-|
|`hub-ui`|Web interface (HTTPS)|Port 443, and port 80 which redirects to 443|
|`hub-api`|Application server|Internal only, not reachable from outside this host|
|`hub-db`|Database|Internal only, not reachable from outside this host|

> \*\*Tip\*\* If your network team needs to open a firewall port for this server, only port 443 needs to be reachable from the workstations that will use it. Port 80 is optional and only serves the automatic redirect.

## Software requirements

* One of the following operating systems, on x86\_64 architecture:

  * Ubuntu 22.04 LTS.
  * Ubuntu 24.04 LTS.
  * Ubuntu 26.04 LTS.
  * RHEL 8.
  * RHEL 9.
* Docker Engine 24 or later, with the Docker Compose plugin 2.20 or later.
* OpenSSL 1.1.1 or later.
* The user who installs the platform can run `docker info`, either as a member of the `docker` group or by using `sudo`.

> \*\*Tip\*\* If Docker, Compose, or OpenSSL are not already installed, run `./check-prereqs.sh` before you install. It detects what is missing and, with your confirmation, installs it automatically.

## Hardware requirements

You need the following minimum hardware requirements:

* 4-core CPU or more.
* 8 GB memory or more.
* 100 GB or more free disk space.

> \*\*Note\*\* `install.sh` checks all of the requirements above automatically and writes a `preflight-report.txt` file with the detected values if any check fails.

## Network requirements

* A static LAN IP address on the server. You are prompted for this address the first time you install.
* Port 443 reachable from the workstations that will use the platform. If port 443 is unavailable, you can choose a different port during installation.
* Optionally, port 80, which redirects to 443.
* No outbound internet access is required to install or run the platform.

## Package contents

```text
edge-installer/
├── install.sh              # Run this to install
├── uninstall.sh            # Run this to remove the installation
├── check-prereqs.sh        # Optional: installs Docker/Compose/OpenSSL if your server is missing them
├── preflight.sh            # Run automatically by install.sh - checks your server meets the requirements above
├── docker-compose.yml      # Defines the three services
├── .env.example            # Configuration template (install.sh copies this to .env on first run)
├── VERSION
├── lib/                    # Helper scripts used by install.sh
│   └── health-check.sh     # Run any time after install to check that everything is still healthy
├── certs/                  # Ships empty - install.sh creates your TLS certificate here
└── images/                 # The application images, plus a checksum file used to verify them
```

## Install the platform

### Step 1: Verify the download

Before you extract anything, confirm that the package has not been corrupted or tampered with in transit:

```bash
sha256sum snn-hub-install-{version}-linux-x64.tar.gz
```

Compare the result against the SHA-256 value provided by your Smith+Nephew representative. The two values must match exactly.

> \*\*Warning\*\* If the values do not match, do not extract the package. Contact your Smith+Nephew representative instead.

### Step 2: Extract and install

```bash
tar xzf snn-hub-install-{version}-linux-x64.tar.gz -C /opt/hub-agent/ --strip-components=1
cd /opt/hub-agent
sudo ./install.sh
```

`install.sh` performs the following actions, in order:

1. Checks that your server meets the requirements above, and writes a `preflight-report.txt` file with details if anything fails.
2. Loads and verifies the application images included in this package.
3. Prompts for your server's static LAN IP address and the port to use. The default port is `443`. You are only prompted the first time you install.
4. Generates a TLS certificate for secure browser access and prints its fingerprint.
5. Generates secure, random database credentials.
6. Starts all three services.
7. Waits up to 2 minutes for all three services to report healthy.
8. Prints the web address to open in your browser.

> \*\*Note\*\* Write down the certificate fingerprint printed in step 4. You need it to complete the next section.

> \*\*Tip\*\* You can run `install.sh` again safely at any time, for example to install a newer package version. It does not ask for the IP address or port again, regenerate your certificate, or reset your database credentials. Everything is logged to `/var/log/hub-agent/install.log`.

### Step 3: Open the setup wizard

1. In a browser on your hospital network, open the address that `install.sh` printed: `https://<your-server-ip>/setup`.
2. When your browser shows a security warning, click to view the certificate details.
3. Confirm that the certificate fingerprint matches exactly what `install.sh` printed, then accept the warning to continue.
4. Follow the on-screen setup wizard to complete configuration.

> \*\*Note\*\* The security warning is expected. It appears because the certificate is self-signed.

## Check the status of your installation

At any time after installation, you can check that all three services are still running correctly:

```bash
./lib/health-check.sh
```

## Upgrade to a newer version

When Smith+Nephew provides an updated package:

1. Verify its checksum, as described in Step 1.
2. Extract it over your existing installation folder, using the same command as in Step 2. This does not disturb your existing configuration.
3. Run `sudo ./install.sh` again.

Your server's IP address and port, TLS certificate, and database credentials all stay the same. Only the application images are updated.

## Uninstall the platform

```bash
sudo ./uninstall.sh
```

This stops and removes the three services. Your database, logs, and TLS certificate are kept by default, so you can reinstall later without losing anything by running `./install.sh` again.

To permanently remove everything, including the database and certificate:

```bash
sudo ./uninstall.sh --purge-data
```

> \*\*Warning\*\* `--purge-data` cannot be undone. You are asked to type `yes` to confirm.

## Troubleshooting

|Issue|Resolution|
|-|-|
|Checksum mismatch on the package itself, in Step 1 before extracting|Do not extract the package. Contact your Smith+Nephew representative. Do not proceed with a package that fails verification.|
|Docker is not installed, or the Docker daemon is not reachable|Install Docker Engine from [docs.docker.com](https://docs.docker.com/engine/install/), or run `./check-prereqs.sh`. Make sure the current user can run `docker info`, either by adding the user to the `docker` group or by running with `sudo`.|
|Docker Engine or Compose version is too old|See `preflight-report.txt` for the version detected, then upgrade per [docs.docker.com/engine](https://docs.docker.com/engine/install/) or [docs.docker.com/compose](https://docs.docker.com/compose/install/), or run `./check-prereqs.sh`.|
|Unsupported operating system|Only Ubuntu 22.04, 24.04, and 26.04 LTS, and RHEL 8 and 9 on x86\_64, are supported.|
|Insufficient CPU, RAM, or disk space|See `preflight-report.txt` for the values detected and the minimums required. Use a larger server or free up disk space.|
|Missing image file (`images/edge-images-{version}.tar.gz`)|Re-extract the package. If the file is still missing, the download may not have completed fully. Re-download the package.|
|Checksum mismatch on the image file|Do not proceed. This indicates that the download is corrupted or incomplete. Re-download the package and re-verify it, as described in Step 1.|
|Static IP address or port not provided|A static IP address is required. Re-run `./install.sh` and enter a valid value when prompted.|
|Services do not become healthy within 2 minutes|Run `docker compose logs` to see what a specific service reported. Common causes are another application already using the chosen port, or the database taking longer than usual to start on a slow disk. You can also run `./lib/health-check.sh` for a status snapshot.|
|Certificate generation failed|An error from the `openssl` command is shown above the failure message. Re-run `./install.sh`. If the problem persists, confirm that `openssl version` reports 1.1.1 or later and that the `certs/` folder is writable.|

## Getting help

If you run into an issue that is not covered above, contact your Smith+Nephew representative.

