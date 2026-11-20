# Disputes log — epic #295 execution

Append-only log of genuine role-to-role disagreements (not clarifying
questions, not a review finding a defect and looping back for a fix) that
arose while running #295's work items through the five-role pipeline.
Per this epic's own dispute-resolution rule: first attempt mutual
agreement between the roles involved, recorded as a back-and-forth on the
issue/PR itself; if that doesn't converge, Reviewer decides as a third
party — stating each side's position and the reasoning for the decision,
not just the outcome. The A3 escape hatch (skip/narrow a role) is a
separate, more drastic mechanism, used only when genuinely warranted and
logged on the affected issue itself, not here.

One entry per disagreement: roles involved, options considered,
conclusion, and whether it resolved by mutual agreement or by Reviewer's
decision.

---

## No entries yet, as of #237/W2 (#313)/W3 (#315)

Running #237, #313, and #315 through the full five-role pipeline (2026-09-27
– 2026-09-28) produced no genuine role-to-role disagreement meeting this
log's bar. What did happen, several times, was the ordinary quality-gate
pattern this epic already expects and doesn't count as a dispute: Reviewer
independently found a real defect in a prior role's work (a missed
cross-reference, a design flaw in how PRs get discovered, a broken test
witness) and the pipeline looped back to fix it — sequential handoff and
correction, not two roles asserting incompatible positions that needed
reconciling. The most severe instance (#315/PR #316: Reviewer found
Architect's original GraphQL-based PR-discovery design doesn't work from
inside a Claude Code session and is separately blind to every
release-branch PR) went back to Architect for a redesign rather than being
patched ad hoc by Fullstack Developer — but Architect did not dispute
Reviewer's finding; it accepted the finding as correct and produced a new
design. No mutual-agreement-then-Reviewer-decides cycle was needed because
no side disagreed with the other's stated position.

This section will be replaced by real entries the moment a genuine
disagreement occurs on a future work item (W4/#294, or any other running
through this pipeline) — logged as it happens, not reconstructed
afterward.
