Model/effort: Claude Opus, high reasoning effort, independent meta-reviewer role.

# Meta-review — epic #295 W1 (issue #296 / PR #298), the first full five-role pipeline run

Independent, blameless. I wrote none of this and was not involved in producing it. I read
`wip/multi-agent-rollout/PRODUCT-REPORT.md` and `ARCHITECT-REPORT.md`, issue #296 with all
comments, PR #298 with all comments and its diff, `compliance-evidence.sh`,
`test/cases/s150_compliance_evidence.sh`, the `S150`/`F34` entries,
`wip/multi-agent-development/ROLE-DESCRIPTIONS.md`, and
`CO-THINKING-PILOT-RETRO-ORCHESTRATOR.md`. Everything below that is stated as fact was
verified by running it, not by reading a claim about it.

Two things I checked before starting, because assuming otherwise would make this review
theatre: the `S150` suite passes on this commit (`./test/run.sh s150` → 1 passed), and the
five prior passes were genuinely substantive (they were — see Part B). Neither of those
made the increment clean.

---

# Part A — the delivered increment

Four findings. **A1 and A3 are real and reachable on production input today** — I triggered
both by running the shipped script against a live PR. A2 is a latent inconsistency with the
script's own documented contract. A4 is a test-suite trap that is dormant but will bite.

None of them is a reason to throw the increment away: the collector is well-built, the test
file is genuinely strong, and the review chain caught most of what there was. But "five
passes, so it's clean" does not survive contact with a live run.

---

## A1 — The collector reads marker-shaped text quoted *inside* PR prose as real evidence, and this already produces a false statement on PR #298

- **Summary.** `BUNDLE_TEXT` is the flattened concatenation of the PR body plus every PR and
  closing-issue comment. Every gate predicate greps it for marker shapes. Nothing
  distinguishes a marker that *is* a marker from a marker that is being *quoted or discussed*
  inside prose or a fenced block. PR #298's own description quotes the collector's manual
  #279 output verbatim, including the literal string
  `<!-- pre-merge-review:done sha=6e00a8c38bf18f19cd53084b5c77ae476c1e74e6 -->`.

- **Failure scenario — reproduced live, not hypothesised.** `./compliance-evidence.sh 298`
  on this commit prints, in the gate-3 Evidence cell:

  ```
  ... sha equals `headRefOid` (an earlier marker for
  `6e00a8c38bf18f19cd53084b5c77ae476c1e74e6` is stale)
  ```

  `6e00a8c3…` has never been a commit on `feature/296-compliance-evidence-collector`. It is
  PR #279's head, present only because PR #298's description quotes a table about #279. I
  confirmed the provenance: `gh pr view 298 --json body,comments` matches that sha on exactly
  one line, and it is inside the quoted output block in the PR body. So the collector's very
  first real-world run on its own PR already prints a statement about that PR's review
  history that is false.

  The dangerous direction is the mirror image. Gate 3 goes `evidenced` when a quoted marker's
  sha *equals* `headRefOid`. That is exactly what happens the moment anyone pastes the
  collector's own output for PR *N* into PR *N* — which is precisely what W4 is being built
  to do, and precisely what Fullstack Developer already did by hand in this PR's description.
  The collector then evidences a review that never happened, from an echo of itself. Gate 1
  and gate 2 are self-fulfilling the same way: this review comment, quoting marker syntax,
  becomes evidence.

- **Location.** `compliance-evidence.sh:173-238` (`collect()`, building `BUNDLE_TEXT`) and
  every `gate_*` predicate that greps it — `:284-329`, `:331-364`, `:366-405`.

- **Category.** correctness.

- **Verdict.** CONFIRMED (the stale-sha misstatement reproduced live on PR #298; the
  `evidenced`-from-an-echo direction follows from the same code path by construction).

- **Disposition — hold for a *record*, not for a code fix.** Round 1 flagged self-ingestion
  as "one observation, deliberately not filed as a finding", deferred it to #295 before W4,
  and judged that "gate 3's sha comparison limits the damage". That last clause is backwards:
  the sha comparison is the mechanism by which the self-echo becomes a *pass*. A robust fix
  (strip fenced blocks and backtick spans before matching; or match only markers that are the
  entire trimmed content of their own line) is not a one-liner and does not belong under this
  PR's time pressure. What *should* land before merge is cheap and matters: a Technical-debt
  row in `PRD.md` next to the existing `normalize_model()` row, and a note on #295, both
  stating the *correct* severity — the collector can evidence a gate from its own output, and
  W4 must not be built until that is closed. Merging with the round-1 characterisation as the
  only record leaves the next reader with an assessment I have now shown to be wrong.

---

## A2 — A failed closing-issue lookup degrades gate 1 to `indeterminate` but lets gates 2 and 3 assert `not-evidenced`

- **Summary.** `BUNDLE_ISSUE_LOOKUP_FAILED` is set when a `gh issue view` call fails, and the
  script's own header states that `indeterminate` covers "a failed sub-lookup". Only
  `gate_stage_models()` consults the flag. `gate_review_model()` and `gate_review_marker()`
  read the same (now incomplete) `BUNDLE_TEXT` and report confident absence. The warning the
  script prints on stderr — "stage evidence involving it may render as indeterminate rather
  than not-evidenced" — is therefore true of one gate out of three that depend on issue text.

- **Failure scenario — reproduced.** With a fake `gh` where call A succeeds (four stage
  markers on the PR, one closing issue) and `gh issue view` exits 1, the table prints:

  ```
  | Review used a different or at-least-as-capable model, … | not-evidenced |
      no `stage=Review` and/or `stage=Implementation` model-record marker found on PR #279 |
  | Quality review before merge, with findings in the PR | not-evidenced |
      no `pre-merge-review:done` marker found on PR #279 |
  ```

  Both cells assert that no marker was found, when a third of the searched corpus could not be
  read. If the Review marker and the `pre-merge-review:done` marker lived on the issue — the
  case the ordering comment at `:214-218` explicitly designs for — this is a compliance table
  reporting "no review happened" because the network blinked. That is the exact regression
  class `model-record-gate.sh` was fixed for in PR #249 round 2, which QA finding (f) cited by
  name and which the test file covers **for gate 1 only** (`call-C-fails` arm asserts
  `row_status … 1` = `indeterminate` and nothing about rows 2 and 3).

- **Location.** `compliance-evidence.sh:331-364` (`gate_review_model`) and `:366-405`
  (`gate_review_marker`); the flag is read only at `:316`. Test gap:
  `test/cases/s150_compliance_evidence.sh`, the `call-C-fails` arm.

- **Category.** correctness / test-coverage.

- **Verdict.** CONFIRMED.

- **Disposition — acceptable as follow-up debt, but it is the cheapest of the four to fix
  now.** Two `if [ "$BUNDLE_ISSUE_LOOKUP_FAILED" -eq 1 ]` guards on the two negative return
  paths, plus two assertions on the existing `call-C-fails` arm. If it does not land here, it
  needs an issue, not silence — the asymmetry is invisible to a reader of the output.

---

## A3 — Gate 1's non-uniform-model branch has zero test coverage and renders with a stray leading space — and it is the branch this repo's own pipeline always takes

- **Summary.** `gate_stage_models()` has two `evidenced` renderings: "all `<model>`" when the
  four stages share a model, and a per-stage `summary` otherwise. `summary` is built with
  `summary="$summary $stage=\`$model\`,"` starting from an empty string, so it always carries
  a leading space, which `${summary%,}` does not strip and `cell()` does not remove (it only
  trims the *ends* of the whole cell, and the space is interior, right after the `(`).

- **Failure scenario — reproduced live.** `./compliance-evidence.sh 298` prints:

  ```
  | Per-stage model/effort recorded (…) | evidenced | `model-record` markers on PR #298 for
  Discovery, Planning, Test, Implementation ( Discovery=`claude-opus-5`, …) |
  ```

  Note `( Discovery=`. Cosmetic in isolation. What is not cosmetic is *why* nobody saw it:
  every one of the nineteen fixtures uses a single model across D/P/T/I
  (`grep -o 'stage=[A-Za-z]* model="[^"]*"'` on the test file returns `claude-sonnet-5` for
  every stage, with one `Sonnet 5` variant that exercises gate 2 only). The mixed-model branch
  was never executed by any test, by QA's nine-finding fixture audit, or by either review
  round — and it is the branch that fires on **every PR this multi-agent pipeline produces**,
  because the pipeline's whole design point is Opus for Discovery/Planning/Test and Sonnet for
  Implementation. The one AC1 worked example everybody verified against is PR #279, a
  single-model PR. The suite is well-built but validates the collector against the world
  *before* the workflow it exists to measure.

- **Location.** `compliance-evidence.sh:300` (the `summary` accumulation) and `:327` (the
  render); `test/cases/s150_compliance_evidence.sh` — no mixed-model gate-1 fixture anywhere.

- **Category.** code-quality (the space) / test-coverage (the branch).

- **Verdict.** CONFIRMED.

- **Disposition — worth fixing before merge.** The rendering fix is one character
  (`summary="${summary# }"` alongside the existing `malformed`/`missing` trims at `:308-309`,
  which already do exactly this). The fixture is one more `case` arm copied from AC1 with two
  stages switched to `claude-opus-5`, asserting gate 1 `evidenced` and the exact cell text.
  Both together are under fifteen lines, and they close the one coverage hole that sits
  directly on the pipeline's own primary use case.

---

## A4 — All nineteen fixtures share one `gh` file path, so the `fakebin_*` variables are nineteen names for the same thing

- **Summary.** `fake_gh_bin()` (`test/lib.sh:178-187`) always writes `$SANDBOX/fakegh/gh` and
  echoes `$SANDBOX/fakegh`. Every `fakebin_ac1`, `fakebin_ac3a`, … `fakebin_longcell` in
  `s150_compliance_evidence.sh` therefore holds an identical string, and each
  `run_build_fake_gh` overwrites the previous arm's script. The suite is correct today only
  because every arm happens to run immediately after building its own fixture.

- **Failure scenario.** Add an arm that re-runs an earlier fixture — the natural shape for a
  regression check, and precisely what the existing determinism re-run
  (`output_ac1_again="$(PATH="$fakebin_ac1:$PATH" …)"`, `:746`) looks like. Placed anywhere
  below a later `run_build_fake_gh`, it silently executes the *wrong* fixture and either
  passes vacuously or fails with a message naming the fixture it did not run. The variable
  names actively advertise a per-arm isolation that does not exist.

- **Location.** `test/cases/s150_compliance_evidence.sh`, all `fakebin_*` assignments;
  `test/lib.sh:178-187`.

- **Category.** test-design (latent).

- **Verdict.** CONFIRMED (the shared path is verifiable from `test/lib.sh`); the failure is
  PLAUSIBLE in the sense that no current arm triggers it.

- **Disposition — follow-up debt, correctly.** Not worth churning this PR. Either parameterise
  `fake_gh_bin` with a per-arm subdirectory, or add one comment at the top of the
  `fakebin_*` block stating "all of these are the same path; build immediately before use,
  never re-run an earlier one". The comment costs two lines and defuses it.

---

## Things I checked and found genuinely sound

Stated because a review that only lists problems misrepresents the artifact.

- **The red-CI arm (QA finding (c)) is load-bearing, not decorative.** I confirmed the D6
  logic independently: `collect()` decides call-B success from *parsed stdout*, not exit
  status, so `bucket=fail` with exit 1 reaches `gate_ci`'s `fail|cancel` arm. The wrong
  implementation QA predicted really would fail this arm.
- **`normalize_model()` is byte-identical to `model-record-gate.sh`'s**, and the duplication
  is recorded as debt with both directions named. The right call given the dogfood-only
  boundary.
- **The exit-code surface (0/1/2/3/4) matches the code**, and exit 2 is now exercised by
  invoking the script, not by grepping its source.
- **AC5's source grep strips comment lines first** — without that, the header's own
  "never calls `gh pr comment`" prose would fail it. That is the S113 trap, avoided.
- **`local` is declared separately from every command substitution**, so every `$?` read in
  `collect()` is the subshell's status and not `local`'s. This is the single most common bash
  review miss and it is not present here.
- **Two smaller things I looked at and decided not to file.** `gate_ci` counts
  `bucket=skipping` toward green — defensible, and consistent with how `gh` reports skipped
  checks. And `gh issue view` runs inside a `while read` loop fed by a here-string, the classic
  stdin-consumption shape; real `gh issue view` does not read stdin, and the fake certainly
  does not, so this is a hazard note rather than a defect.

---

# Part B — retrospective on the pipeline's first real run

The honest headline: **the pipeline worked, and it worked better than the co-thinking pilot
did.** Each role's output visibly consumed the previous one's and improved on it — Product
found three real gaps in an already-Architect-reviewed spec, Architect found seven, QA found
nine in Architect's fixture contract including the one (red CI) that would have let a wrong
implementation ship green, Fullstack Developer flagged both of its deviations instead of
absorbing them, and Reviewer verified rather than accepted, twice, by mutation. That is a
functioning pipeline, not a ceremony.

What follows is where it cost more than it needed to, and what the evidence says should change.

## B1 — The handoffs worked; the one that leaked was Reviewer → Orchestrator

Every *role-to-role* handoff in this run was mediated by a durable artifact (issue comment,
PR comment, commit) and every downstream role demonstrably read it. Decision 1's "no
chat-memory handoff" held without anyone having to police it, and the co-thinking pilot's
convergent complaint — one role characterising another's position in its own voice — did not
recur, because on a real work item the upstream artifact is the *issue itself*, which the
downstream role edits rather than paraphrases.

The one place work leaked was the exit ramp. F1 was the only finding Reviewer could not fix
itself (the `pre-merge-review` skill's `allowed-tools` excludes editors, correctly), and it
was the only finding that took three attempts across two rounds. That is not a coincidence,
and it is the subject of B2.

Second-order observation worth recording: **Product's §5 diagnosis is the most reusable
output of this entire run.** "A Product phase whose output is an issue must inline anything
load-bearing that currently lives in a `wip/` report, an untranslated source, or a
conversation — referencing is not carrying." All three of Product's own findings, and
arguably QA's finding (b), reduce to that one rule. It should go into W2's Product role
contract verbatim.

## B2 — The two-tries-for-F1 slip is a symptom, and the policy should change

The Orchestrator's first F1 fix wrote
`**Covers:** F34, S150 (new — this work item's own functionality and its test scenario)`.
`scenario-gate.sh` splits on commas and matches each token with `grep -qxF`, so the second
token became the whole parenthetical and never equalled `S150`. The field looked fixed and
was not; round 2 caught it only because Reviewer re-ran the gate instead of reading the field.

Three things make this a symptom rather than a slip:

1. **The failure mode is specific to the "trivial, I'll just patch it" mindset.** The edit was
   treated as too small to verify, so it was not verified. A Fullstack Developer handed the
   same finding would have done what it did with every other finding in this run: applied the
   fix and then *run the gate*. It has the tooling and the habit; the Orchestrator, patching
   between dispatches, has neither in the same way.
2. **The finding itself told the fixer how to verify it.** Round 1's F1 named the exact
   command (`scenario-gate.sh .`), the exact expected output (nothing), and three precedent
   issues showing the bare-token form. Everything needed was in the finding. It was not used.
3. **It is the second instance of the same pattern in this run.** The Orchestrator also
   applied Architect's D4/D5/D6/D7 directly to the issue body. Those were mechanically
   correct — but nothing verified them either, and the only reason we know they were right is
   that Reviewer later re-derived them. The direct-patch path has no gate on it at all.

**Recommendation.** Change the policy, narrowly and mechanically, rather than banning direct
Orchestrator patches:

- Any finding whose fix touches a **tracked file** goes back through Fullstack Developer,
  without exception. That is already effectively what happened for F2-F5 and it worked.
- A finding whose fix touches only a **GitHub artifact** (issue body, label, `Covers:` field)
  may stay with the Orchestrator — Reviewer cannot make it, and routing it to a Developer to
  run `gh issue edit` is ceremony. But it carries a standing obligation: **the Orchestrator
  must re-run the gate the finding cites and paste its output into the closing comment.** F1
  cited a runnable gate. Had that rule existed, the bad edit would have been caught in the
  ninety seconds after it was made rather than in a whole extra review round.
- Corollary for Reviewer: a finding whose fix is an artifact edit should always name the
  verification command, as round 1's F1 did. Round 1 got this right; make it the contract.

## B3 — Two review rounds was correct cost, and would have been needed anyway

Round 1 found five real findings on a first implementation of a 480-line script with a 796-
line test file. Round 2 existed because four of them were fixed in a new commit, and this
repo's marker pins a review to a sha — a fixup commit *must* get a fresh review. That is the
design working, not overhead.

So the answer is: **two rounds is the expected cost, and round 1 was not insufficiently
thorough.** Round 1's F1-F5 are all genuine, and round 2's mutation testing (five deliberate
defects, each confirming the new assertions actually fail) is the strongest verification pass
in the repo's history that I can see. If anything the round-2 review was over-thorough for
what it was reviewing — a 60-line fixup — but "over-thorough on the fixup that closes the
findings" is the right direction to err.

The avoidable part is narrow and is exactly B2: had F1 been fixed correctly the first time,
round 2 would have closed with an unconditional approve instead of carrying the same finding
forward. One extra gate invocation, not one extra round of process.

One genuinely missing round, though: **nothing in the pipeline ran the finished artifact
against live input that differed from the worked example.** Everyone verified against PR
#279, the single-model PR that AC1 names. A3 and A1 both fall out of pointing the collector
at PR #298 — a thirty-second act nobody's role made them responsible for. Reviewer explicitly
does not re-run tests (correctly). Nobody's contract says "run the thing on something other
than the fixture." For a tool whose entire output is a claim about real PRs, that is a hole in
the role set, not in anyone's execution. **Recommendation: add to the Reviewer contract, for
work items that ship an executable, a single required step — run it once on input that is not
the worked example, and report the output.** Cost: one command. It would have caught two of
my four findings.

## B4 — Model choice was well-calibrated, with one stage arguably over-powered and one under

Recorded chain: Discovery `claude-opus-5`/medium, Planning `claude-opus-5`/high, Test
`claude-opus-5`/high, Implementation `claude-sonnet-5`/high, Review `claude-opus-5`/high (both
rounds). `model-record-gate.sh` is clean and the review floor was met cleanly for the first
time in this pilot — no same-model exception needed, which is itself a milestone worth naming.

Judged against what each stage actually produced:

- **Discovery at medium: correctly calibrated, and the reasoning was recorded properly.**
  Product argued explicitly that a validation pass over an already-reviewed spec is a
  different task from deriving requirements, so the floor is per-task not per-stage. It then
  found three real gaps. Medium was right, and the *argument* for it is the reusable part.
- **Planning and Test at Opus/high: earned, unambiguously.** Architect's §3 interface contract
  is what made a Sonnet implementation viable at all, and QA's nine findings — particularly
  (c) — were the difference between a suite that proves something and a suite that passes.
  Neither would have come out of a cheaper stage.
- **Implementation at Sonnet/high: correct, and the evidence is positive.** Sonnet built 1,276
  lines against a detailed contract and its two deviations were both *correct judgments*
  (exit 2 over `${1:?}`'s exit 1; flagging the prose/code conflict rather than silently
  picking). Neither round-1 nor round-2 findings were "Sonnet misunderstood the contract."
  This is the datapoint epic #65 needed: with an Opus-authored contract, Implementation does
  not need Opus.
- **The one place the split shows strain.** My A3 finding — an untested branch that is the
  primary real-world path — is the kind of gap that comes from a contract-driven
  implementation faithfully covering the contract and the contract covering the specified
  worked example. Sonnet built exactly what was asked. Opus (as QA) specified nineteen arms
  and not the twentieth. That is a *Test-stage* miss at Opus/high, not an Implementation miss
  at Sonnet/high, which is a useful thing to know: raising the Implementation model would not
  have caught it. **The lever is a QA contract item ("enumerate the inputs the system will
  actually see in production, not only the inputs the ACs name"), not a bigger model.**
- **Review at Opus/high, twice: right for round 1, arguably over-powered for round 2.** Round
  2 reviewed a 60-line fixup and produced a 100-line mutation-tested report. Valuable, but if
  cost ever becomes a constraint, "a re-review of a findings-only fixup may drop one effort
  level, provided the diff touches no new behaviour" is the first knob to turn — and I would
  turn it only after the pilot stops being a pilot.

## B5 — What the design documents should change, on this run's evidence

Concrete, evidence-backed, in priority order. Each names the observation that produced it.

1. **`ROLE-DESCRIPTIONS.md` § Product — add the carrying rule.** "A Product phase whose output
   is a filed issue must inline anything load-bearing that currently lives in a `wip/` report,
   an untranslated source, or a conversation. Referencing is not carrying." Plus its
   companion: "when an AC constrains a vocabulary, enumerate it closedly." *Evidence:* all
   three of Product's own findings, and AC8's existence at all.
2. **`ROLE-DESCRIPTIONS.md` § Product — a degenerate pass is a completed step.** State that a
   validation pass may legitimately terminate with zero `grilling` rounds when the frontier
   starts empty, and state whether Product applies small mechanically-forced edits directly or
   proposes them. *Evidence:* Product raised both as undefined and had to choose unilaterally.
3. **`ROLE-DESCRIPTIONS.md` § Reviewer — add the live-run step for executable deliverables.**
   One run on non-worked-example input. *Evidence:* B3; two of my four findings.
4. **`ROLE-DESCRIPTIONS.md` § QA — production inputs, not only AC inputs.** *Evidence:* A3.
5. **`PRD-MULTI-AGENT-WIP.md` / `ARCHITECTURE-MULTI-AGENT-WIP.md` — write down the Orchestrator
   finding-disposition policy from B2.** The role set currently has no Orchestrator *contract*
   at all, only responsibilities scattered through §6; the one activity that went wrong twice
   in this run is the one with no written rule.
6. **`ROLE-DESCRIPTIONS.md` § Reviewer — findings must name their verification command.**
   *Evidence:* F1 did, which is the only reason round 2 could re-check it cheaply.
7. **Record on #295, before W4:** the self-ingestion severity correction from A1, and Product's
   §4 observation that a real OQ9 comment needs a human sentence alongside the collector's
   table. Both are epic-level and both are currently recorded only inside prose that
   undersells them.

## B6 — Is this run sufficient evidence for #294 / OQ11?

**Partly — and the honest answer is no, not on its own.** It should be recorded as a genuine
pass, and then one more work item should run before the sufficiency judgment is made.

What it *does* establish, and these are not small:

- Five roles ran sequentially on a real work item with artifact-mediated handoffs, and the
  chain is evidenced rather than self-certified — I re-verified the marker chain independently.
- Each role found things the previous one missed, at a rate that justifies its cost. That is
  the falsifiable claim epic #65 rests on, and this run supports it.
- The Opus-plan / Sonnet-build split is validated with positive evidence.
- The review floor was met without a same-model exception for the first time.
- It produced a real, working, tested artifact that CI is green on.

What it *cannot* establish, and this is the part that matters for a good-faith judgment:

- **The work item is meta.** It is a script about the workflow, specified by the workflow,
  reviewed by the workflow, and its worked example is the workflow's own prior PR. Every role
  was operating on its home turf, with maximal shared context and no domain the pipeline had
  to learn. A pipeline that works on a bash script about its own compliance markers has not
  been shown to work on anything else.
- **No role disagreement occurred.** Decision 4 / A7 is the mechanism epic #65 is least sure
  about, and every role in this run either agreed with or cleanly extended its predecessor.
  Zero escalations to Ties from any role. The escalation path is still untested at full-
  pipeline scale — it was the co-thinking pilot's single biggest finding, and this run
  produced no new evidence about it at all.
- **The one process defect that did occur was in the one activity with no written contract**
  (B2), which means this run tested the role set more than it tested the orchestration.
- **The cost side is barely sampled.** One work item, one size (M), one shape (a standalone
  script with no integration surface). Nothing about how the pipeline behaves on something
  that touches existing code, or that has a genuinely contested design.

**Recommendation for #294/OQ11:** record this run as a pass with the qualifications above,
explicitly including "meta-item, no role disagreement, orchestration untested". Then run one
more work item that is (a) non-meta, (b) touching existing behaviour rather than adding a
standalone file, and ideally (c) one where Product and Architect are likely to genuinely
disagree — and make the OQ11 sufficiency judgment on the pair. Judging sufficiency on this run
alone would be judging the workflow on the single easiest case it will ever face, which is
precisely the shape of conclusion the OQ exists to prevent.

---

# Recommendation on PR #298

**Merge, after folding in one small commit.** The increment is sound and the pipeline that
produced it worked. Three cheap things belong in that commit:

1. **A3's one-character rendering fix** (`summary="${summary# }"`) plus a mixed-model gate-1
   fixture. Fifteen lines, and it covers the path every future pipeline PR will take.
2. **A1 recorded honestly** — a Technical-debt row in `PRD.md` and a note on #295 stating that
   the collector can evidence a gate from its own quoted output, superseding round 1's
   "damage is limited" characterisation. No code change.
3. Optionally **A2's two guards and two assertions**, if it does not stretch the commit; an
   issue otherwise.

A4 is follow-up debt with a two-line comment as a stopgap. Nothing here warrants blocking, and
nothing here should be merged silently either — A1 in particular must not go into `main` with
the wrong severity as its only written record.
