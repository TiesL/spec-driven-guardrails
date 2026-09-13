# Adoption of shared workflow changes

Per change from `CHANGES.md` in [spec-driven-guardrails](https://github.com/TiesL/spec-driven-guardrails)
whether this project applies it. No row means: not (yet) applicable —
the question shows up on its own once that changes.

| Change | Answer | Date | Notes |
|---|---|---|---|
| traceability-link-1 | yes | 2026-09-08 | at adoption — requires substantiation during PRD/architecture |
| process-prd | yes | 2026-09-08 | at adoption — requires substantiation during PRD/architecture |
| architecture-document | yes | 2026-09-08 | at adoption — requires substantiation during PRD/architecture |
| test-unit | yes | 2026-09-08 | at adoption — requires substantiation during PRD/architecture |
| test-feature-gwt | yes | 2026-09-08 | at adoption — requires substantiation during PRD/architecture |
| test-tdd-seams | yes | 2026-09-08 | at adoption — requires substantiation during PRD/architecture |
| quality-review-before-merge | yes | 2026-09-08 | at adoption — requires substantiation during PRD/architecture |
| ci-gate-on-merge | yes | 2026-09-08 | at adoption — requires substantiation during PRD/architecture |
| process-technical-debt-register | yes | 2026-09-08 | at adoption — requires substantiation during PRD/architecture |
| process-refactoring-triggers | yes | 2026-09-08 | at adoption — requires substantiation during PRD/architecture |
| process-diagnose-bug | yes | 2026-09-08 | at adoption — requires substantiation during PRD/architecture |
| spec-security | yes | 2026-09-08 | Relevant, limited — the guardrails hook (F7) is itself a security measure; check-traceability.sh parses untrusted issue/PR text without eval. See PRD.md, Security section. |
| spec-data-integrity | yes | 2026-09-08 | Strongly relevant — WORKFLOW-ADOPTION.md is the durable record of decisions and must never be overwritten; adopt.sh must stay idempotent. See PRD.md, Data integrity section. |
| spec-failure-modes | yes | 2026-09-08 | Strongly relevant — a hook never blocks a session unless that's explicitly its job (F7/F8), and then fails open without gh or network. See PRD.md, Failure modes section. |
| spec-observability | yes | 2026-09-08 | Relevant — silent degradation (a broken symlink behind a hook chain that ends in `|| true`) is the main failure mode; check and the outdated-adoption notice are the antidote. See PRD.md, Observability section. |
| spec-performance-scale | no | 2026-09-08 | Barely relevant at this scale (O(n·m) over roughly 27 entries, negligible) — briefly named in PRD.md, Performance and scale section, for discoverability, not an active requirement. |
| spec-deployability | yes | 2026-09-08 | Strongly relevant, unusual shape — "deploying" is merging to main; four projects follow main live via symlink, with no staging or opt-in. See PRD.md, Deployability section. |
| spec-privacy | no | 2026-09-08 | Not applicable — no personal data beyond the git authorship information that's already there. See PRD.md, Privacy section. |
| spec-compliance | yes | 2026-09-08 | Not as a legal requirement, but as self-imposed auditability — the adoption record exists specifically to make demonstrable which project applies which agreement and why. See PRD.md, Compliance and auditability section. |
| spec-backup-recovery | yes | 2026-09-08 | Relevant, low risk — everything of value lives in git; the fragile part (local, untracked symlinks) recovers via an idempotent adopt.sh rerun. See PRD.md, Backup and recovery section. |
| spec-portability | yes | 2026-09-08 | Relevant, with one deliberate new binding — skills are Claude Code-specific (frontmatter as context/model), bash 3.2 is the broader boundary. See PRD.md, Portability section. |
| spec-maintainability | yes | 2026-09-08 | Strongly relevant, core of this release — F3/F4/F5 remove parser, NFR, and reading-load duplication, at the cost of a new skills/nfr/test tree. See PRD.md, Maintainability section. |
| spec-testability | yes | 2026-09-08 | Strongly relevant, once the biggest gap (zero tests against fourteen specified scenarios) — now a test harness with 83 scenarios. See PRD.md, Testability section. |
| spec-usability | yes | 2026-09-08 | Relevant — the user is Ties plus the agent; F6 makes the substantiation load visible and phases it, instead of seventeen rows of homework at once. See PRD.md, Usability section. |
| spec-cost-management | yes | 2026-09-08 | Relevant, in tokens — WORKFLOW.md loads in full in every session of every project; skill descriptions cost little, their body only on invocation. See PRD.md, Cost control section. |
| spec-documentation | yes | 2026-09-08 | Relevant — README.md was demonstrably outdated (F16); every skill carries its own explanation, the core explicitly points to it. See PRD.md, Documentation section. |
