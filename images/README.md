# images/

Holds the single combined image archive that `install.sh` loads offline
(ADR-007, EDG-15 AC13 - no ECR/AWS access during installation), plus the
digest manifest used to verify it after loading.

| File | Produced by | Consumed by |
|---|---|---|
| `edge-images-{semver}.tar.gz` | `release/download-images.sh` (`docker save snn-edge-ui snn-edge-api snn-edge-db \| gzip`, EDG-15 AC3) | `install.sh` (`docker load -i ...`) |
| `DIGESTS` | `release/download-images.sh` (`docker image inspect --format '{{.Id}}'` per image) | `install.sh` (aborts on mismatch, EDG-15 AC11) |

Both files are release build artifacts (gitignored) - regenerate them with
`release/download-images.sh` rather than committing them.

**All three images must exist before a release bundle can be cut**
(EDG-15 does not define a partial/API-only install mode). As of
2026-07-30 all three (`snn-edge-ui`, `snn-edge-api`, `snn-edge-db`) are
available in ECR at `1.0.0` - see `docs/HANDOFF.md` for current tags.
