Drafted: 2026-07-29
Status: NOT YET SENT
Purpose: Ask stakeholder to confirm ADR-012 and ADR-013 (docs/DECISIONS.md)

---

Hi [Name],

While building out the edge-installer against EDG-15 and EDG-16, I came across two points where the two tickets read differently from each other. Wanted to flag both and get your read before we lock in the implementation.

**1. Where does the database password live?**

- EDG-15 (Step 2, install script requirements) says the installer should generate a random database password and save it in the config file (.env).
- EDG-16 (Acceptance Criteria #6) says no secrets should ever be stored in the config file — credentials should only be entered later through the Cloud Configuration screen.

Our working assumption: these refer to two different things. EDG-15's password is an internal one, used only for the containers to talk to each other — never seen by a person. EDG-16's rule is about the hospital's actual account credentials, entered through the setup screen. If that's correct, no issue. Can you confirm that's the intended split?

**2. How do we verify the loaded images are the correct, untampered ones?**

- EDG-15 (Step 2, item 11) requires the installer to check that the loaded container images match an expected value "pinned in docker-compose.yml," and to stop if they don't match.
- EDG-16 (Acceptance Criteria #3) requires the config file (.env) to control which version of each image is used, so a version can be changed with a one-line edit.

These two don't fit together as literally written — a file can't both "lock to one fixed image" and "be freely changeable by editing a setting" at the same time. We've implemented it as: the version stays configurable via .env (per EDG-16), and the verification check lives in a separate manifest file the installer reads (rather than inside docker-compose.yml itself). This satisfies the intent of both, but isn't literally what EDG-15 describes. Wanted your confirmation this approach is acceptable, or if there's a different intent behind that requirement.

Happy to jump on a quick call if easier. Let me know your thoughts when you get a chance.

Thanks,
[Your Name]
