# Ties' decisions on Product's open questions (2026-09-28)

Answers to `PRODUCT-REPORT.md` §4's five open questions, given directly in conversation with
the orchestrator (not a live `grilling` round — Product's report already did the frontier
framing; these are Ties' rulings on it, with one adjustment against Architect's sizing on Q3).
Per this repo's `wip/<slug>/` convention, this file records the decisions; it does not itself
edit `PRD.md`/`ARCHITECTURE.md`/`ROLE-DESCRIPTIONS.md`/`MULTI-AGENT-WORKFLOW.md` — items below
marked **[needs issue]** require their own work-item issue before any tracked file changes,
per this repo's own workflow rule.

---

**Q1 — A3 escape-hatch formalization (candidate 2.1) sequencing.**
Decision: **follow Product's recommendation** — after epic #295/OQ11 (issue #294) closes, not
before. No action now.

**Q2 — Does the epic-closing retrospective (candidate 2.3) apply retroactively to epic #295,
to close out #322?**
Decision: **follow Product's recommendation** — validate 2.3 against #295/#322 either way:
dogfooded before #322 closes if the retrospective mechanism gets built in time, retroactively
against #295's history afterward if #322 is closed manually first. No action now (2.3 itself
isn't scoped/built yet).

**Q3 — Where should named review-depth tiers (candidate 2.4) be scoped?**
Decision: **follow Architect's split, not Product's single-question framing.** Two separate
calls:
- (a) Build the classifier+dispatch mechanism now — small, low-risk, reuses
  `pre-merge-review`'s existing `context: fork` pattern and Reviewer's existing
  security-trigger list as the classifier. **[needs issue]**
- (b) When "thorough" becomes the default trigger for a given PR shape stays #307's call
  (the real ceremony-cost question). No action now on (b).

**Q4 — Is the adversarial-discussion / Party-mode-inspired pattern (candidate 2.5) worth
building now?**
Decision: **built now, but not executed yet** — i.e., scope and write the pattern/skill now
(design decision made, not deferred to "wait for a second organic need" as Product
recommended), but don't dispatch/run it as part of any session yet. **[needs issue]** for the
scoping/write-up itself; actual invocation stays unscheduled until a real use arises.

**Q5 — Adopt "built" vs. "done" vocabulary (candidate 2.6) now?**
Decision: **adopt now**, per Architect's correction of Product's original recommendation:
only the two endpoint terms (`built`, `done`), not BMad's full six-state lifecycle
(draft→ready-for-dev→in-progress→in-review→built→done, +blocked/dropped) — the intermediate
states are already covered by the `role:<name>` label (A5); importing the full state machine
would duplicate that. **[needs issue]** to actually touch `ROLE-DESCRIPTIONS.md`/
`MULTI-AGENT-WORKFLOW.md`.

---

## Not yet decided
Q1-Q5 only cover sequencing/scoping questions Product explicitly raised — they presuppose
candidates 2.1 and 2.3 eventually get built, but Ties has not yet given blanket acceptance to
the co-thinking session's full candidate list (2.1-2.8) or to promoting this session's output
into a real epic/PRD section, per the `wip/<slug>/` acceptance gate (README.md). That's a
separate, larger decision still open.
