Drafted: 2026-07-30
Purpose: Status update for customer/management - EDG-15, EDG-16, and consolidated

---

## EDG-15 - Edge Agent Setup at Hospital Facility

**Status: On Track**

This covers the installer package hospital IT will use to set up the
Edge Agent on their own servers - designed to work without needing
internet access during setup, for security and reliability.

**Progress:**
- Installer is fully built, including automatic setup checks, secure
  certificate handling, and a guided installation flow.
- Packaging and publishing process is built and being connected to our
  automated build system.

**Remaining:**
- One full test run on a real server, to confirm everything works
  end-to-end before handing it to hospital IT.
- Final packaging and publishing to make the software available for
  download.

---

## EDG-16 - Dockerize Edge Agent Deployment

**Status: On Track** (one item pending before hospital delivery)

This covers packaging our three core components - user interface,
backend service, and database - into standardized units that run
reliably on hospital servers.

**Progress:**
- All three components are built and published, each with an initial
  version ready for testing and demo.
- Automated build pipelines are in place for all three, so future
  updates can be released reliably.

**Remaining:**
- The backend service has some internal cleanup items - already
  discussed with the client - to complete before it goes to a real
  hospital. Not blocking current testing or demo work.

---

## Consolidated Summary

**Status: On Track**

Strong progress on both fronts of the Edge Agent Platform. All three
core components are built and available, and the hospital installer is
complete and entering final testing.

**Highlights:**
- All software components are built and versioned, ready for demo.
- The offline installer (works without internet access - a hospital
  requirement) is fully implemented.
- One known item on the backend service is tracked and will be
  resolved before real hospital delivery - already aligned with the
  client.

**Next steps:**
- Run a full end-to-end test on a real server.
- Publish the first complete, demo-ready package.
