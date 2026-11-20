Model/effort: Claude Opus, high reasoning effort, independent meta-reviewer role.

# Meta-review — epic #295 pilot #2 (issue #299 / PR #301), the second full five-role pipeline run

Independent and blameless. I wrote none of this, was not involved in producing it, and read
the trail cold: issue #299's body and all five comments (Product's pass, Ties' Q1/Q2 decisions,
Architect's plan with D1–D3, Product's ruling, QA's seven-arm spec), PR #301's description and
all three comments (Implementation, review round 1, the fix comment, review round 2), the merged
`compliance-evidence.sh` and `test/cases/s150_compliance_evidence.sh` at `a84631d`,
`TEST-SCENARIOS.md`'s S150 entry, issue #300, and pilot #1's
`wip/multi-agent-rollout/META-REVIEW-PILOT-RUN.md` in full.

Everything below stated as fact was **run**, not read: `./test/run.sh s150` (1 passed) on
`a84631d`; the merged collector against live PRs #10, #214, #249, #251, #252; a pass-through
`gh` wrapper that fails exactly one closing-issue lookup on PR #10; and two purpose-built fake
`gh` fixtures to test the one soundness claim the whole chain rests on.

Headline, stated plainly before the details: **pilot #2 is a genuine improvement on pilot #1 on
almost every axis I can measure** — fewer artifacts, fewer review rounds, a real Product↔Architect
loop-back that paid for itself, and a live-run gate (AC10) that caught an inaccurate claim three
passes had signed off. The failure mode did not disappear, though. It moved one level up and
recurred inside the correction that was written to fix it.

---

# Part A — the delivered increment

Four findings. **P2-1 is a real correctness gap on the exact path the work item declared sound
and protected with its most carefully designed test arm** — I reproduced it. P2-2 and P2-3 are
accuracy defects in the corrected coverage statement (the artifact AC10 exists to make honest).
P2-4 is a finding that the pipeline itself found, dispositioned, and then dropped.

The code that was written is correct. All three guards are in the right place, in gate 1's shape,
with the right wording split between AC1/AC2's and AC3's clauses; `./check` is green and the seven
arms are real. Nothing here is a reason to revert anything.

---

## P2-1 — Gate 2's same-model `not-evidenced` — the path AC6 protected and Arm D pins — is still unsound when one of several closing-issue fetches fails

- **Summary.** Product asserted, Architect "re-walked and confirmed", QA "re-derived from the code
  rather than from Architect's table", and Reviewer accepted, that gate 2's terminal
  `not-evidenced` (both markers found, same model, no exception) is sound under a failed issue
  lookup because "both markers were actually read, so the verdict rests on data in hand". The
  supporting argument given three times is the `tail -1` ordering fact: `collect()` prepends issue
  text before PR text, so an issue-side marker can never outrank a PR-side one.

  That argument is sound only when the winning markers are **PR-side**. With two or more closing
  issues, `issue_text` is accumulated **in `BUNDLE_ISSUES` order** (`compliance-evidence.sh:174-178`)
  and only then prepended to the PR text (`:181`). So a marker in the *second* issue outranks one
  in the first. If the markers that decided the verdict came from a successfully-read issue and a
  *later* issue's fetch failed, the unread text could have carried a newer `stage=Review` marker
  that flips the verdict — which is exactly the "confident claim of absence from a provably
  incomplete corpus" this work item exists to remove, surviving on the one path the work item
  fenced off.

- **Failure scenario — reproduced, both halves.** A fake `gh` where call A returns
  `ISSUE 265`, `ISSUE 266` and no markers of its own; `gh issue view 265` succeeds with
  `stage=Implementation model="claude-sonnet-5"` and `stage=Review model="claude-sonnet-5"`;
  `gh issue view 266` exits 1. The merged collector prints:

  ```
  | Review used a different or at-least-as-capable model, … | not-evidenced |
    `stage=Review` and `stage=Implementation` markers on PR #279 both record `claude-sonnet-5`
    with no `same-model-exception` |
  ```

  Then, changing only `gh issue view 266` to succeed with
  `stage=Review model="claude-opus-5"`, the same run prints:

  ```
  | Review used a different or at-least-as-capable model, … | evidenced |
    `stage=Review` marker (`claude-opus-5`) on PR #279 differs from `stage=Implementation` … |
  ```

  So the content of the unread issue does decide this row, and in the failing run the collector
  reports a compliance violation it cannot know occurred. Gates 1 and 3 degrade correctly in the
  same table; gate 2 does not.

- **Location.** `compliance-evidence.sh:312` (the unguarded terminal `printf`), the reasoning it
  rests on at `:158-161` and `:181`, and — most consequentially — the new soundness comment at
  `:125-133`, which now states the incomplete justification as a **rule for the next gate author**
  ("gate 2's same-model verdict (both markers were read)"). Upstream: issue #299's "Paths that look
  similar but are sound" section, Architect §6's "Not flagged as defects" list, QA §2.2.

- **Category.** correctness (narrow reachability) / reasoning recorded as invariant.

- **Verdict.** `CONFIRMED` — reproduced twice, in both directions.

- **Reachability and severity.** Narrow: it needs ≥2 closing issues, the deciding markers to be
  issue-side, and a later issue's fetch to fail. No PR in this repo currently has that shape (#214
  and #10 have 3 closing issues each but no issue-side Review/Implementation markers at all). It is
  strictly rarer than the bug #299 fixed — but so was A2 when it was filed, and the argument for
  fixing A2 (W4 will post these rows and act on them) applies unchanged.

- **Disposition — new issue, priority medium (ahead of W4 shipping, behind A1).** Not exempted by
  any of #299's eight non-goals; I checked all eight (non-goal 4 forbids *changing* precedence,
  which is not what this needs). Two candidate fixes, both cheap, and the choice is a real design
  call rather than an obvious one: (a) narrow the invariant — degrade gate 2's same-model verdict
  when the flag is set **and** more than one closing issue was named, which needs no provenance and
  is two lines; or (b) accept it as debt and, either way, **correct the comment at `:125-133` now**,
  because a wrong invariant written down for the next author is worse than an unwritten one. I
  would not re-open the code without the issue; I would treat the comment as the urgent half.

---

## P2-2 — The corrected coverage statement is still wrong, on the one row round 1 certified as right — by the same under-search mechanism it was correcting

- **Summary.** Round 1's Finding 1 corrected three coverage rows (AC1, AC5, AC6) that claimed
  "structurally unreachable live", and explicitly certified the fourth: *"AC2 is the one row that
  checks out. I scanned the 40 most recent PRs: none renders gate 3's no-marker-of-any-shape path."*
  The merged table therefore still reads **AC2 — Live? No**. That verdict is false. This repo's
  early PRs predate the `pre-merge-review:done` convention entirely, so essentially all of them
  render gate 3's P2 path, and several have closing issues, so the **degraded** branch is live too.

- **Failure scenario — reproduced on live data just now.** `./compliance-evidence.sh` on PRs #1,
  #3, #10, #37 and #40 each renders gate 3 as `not-evidenced — no pre-merge-review:done marker
  found`. PR #10 has three closing issues (#7, #8, #9); with a pass-through wrapper failing only
  `gh issue view 8`:

  ```
  | Per-stage model/effort recorded (…)          | indeterminate | … but a closing issue lookup failed, so absence can't be confirmed |
  | Review used a different or at-least-as-capable … | indeterminate | no `stage=Review` and/or `stage=Implementation` … so absence can't be confirmed |
  | Quality review before merge, with findings … | indeterminate | no `pre-merge-review:done` marker found on PR #10, but a closing issue lookup failed, so absence can't be confirmed |
  ```

  exit 0. That is AC1, AC2 **and** AC5's shape, all on real data, on a PR nobody in the chain looked
  at. The fix behaves correctly throughout — the defect is in the written claim, not the code.

- **Location.** PR #301 description, "Coverage statement" table, row AC2 (and the correction
  paragraph beneath it, which implies the remaining "No" was verified).

- **Category.** evidence-accuracy.

- **Verdict.** `CONFIRMED`.

- **Disposition — no new issue; correct the record and, more importantly, read the pattern.** The
  row's *prose* is honestly qualified ("no PR in the 40 most recently checked"), which is the form
  pilot #1 asked for; the **verdict column next to it is not**, and a reader takes the verdict. The
  sample was also chosen in the way most likely to be unrepresentative: the 40 most recent PRs are
  precisely the ones written after the marker conventions existed. See B3 — this is the third
  consecutive layer of the same error, and the recommendation belongs in the role contracts, not in
  an issue.

---

## P2-3 — The corrected AC5 row claims a live exercise that the live run cannot perform

- **Summary.** The merged table says AC5 is now exercised live because "PR #214 has three closing
  issues (#212/#213/#215); forcing failure on just #213 and forwarding the other two exercises the
  partial-failure shape live, **correctly**". QA's own §4/§3 is explicit that AC5's value is the
  *pairing* — gate 1 `evidenced` from the successfully-read issue **while** gates 2/3 degrade —
  because "only that pairing distinguishes 'one of two failed' from 'both failed'". PR #214 carries
  no `model-record` markers anywhere (verified: gate 1 lists all four stages as missing on a normal
  run), so its forced run degrades every gate and is **indistinguishable from a total failure**. It
  exercises AC5 as literally worded and not the property Arm C exists to prove.

- **Location.** PR #301 description, coverage table row AC5.

- **Category.** evidence-accuracy (over-claim, in the opposite direction from P2-2's under-claim).

- **Verdict.** `CONFIRMED` — `./compliance-evidence.sh 214` shows no stage markers from any of the
  three closing issues.

- **Disposition — negligible on its own; fold into P2-2's correction.** Worth one clause because it
  shows the correction round swung from "we under-claimed coverage" to "we now claim coverage we
  don't have" without a check in between. No issue.

---

## P2-4 — Round 2's own Finding 4 was merged open and then tracked nowhere

- **Summary.** Round 2 filed Finding 4: `TEST-SCENARIOS.md`'s S150 "Then" clause now mis-states the
  shipped behaviour in two places. It carries `<!-- finding:s150-scenario-text-stale status=open -->`,
  and its recommended disposition was "fold into the S150 update #300 will touch anyway, **tracked
  as a one-line note on #300**" — expressly: *"What is not fine is merging it unrecorded."* The PR
  merged four minutes later. Issue #300 has **zero comments**; no issue mentions the slug; and
  `TEST-SCENARIOS.md:1641-1644` on `main` still says a failed issue-comments lookup "degrades **its
  own row**" and that "a stale review marker is `not-evidenced`" — both now false.

  The same happened to round 2's other written residual: *"issue #299's AC10 ¶3 still asserts 'P1–P3
  do not fire on live data and remain fixture-only' … worth one edit to the issue body at merge
  time."* The issue body still says it, so the archived spec now contradicts its own merged PR.

- **Location.** `TEST-SCENARIOS.md:1632-1646`; issue #299's AC10 ¶3 and QA's §5.2; issue #300
  (empty).

- **Category.** spec/traceability accuracy, and a process leak (B4).

- **Verdict.** `CONFIRMED`.

- **Disposition — yes, a new issue (or a comment on #300), priority low but do it now.** The content
  is two clauses of prose; the reason to file it is that it is currently recorded *only* inside a PR
  comment on a merged PR, which is exactly the "silently vanishing finding" that
  `finding-carryforward-gate.sh` was written for (#241 AC2) — and that gate does not look at merge
  time. See B4's recommendation.

---

## Things I checked and found genuinely sound

Said because a review that lists only problems misrepresents the work.

- **The three guards are right, and one placement is better than anyone claimed.** P2's guard sits
  *after* the loose/malformed branch (`:352-360`), so a malformed marker keeps its own, more
  informative `indeterminate` instead of being swallowed. Round 1 noticed; nobody upstream specified it.
- **Arm D really does falsify what it is named for.** I re-derived it rather than trusting round 1's
  mutation table: the fixture reaches `:312` (past P1, past malformed, past differs, past the
  exception check) with the flag set, which is the single corpus in which a *sound* `not-evidenced`
  coexists with an incomplete corpus. Product's original arm could not have caught the over-broad fix;
  D3 was a real defect and it is really closed.
- **AC3a is exactly two characters, in both branches**, and Arm E pins the non-degraded string by
  equality plus a separate `-->` check — the one-branch-only drift D1 predicted cannot land.
- **Arm C's tripwire comment is present and correctly filed** on the AC5 arm, and AC5 genuinely
  needed no production code, which is the predicted signature of a correct fix.
- **The `may` reword (round 1's Finding 2) is accurate and introduced nothing.** I re-checked every
  path of all three flag-consulting gates: under flag=1 the reachable set is degraded `indeterminate`,
  gate 2's same-model `not-evidenced`, `evidenced`, and a flag-independent `indeterminate`. "May
  render" is true of that set; "render" was not. Arm F's pinned substring survives verbatim.
- **The stderr-hygiene fix (Finding 3) introduced nothing.** Four distinct `$SANDBOX/`-scoped files,
  no collisions, `$?` still read on the next line in each arm, exit-status assertions intact.
- **`./test/run.sh s150` passes on `a84631d`**, and the live runs I did on #10, #214, #249, #251, #252
  all exit 0 with six well-formed rows and the closed vocabulary.
- **A1 (the quoted-marker limitation) is now recorded honestly in the script itself** (`:103-118`),
  with pilot #1's corrected severity. Pilot #2 then produced two further natural reproductions of it —
  QA's fenced Arm D fixture in an issue comment poisoned PR #301's *own* gate 2, and round 1 had to
  defang its quotations to avoid doing it again. That is three in-the-wild instances on two work items,
  all generated by the pipeline's normal activity of writing about markers. A1 should be treated as a
  hard blocker on W4, not a debt row.

---

# Part B — retrospective, measured against pilot #1's retrospective

## B1 — Pilot #1's recommendations were followed, and the two that were followed hardest are the two that paid

Taking pilot #1's B5 list item by item, on evidence rather than intent:

**"Referencing is not carrying" (B5.1) — followed, and it is the single biggest quality difference
between the two runs.** Issue #299's body is 262 lines and self-contained: the three defective paths
with line numbers, the *sound* paths with the reasoning spelled out so a downstream role can check
rather than re-derive, verbatim evidence templates, eight closed non-goals. Product says explicitly
it is doing this because of pilot #1's lesson. The measurable effect: Architect's D1–D3, QA's §3.2/§3.3
gaps and round 1's Finding 2 are all findings *against the written spec* — they were only possible
because the spec was concrete enough to be wrong in public. Pilot #1's Product pass produced findings
about things that were missing; pilot #2's produced findings about things that were stated.

**The Reviewer live-run step (B5.3) — followed, as AC10, and it is what caught Finding 1.** It was
also strengthened beyond pilot #1's recommendation: QA split execution (Developer) from verification
(Reviewer) and required the Reviewer to re-run independently rather than read pasted output. The
Reviewer did, and then went past the brief by probing the repo's PR population — which is where the
correction came from. Ties' Q2 decision deliberately kept AC10 issue-scoped pending a second data
point. **That data point now exists and it is strongly positive: promote it.** My recommended
scope is still narrower than "every PR" — work items that change a program that reads an external
system — but with one addition from P2-2 below.

**The Orchestrator finding-disposition policy (B5.5) — followed, and the split it prescribes needs
refining.** Findings 2 and 3 touched tracked files and went back to Fullstack Developer, who fixed
them in `d3d18b2` and reported what it did. Finding 1 touched only the PR description and stayed
with the Orchestrator. On pilot #1's rule as written, that is exactly right. On pilot #1's *reason*,
it is not: F1's lesson was not "tracked files are special", it was "the direct-patch path has no gate
on it at all", with the mitigation "re-run the gate the finding cites and paste the output". Finding 1
cited no gate, because no gate can check a prose claim about which live PRs exercise which path — and
the un-gated edit duly shipped with two new errors (P2-2, P2-3) and left its upstream issue
contradicting it (P2-4). **So a PR description is not meaningfully different from a tracked file here;
what matters is whether the edit's claim is falsifiable by a command.** Refinement in B6.1.

**"QA enumerates production inputs, not only AC inputs" (B5.4) — followed, and it is the clearest
role-level improvement in the run.** QA §5.2 went to live PRs and corrected the *issue's own premise*
(P3 is live-reachable on #290/#292), before a line of code was written. Pilot #1 had nothing like this.
It is also where the recurring failure mode starts: QA checked three PRs.

## B2 — Cost is down, and down in the right places

Precise counts, pilot #1 → pilot #2:

| | Pilot #1 (#296/#298) | Pilot #2 (#299/#301) |
|---|---|---|
| Issue-phase comments | 5 | 5 (incl. Ties' Q1/Q2 ruling and a Product↔Architect loop-back) |
| PR comments | 8 | 3 |
| **Review rounds on the PR** | **3** (round 1, round 2, round 3 after the meta-review) | **2** |
| Fix commits after review | 2 (F1 needed two attempts) | 1 |
| Wall clock, first role pass → merge | ~10.5h across two sessions | **~2h in one** |
| Blocking findings at round 1 | 5 | 3 (1 blocking, conditional) |

Two review rounds is the floor this repo's design implies (a fixup commit invalidates the sha-pinned
marker, so a fresh round is mandatory), so pilot #2 hit the floor. Pilot #1's third round existed
because an out-of-band meta-review found live bugs; pilot #2's equivalent work was *inside* the
pipeline as AC10, and produced no extra round. **That is the overhead trending in the right direction
for the right reason** — not by cutting scrutiny, but by moving scrutiny earlier.

One bookkeeping defect worth naming because this pipeline's own artifacts count rounds: the two review
comments on PR #301 call themselves "Round 1 on this PR" and "round 4" respectively, with the second
referring to the first as "round 3". PR #301 had two review rounds. Whatever numbering the Orchestrator
was using, the durable record now disagrees with itself, and a future compliance reader (or W4) cannot
reconstruct it. Number rounds per PR, starting at 1.

## B3 — The recurring failure mode: a bounded sample promoted to a universal negative

This is the finding I would carry forward above all others, because it has now occurred at **four**
consecutive levels of the same work item, each level catching the previous one and then committing it
again one notch wider:

1. **Product** checked 4 PRs (#279, #290, #292, #298) → "P1–P3 don't fire on any real PR in this repo
   and stay fixture-only." (AC10 ¶3, still in the issue body today.)
2. **QA** checked 3 PRs → corrected P3, then concluded "AC5 cannot be exercised live at all" and "the
   single most important new arm is the one live runs are structurally unable to reach."
3. **Reviewer round 1** checked ~40 PRs → corrected AC1, AC5 and AC6 with real counter-examples
   (#214, #249, #251, #252), named the error precisely ("it generalized 'not reachable on the three
   PRs this chain happened to check' into 'not reachable live'") — and then certified AC2 as "the one
   row that checks out" on a 40-PR sample drawn entirely from the era *after* the marker conventions
   existed.
4. **Me**, checking the oldest PRs instead of the newest: AC2 is live-exercisable on #1, #3, #10, #37,
   #40, and the degraded path runs end-to-end on #10 (P2-2).

So: is Finding 1 evidence that the mechanism works, or evidence of a deeper failure mode? **Both, and
the "both" is the interesting part.** The mechanism works — each independent pass with real data found
a real inaccuracy the previous three had signed off, which is precisely what a multi-role pipeline is
for, and it is worth noting that no role ever got the *code* wrong; every error was in a claim about
the world. But the mechanism is being asked to do a job that a habit would do more cheaply. The habit
is two rules:

- **Never write "structurally unreachable / impossible / fixture-only" without either a proof from the
  code or the sample stated in the verdict itself.** "Not observed in the 40 most recent PRs" is a fine
  verdict. "No" is not, and neither is "structurally unreachable".
- **Choose the sample adversarially, not conveniently.** Every one of the four searches sampled the most
  recent, most familiar PRs — the ones most likely to conform to the conventions being tested. The
  cheapest correction available anywhere in this run was "also look at the oldest PR."

Note that the code was never wrong here. Both pilots' most expensive failures have been about the
*evidence record*, not the artifact: pilot #1 shipped a coverage presumption, pilot #2 shipped a
coverage overstatement and then a corrected overstatement. For a workflow whose entire product is
evidence, that is the risk class to instrument.

## B4 — Handoffs improved; the leak moved from the fix path to the disposition path

Role-to-role handoffs were better than pilot #1's, and the Product↔Architect loop-back is the reason.
**D1–D3 was well-executed, cheap and valuable, and it is not friction.** Six minutes elapsed between
Architect's plan and Product's ruling; all three were resolved role-to-role with no escalation; and D3
was a genuine defect of the kind that is invisible downstream — a test arm named for a failure mode it
could not detect. Product's ruling conceded it without hedging ("my error", "a scenario that cannot
falsify what it claims to falsify is the specific failure QA's role contract exists to prevent"). Had
D3 not been caught, the suite would have shipped green with its most important guard inert, and pilot
#1's exact headline ("four passes, so it's clean") would have recurred. A loop-back that costs six
minutes and removes a false guard is the cheapest thing in either pilot.

The leak this time is at the **exit**, not the entry. Two dispositions written down in round 2 —
Finding 4 onto #300, and the issue-body correction "at merge time" — were both executed by nobody
(P2-4). The pipeline is now good at producing findings and routing fixes, and has no mechanism at all
for the category "recorded, deferred, someone must carry it". `finding-carryforward-gate.sh` exists for
exactly this failure (#241 AC2, born from a PR that merged 17 seconds after an uncarried finding) and
it only compares review rounds *within* an open PR; it cannot fire at merge. Pilot #1 lost a round to an
unverified Orchestrator patch; pilot #2 lost a deferred finding to an unowned one. Same root: the
Orchestrator's own activities are the ones with no contract and no gate.

## B5 — Model choice: still well-calibrated, and the calibration argument has become genuinely useful

Recorded chain: Discovery opus/medium, Planning opus/medium, Discovery-ruling opus/low, Test opus/high,
Implementation sonnet/high, Review opus/high then opus/medium. `model-record-gate.sh` clean; no
same-model exception needed.

- **Opus/high at Test was the decisive spend, again, and for a sharper reason than in pilot #1.** QA's
  own effort argument says it: the pass's value was an adversarial sweep asking "can any arm go red at
  all for each AC", which is what surfaced the two untested ACs (AC3a's non-degraded branch, AC7) that
  Architect's four-arm contract missed. That is a different cognitive task from writing scenarios, and
  it is where the model floor actually binds.
- **Sonnet/high at Implementation: validated a second time, with a stronger signal.** The Developer
  implemented a seven-arm spec with exact-text assertions, demonstrated 14 red assertions before green,
  ran the AC10 live matrix, and its two review findings were a **spec** defect (AC7's over-broad wording,
  which it had implemented verbatim and correctly) and two omissions from a spec it had otherwise
  followed. Zero "the contract was misunderstood" findings across two pilots. The Opus-plan/Sonnet-build
  split can be treated as established.
- **Opus/medium for the re-review round was right, and pilot #1's speculative knob is now evidenced.**
  Pilot #1 suggested "a re-review of a findings-only fixup may drop one effort level". Pilot #2 did
  exactly that, argued it explicitly ("the capability floor for 're-derive whether one word resolves a
  stated contradiction' is met at medium; what the round needed was the same *model*, not the same
  *effort budget*"), and the round still produced a new finding. Promote that sentence into
  `model-choice`.
- **Where the calibration did *not* help.** Every one of my Part A findings is a place where more
  reasoning at the same desk would not have helped: P2-1 needed one more fake-`gh` fixture, P2-2 needed
  one more `gh pr list | tail`. Two pilots now agree that this pipeline's residual risk is not reasoning
  depth but **contact with inputs nobody chose**. The lever remains a contract item, not a bigger model.

## B6 — Recommendations, in priority order

1. **Replace pilot #1's tracked-file/artifact split with a falsifiability split.** A finding's fix may
   stay with the Orchestrator only if the finding names a command that can falsify the fix, and the
   Orchestrator pastes that command's output. If the fix is a claim about live behaviour that no command
   can check, it goes back to whoever can *produce* the evidence (Fullstack Developer), who re-runs and
   pastes. *Evidence:* Finding 1's un-gated description edit shipped P2-2 and P2-3 and orphaned P2-4.
2. **No PR merges with an open `finding:` slug in its latest review comment unless that comment names
   the issue number carrying it.** Extend `finding-carryforward-gate.sh` with a merge-time mode, or add
   it to the merge guard; it is a grep over one comment. *Evidence:* P2-4, and #241 AC2's original
   motivation.
3. **Add the sampling rule to `ROLE-DESCRIPTIONS.md` for Product, QA and Reviewer alike:** no universal
   negative about live reachability without a proof from code or the sample carried in the verdict, and
   samples chosen adversarially (oldest/most non-conforming, not most recent). *Evidence:* B3, four
   consecutive instances in one work item.
4. **Promote AC10 to a standing rule** (Ties' Q2, now with its promised second data point), scoped to
   work items changing a program that reads an external system, with QA's execution/verification split
   built in: Developer runs and pastes, Reviewer independently re-runs at least one case, and the
   coverage statement must name a covering arm for every "not exercised live" row. Add rule 3 to it.
5. **Correct the durable record for this work item**: issue #299's AC10 ¶3 and QA §5.2 (still assert
   fixture-only), PR #301's AC2 and AC5 rows, and `TEST-SCENARIOS.md`'s S150 "Then" clause. All prose;
   one small PR.
6. **File P2-1** (gate 2's same-model path under multi-issue partial failure) and fix the invariant
   comment at `compliance-evidence.sh:125-133` either way.
7. **Raise A1 from debt to W4 blocker.** Three natural reproductions across two pilots, all produced by
   the pipeline's ordinary activity of writing about markers, including one that made PR #301 report
   *itself* non-compliant. W4 posts marker-discussing text into PRs by design.
8. **Number review rounds per PR**, starting at 1 (B2).

## B7 — Is OQ11 answerable now?

**My independent judgment: yes for a bounded decision, and the bound matters more than the yes.**

Pilot #1's meta-review said no and named four gaps. Pilot #2 closes two of them cleanly and one
partially:

- *Meta work item* — **mostly closed.** #299 is an ordinary correctness bug in existing behaviour, with
  a three-guard fix and a real regression suite. It is not, however, outside the workflow's own domain:
  the program under repair is the workflow's compliance instrument, its worked examples are this repo's
  own PRs, and the bug was found by the workflow's own meta-review. Every role still played at home.
- *No role disagreement* — **closed as far as role-to-role disagreement goes.** Architect found three
  defects in Product's spec, including one that would have shipped an inert guard; Product conceded all
  three in writing; Reviewer overturned a coverage claim that three prior passes had asserted. That is
  real disagreement with real consequences, and it resolved cheaply.
- *Orchestration untested* — **still open, and it produced this pilot's process defect too** (B4).
- *Cost barely sampled* — **partially closed**: two points now (M and S), both single-file, both in
  bash, both in this repo.

What is still untested, and it is the same item pilot #1 named: **no disagreement has ever had to
escalate to Ties under Decision 4 / A7.** Both of pilot #2's conflicts resolved because one side
conceded completely and quickly. Ties was consulted twice — Q1/Q2 in the Product pass — but those were
*open questions raised with recommendations*, which is the easy path, not an escalation from a deadlock.
The mechanism epic #65 is least sure about has now survived two pilots without being exercised once.
Two further categories are unsampled: a work item in a domain the pipeline must *learn*, and one large
enough that the plan cannot be carried in a single Architect comment.

So my recommendation for #294/OQ11, differing from pilot #1's "not yet" but not by much:

**Record OQ11 as answered *affirmatively and narrowly*: the five-role pipeline is proven, on two runs,
for small-to-medium single-module work items inside this repo's own domain, and broader implementation
may be kicked off on that basis.** The two runs support the falsifiable claim epic #65 rests on — each
role finds things the previous one missed at a rate that justifies its cost — and pilot #2 shows the
cost curve bending down as the contracts absorb what the pilots learn, which is the more important
signal. Do not, however, record it as "the workflow is validated" without the residual named in the
same sentence: **the escalation path is still unexercised, and both pilots' surviving defects are in the
evidence record rather than the code.** If one more pilot is run before the broader kickoff, choose it
for those two properties — a genuinely contested design decision that can deadlock, in a domain outside
this repo — rather than for size. Running a third pilot that is another small bash fix here would add a
data point to the part that is already proven.

---

# Recommendation on the merged increment

**Nothing here warrants reverting or re-opening PR #301.** The code is correct and better tested than
anything else in this repo. What it needs is one small follow-up PR carrying items B6.5 and B6.6
(record corrections plus the invariant comment), one new issue for P2-1, and one comment on #300 or a
new issue for the S150 scenario text. The process recommendations (B6.1–B6.4, B6.7, B6.8) belong in
`ROLE-DESCRIPTIONS.md`, the `pre-merge-review` skill and epic #295, and are worth more than any of them.
