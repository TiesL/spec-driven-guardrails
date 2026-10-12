Closes #408. Refs #411 and #430.

## Release candidate

This PR brings `release/408-process-improvements` into `main`. The agreed
membership is #410, #414, #415, #420, and #422–#430. #430 supplies acceptance
evidence rather than a code change. #409 is deferred. #455 remains outside
this release and paused until this release lands. Absorbed #400, #413, #421 and
#404 items 1–5 are not presented as separate shipped features; #404 item 6 is
excluded.

The candidate adds fresh Reviewers for every Review round, finding-class
loop-back with an override flow, a bounded orchestrator decision table and
risk notes, macOS CI, shared Markdown/record/round readers, effort removal,
record-v2 gate and consumers, and release documentation. The notes remain
under `Unreleased`; the current tagged release is v0.3.0.

## Evidence

- [#430 adopter corpus and dry-run acceptance](https://github.com/TiesL/spec-driven-guardrails/issues/430#issuecomment-6132587414). The per-adopter corpus table is also posted as a comment on this PR.
- [Fresh holistic QA, thorough](https://github.com/TiesL/spec-driven-guardrails/issues/408#issuecomment-6132973927): no release blocker.
- [Fresh holistic Reviewer, thorough](https://github.com/TiesL/spec-driven-guardrails/issues/408#issuecomment-6133010298): no release blocker.
- Final documentation PR #466 passed 249 local tests and both Linux and macOS CI at its reviewed head; this release PR needs its own green CI.

## Compatibility and limits

Three `CHANGES.md` answers require reconfirmation against v0.3.0:
`quality-review-before-merge` is meaning version 4;
`process-model-choice` and `process-multi-agent-roles` are first versioned at 2.
Only column-0 whole-line records count. Near misses are named, and the latest
candidate governs the latest-record finding. Invalid overrides are refused.
Adopters can re-post records through the emitter or record a valid override.
The `--effort` flag is temporarily accepted and ignored with a warning;
effort is no longer chosen or checked. Different-model capability cannot be
verified from artifacts.

The reader has stated CommonMark limits, including #445 and #446; the
one-definition lint is bounded and evadable. An unavailable GitHub read is
fail-open, not a successful check. The #430 corpus covers readable adopters in
the owner's account and Ties-IT-advies organization and shares the reader's
blind spots. Its scratch PR #10 has no independent CI. In the forced-failure
run, `role-play-unchecked:` appeared in a hook transcript event but did not
reach the agent as command output. The synthetic inline-only scratch PR #14
was blocked by the release gate; scratch #5 also changes to blocked, while
#10 remains non-blocking.

The two low holistic-review findings are filed for later work:
[#467](https://github.com/TiesL/spec-driven-guardrails/issues/467) (stale warning
visibility wording) and [#468](https://github.com/TiesL/spec-driven-guardrails/issues/468)
(diff whitespace). Neither reviewer found a release blocker.

## Version proposal and decision

Proposed bump: **minor, v0.4.0**, for new opt-in workflow behavior and the
three reconfirmations under this project's `0.y.z` convention. This is a
proposal. Merging into `main`, selecting the version, cutting the dated
changelog section, updating the README current-version token, and tagging all
await the maintainer's explicit decision after this PR's CI is green.
