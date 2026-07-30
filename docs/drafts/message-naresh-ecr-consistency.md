Drafted: 2026-07-29
Status: NOT YET SENT
Purpose: Ask Naresh to align the edge-api ECR repo with the naming/tagging
scheme confirmed for EDG-15/EDG-16 (ADR-011)

---

## Short version (Teams chat)

Hey Naresh — noticed the edge-api ECR repo doesn't match what we landed on for EDG-15/16.

Current: `sandbox/bridge/snn-edge`, tags like `snn-edge-api-5`
Expected: `sandbox/bridge/snn-edge-api`, semver tags like `2.1.0` (same pattern edge-db already uses — repo `snn-edge-db`, tag `1.0.4`)

Can't rename in ECR, so we'd need a new repo + repoint Jenkins at it. Also — re-push the current build under a real version tag, or just start clean from the next one?

Not blocking anything today (still waiting on edge-ui), just wanted to flag it early. Lmk if you want to hop on a call.

---

## Long version (email / JIRA comment)

Hi Naresh,

While setting up the edge-installer against EDG-15/EDG-16, I noticed the edge-api ECR repo doesn't quite match the naming/tagging pattern we've settled on for the three images. Wanted to flag it so we're consistent before this goes further.

**What EDG-16 (AC3) and our naming decision (ADR-011) expect:**
- Repo name: `sandbox/bridge/snn-edge-api` (same pattern as edge-db's `sandbox/bridge/snn-edge-db`)
- Tags: semantic version, e.g. `2.1.0` — matches the example EDG-16 gives (`snn-edge-api:2.1.0`) and what edge-db is already doing (tagged `1.0.4`)

**What's currently there:**
- Repo name: `sandbox/bridge/snn-edge` (no `-api` suffix)
- Tags: `snn-edge-api-2`, `snn-edge-api-3`, `snn-edge-api-5` — a build counter baked into the tag, not semver

**Ask:**
1. Create a new ECR repo: `sandbox/bridge/snn-edge-api` (ECR doesn't support renaming an existing repo).
2. Point the Jenkins pipeline at the new repo.
3. Switch tagging to semver (e.g. start at `1.0.0`, or whatever we agree reflects the current build) instead of the `-N` counter.
4. Let's decide together whether to re-push the current build (currently tagged `snn-edge-api-5`) into the new repo under a semver tag so it's not orphaned, or just start fresh from the next build.

Nothing's blocking today since we're still waiting on edge-ui, but wanted to get this queued up early since the installer's docker-compose.yml and .env are already written against `snn-edge-api` as the final name.

Happy to hop on a call if that's easier than back-and-forth here.

Thanks,
[Your Name]
