# images/

Holds the single combined image archive that `install.sh` loads offline
(no ECR/AWS access during installation), plus the
digest manifest used to verify it after loading.

| File | Produced by | Consumed by |
|---|---|---|
| `edge-images-{semver}.tar.gz` | `release/download-images.sh` (`docker save snn-edge-ui snn-edge-api snn-edge-db \| gzip`) | `install.sh` (`docker load -i ...`) |
| `DIGESTS` | `release/download-images.sh` (`docker image inspect --format '{{.Id}}'` per image) | `install.sh` (aborts on mismatch) |

Both files are release build artifacts (gitignored) - regenerate them with
`release/download-images.sh` rather than committing them.

**All three images must exist before a release bundle can be cut**
(no partial/API-only install mode is defined). As of
2026-07-30 all three (`snn-edge-ui`, `snn-edge-api`, `snn-edge-db`) are
available in ECR at `1.0.0` - see `docs/HANDOFF.md` for current tags.
