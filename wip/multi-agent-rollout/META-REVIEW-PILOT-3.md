**Model:** claude-opus-5-5 (Opus 5.5), effort: high — independent meta-review

# Meta-review — epic #295, pilot #3: #237/PR #312, W2 #313/PR #314, W3 #315/PR #316

Independent and blameless. I did none of the implementation or review work assessed here and
read the trail cold. What I read in full: `META-REVIEW-PILOT-RUN.md` and `META-REVIEW-PILOT-2.md`
(first, for format and for their recommendations); issues #237, #313, #315, #294, #317, #318,
#295, #65, #307, #309 with all comments; PRs #312, #314, #316 with bodies, every comment, every
review and the commit list; `DISPUTES.md`; `role-contracts/SKILL.md`; `role-label-staleness.sh`
and `test/cases/s152_role_label_staleness.sh`; `ARCHITECTURE-MULTI-AGENT-WIP.md` (Decisions 1-5,
A1-A11); `skills/model-choice/SKILL.md`; `skills/pre-merge-review/SKILL.md`.

Everything below stated as fact was **run or re-derived**, at `b5c37b7`, from inside a Claude
Code cloud session like the one the pipeline ran in:

- `./role-label-staleness.sh` live against #313, #315, #237, #294, #296, #302, #295, #318, #1, #65;
  again with `mawk` as `awk`; again through a pass-through `gh` wrapper that fails only the
  timeline call.
- `bash test/cases/s152_role_label_staleness.sh` under gawk (passes) and mawk (fails); the full
  `./check`; s150/s151 under mawk.
- Four mutation probes of my own against s152, in a throwaway worktree.
- `./compliance-evidence.sh 316` and `298`, `model-record-gate.sh 316`,
  `finding-carryforward-gate.sh 316`, `issue-structure-gate.sh 316`, all live.
- A REST audit of every `role:<name>` labeled/unlabeled event on the six items, every
  `model-record` marker on all three items by source, every PR's merge time vs. last review, and a
  scan of all 142 PRs in the repo for title-only closing references.
- Greps for the provenance of `DISPUTES.md`'s resolution rule, for `pre-merge-review:done` and
  `finding:` markers on the three PRs, and for where the two prior meta-reviews' role-contract
  recommendations are tracked.

**Headline.** The judgment layer of the pipeline worked better than in either earlier pilot.
Three Reviewer passes found seven real blocking defects across three items, all verified live and
by mutation rather than by reading. No round was a rubber stamp. The **mechanical and evidentiary
layer did not work**, and nothing in the trail says so:

- The `role:<name>` labels that Decision 3/A5 make the identity record were never applied once.
- None of the three PRs carries the `pre-merge-review:done` marker or a single `finding:` slug.
- This repo's guardrails (hooks, merge guard, `.claude/skills`) are not installed in the session
  the pipeline ran in.
- Every `gh`-GraphQL evidence gate either exits 4 or silently skips with exit 0 in that session.
- The W3 detector shipped as "done" prints a confident wrong verdict (exit 0) on a stock
  Debian/Ubuntu `awk`.

The code the pipeline reviewed is mostly sound. The evidence the epic's own claims rest on is
mostly absent.

---

# Part A — the deliverables

## P3-1 — `role-label-staleness.sh` silently reports `not-started` under mawk, and PR #316's "passes under both mawk and gawk" is not reproducible (High)

- **Summary.** `live_text()`, copied verbatim from `compliance-evidence.sh`, uses the interval
  regex `^ {0,3}(`{3,}|~{3,})`. mawk 1.3.4 panics on it (`REcompile() - panic`). awk then emits
  nothing, so every body collapses to empty text, and the script reports that no markers exist
  anywhere. It exits 0, and the only sign of trouble is the panic on stderr.
- **Failure scenario, reproduced live.** With mawk first on `PATH`:

  ```
  role-label-staleness: issue #313 — not-started (no role:<name> label and no model-record marker found on issue #313 or any linked PR)
  role-label-staleness: issue #315 — not-started (no role:<name> label and no model-record marker found on issue #315 or any linked PR)
  ```

  Under gawk the same runs correctly print `stale … stage=Review … expected role:reviewer`. The
  mawk output is the exact "confident claim of absence" this whole epic has spent four work items
  removing from W1. Here it comes from the interpreter rather than the network. The test suite
  fails the same way: `s152` under mawk gives exit 1 with 15 `FAIL` lines. s150 (26) and s151 (12)
  fail under mawk too.
- **The claim in the record.** PR #316's description says s152 is "verified under both `mawk`
  (default) and `gawk`." That does not reproduce. `/etc/alternatives/awk -> /usr/bin/gawk` is
  timestamped **2026-09-27 23:47**, inside this session and just before W3's first commit
  (23:59). Plain `awk` has been gawk since then, so a "default awk" run after 23:47 was a gawk run.
  I can't attribute the switch to a role, and I don't need to. The verification claim is false as
  stated, and the environment was changed under the suite without a record.
- **Tracked?** No. PR #312's round-1 Reviewer diagnosed the mawk panic exactly and listed it as a
  follow-up "raised separately". Round 2 said "A follow-up task for the mawk portability bug has
  been suggested separately." No issue exists (I checked every issue from #299 to #318), so the
  suggestion never became a durable artifact. W3 then copied the defect into a second script.
- **Location.** `role-label-staleness.sh:286` (same regex at `compliance-evidence.sh:142`);
  PR #316 description, "Deviations"/"Test run".
- **Category.** correctness (portability, silent) / evidence accuracy.
- **Verdict.** `CONFIRMED`.
- **Disposition.** New issue, before W4 and before anyone runs either collector on a
  Debian/Ubuntu box outside CI. Either make the regex mawk-safe (`^ ? ? ?` in place of `{0,3}`,
  and a literal-prefix match in place of `{3,}`), or self-test awk at startup and **exit non-zero**
  on failure. Silently degrading to "no evidence" is the one outcome that must not happen.

## P3-2 — #318 is confirmed now, and its blast radius is wider than filed: every GraphQL-backed gate either exits 4 or fails open in-session (High)

- **AC1, confirmed live.** `./compliance-evidence.sh 316` exits 4 with "could not read PR #316 via
  'gh pr view'". It does the same for `298`, a **main-targeting** PR, so this is not only a
  release-branch problem. The W1 collector cannot produce a table from inside the session the
  pipeline runs in.
- **Worse, several gates fail open.** `model-record-gate.sh 316`,
  `finding-carryforward-gate.sh 316` and `issue-structure-gate.sh 316` each print "couldn't
  consult … skipping the check" and **exit 0**. Whoever ran them in this session would see a pass.
- **Not in #318's scope, same exposure** (`gh pr view`/`gh issue view`/`gh pr checks` in
  non-test code): `finding-carryforward-gate.sh`, `issue-structure-gate.sh`, `wait-for-ci.sh`,
  `epic-auto-close.sh`, `templates/check-pr-issue-link.sh`.
- **#318's title names "unread-PR-reviews defects", but its body and ACs never mention them.**
  `gh pr view --json comments` does not include review bodies. This pipeline posts every Review
  marker as a PR review. So even where GraphQL works, W1's gate 2 would report the Review-stage
  marker missing on #312/#314/#316.
- **"Unconfirmed" was already stale when written.** PR #316's round-1 review ran
  `gh pr view 314 --json body` and got HTTP 403. That is the transport of `compliance-evidence.sh`'s
  Call A. #295's body, #318, and the OQ11 recommendation all still call the exposure "likely" or
  "unconfirmed". Confirming it took me one command.
- **Verdict.** `CONFIRMED` (AC1, and the fail-open behaviour). AC2's release-branch half is
  corroborated by construction: CI's `check-pr-issue-link.sh` link 3 fails on all three PRs for
  exactly the empty-`closingIssuesReferences` reason.
- **Disposition.** Widen #318 to every script in the list above, add a reviews AC, and make
  "skipping the check, exit 0" an exit-non-zero outcome for any gate. **W4 must not rely on
  `compliance-evidence.sh` until this closes.**

## P3-3 — s152 is strong but leaves the epic's signature defect class unpinned (Medium)

My own mutation probes against `b5c37b7`:

| Mutation | Result |
|---|---|
| M2: disable the AC1 "label behind evidence → stale" branch | killed (7 FAIL lines) |
| **M3: "no label + no marker + a lookup failed" no longer degrades, so it prints a confident `not-started`** | **survived** |
| **M1: PR *review* bodies bypass `live_text()`** | **survived** |
| M4: drop the `\b` after `#<issue>` (so issue #31 would match "Closes #313") | survived |

- **M3.** This is the degrade Architect specified in both the original and the redesign ("any
  verdict that would otherwise be `not-started` … must degrade"). It is also the class #299 and
  both prior meta-reviews centred on: absence asserted from an incomplete corpus. No arm tests it.
  Every lookup-failure arm has a label present. The shipped code is correct: through a wrapper
  that fails only the timeline call, `./role-label-staleness.sh 318` prints `indeterminate`. But a
  regression would ship green.
- **M1 is the path live data actually exercises.** The review bodies on #312 and #316 quote
  `model-record` markers in code spans. One of them is the malformed `stage=Review-->` from
  #316's F-5, which would force `indeterminate` for #315 if it were read as live. The live verdict
  on #315 is correct, so the stripping works today. It is untested on exactly the source most
  likely to contain quotations. This is the "g1 PR-side sub-arm" gap that Reviewer twice asked to
  have tracked, and that #317 then dropped (P3-4).
- **Verdict.** `CONFIRMED` for all three survivals.
- **Disposition.** Add these to #317: one no-label/no-marker/timeline-failure arm, one quoted
  marker in a *review* body, one `#31`-vs-`#313` arm. Fifteen lines.

## P3-4 — #317 records the deferred findings inaccurately (Low-Medium)

- The title says "4 non-blocking findings", but the body lists six.
- The **g1 span/blockquote/PR-side sub-arms** are missing, although round 2 said "Please track
  them in a follow-up issue rather than drop them" and round 3 repeated it.
- **F-9 is downgraded.** Reviewer's text: "`CONFIRMED` (observed live) … #316 is *also* kept for
  #313 … Category: Correctness." #317's text: "superficially looks like it could be misparsed …
  worth cleaning up for clarity, not correctness." That is an orchestrator paraphrase that changed
  a finding's category. It is the Decision 4 "interpretation layer" problem, relocated to an issue
  body.
- **F-10 is mis-specified.** Reviewer's case is a *kept PR's* comments call failing. #317 says
  "the issue-comments fetch fails". Its AC6 asks the arm to assert the result "correctly degrades
  to `indeterminate`". Reviewer's actual suggestion was to assert "`stale … expected
  role:reviewer` instead of `indeterminate`". An arm asserting `indeterminate` would **not** kill
  mutation ME: skipping the reviews call also yields `indeterminate` there. As written, AC6 would
  close without closing the gap.
- **Verdict.** `CONFIRMED`, checked against the review text.

## P3-5 — The script's own account of GitHub's closing-keyword semantics contradicts itself (Low)

- Header lines 95-105 still say the keyword lives "in a PR's body" and call the approach "not a
  heuristic approximation, the actual same mechanism".
- Lines 129-131 and 362-369 say "GitHub's own auto-close mechanism accepts the keyword in either
  field [title or body]".
- Round 2's Reviewer wrote that main-targeting PRs put it in the body because "GitHub needs it
  there".

These cannot all be true. My understanding is that GitHub documents the PR description and commit
messages, not the title. A squash-merge commit subject is the title, which may be why title
matching works in practice. I could not check the docs from here (docs.github.com is
egress-blocked), so: `PLAUSIBLE`.

A related gap is untested: step 1 finds candidates only through timeline `cross-referenced`
events. A PR with "Closes #N" in its title and **no** mention of #N anywhere in its body may never
appear as a candidate. No such PR exists yet (I scanned all 142), so this is `PLAUSIBLE` too.
Either way the header should state the title match as a deliberate, repo-convention-driven
broadening, not "parity with GitHub".

## P3-6 — W2's skill satisfies A4/A8/the security list on its own terms, and carries none of what two pilots learned (Medium)

My independent read of `role-contracts/SKILL.md`:

- **A4.** Met in letter: a named write/action scope for all five roles, the read-vs-write
  qualifier, and the stage-report allowance stated once. It is weak where A4 matters most.
  Fullstack Developer's scope ("application code, test code, and docs within Architect's
  decomposition") is in practice the whole repo. Practice diverged on the very next item: W3's
  Developer wrote `PRD.md` F35 (`7ee6e43`, `8d370e9`) and the `TEST-SCENARIOS.md` S152 entry,
  which the new contract assigns to Product and QA. Either the contract or the practice is wrong,
  and nobody noticed that they disagree.
- **A8.** Stated in full once, with five pointers. It governs *dispatch prompts*, which are not
  durable artifacts (P3-13), so compliance cannot be checked from the trail.
- **Security triggers.** The table is byte-identical to PRD §4 (`diff` empty), and the
  invocation sentence is imperative. Correct. Its first plausible application went unmentioned:
  W3 processes GitHub body text, which is the "untrusted input" category. No review on #316 says
  whether a trigger applied.
- **What it is missing.** None of the role-contract recommendations from pilot #1 (B5.1 carrying
  rule, B5.3 Reviewer live-run step, B5.4 QA production inputs, B5.6 findings name their
  verification command) or pilot #2 (B6.1 falsifiability split, B6.3 sampling rule, B6.4 promote
  AC10) is in the file. None is tracked anywhere else either: #307, the v2 holding-pen epic, lists
  none of them. #313's AC8 ("no new mechanism") and AC6 (meta-reviews are "retrospective, leave
  untouched") scoped them out without anyone deciding to.
- **It codifies the opposite of the evidence.** Reviewer "does not re-run tests itself … reviews
  evidence rather than re-executing it." Yet every high-value Reviewer act in this pilot was a live
  run or a mutation probe: #316's GraphQL 403s, the title-only miss on #313, M1-M4 and MA-MF. W4
  will dispatch against a contract that tells Reviewer not to do what caught every serious defect.
  No Orchestrator contract exists, although both prior meta-reviews named it the top gap.
- **Two residuals from #314's own review are untracked:** F5 (SKILL.md:22's ambiguous "That source
  document") and PRD:230's stale "(still to be written…)". Both are still present at `b5c37b7`.

## Things I checked and found genuinely sound

- **#237's translation.** The line-joined Dutch grep across `wip/multi-agent-development/*.md`
  returns nothing, and `./check-no-dutch.sh .` is clean. The round-2 claim holds.
- **#314's F1 fix is present.** The "deliverable structure" clause is back at SKILL.md:46-49.
- **W3's REST redesign works in-session.** Live, it resolves #313 via #314's title and #315 via
  #316, reads Review markers from PR reviews, and is correct on #296, #302 and #237.
- **Pagination works on the script's query-string-free endpoints.** #65's 77-event timeline was
  read in full. One trap for later: `gh api --paginate` on an endpoint **with** a query string
  (e.g. `?per_page=100`) fails through this proxy with "Numeric-ID repository paths … not
  supported", because GitHub's `Link` header points at `repositories/<id>/…`. Nobody should "just
  add `per_page=100`".
- **The degrade logic is correct live.** A failed timeline on #318 gives `indeterminate` with a
  clear reason.
- **#308's quoted-marker fix works in the wild.** Review bodies quoting live-shaped and malformed
  markers do not perturb verdicts.
- **The decision table re-derives as Reviewer said.** AC1-AC6 and `valid_status()` are in place,
  and `s152` passes under gawk.

---

# Part B — the process

## B1 — Lanes: mostly held, with three genuine crossings

- **Product** framed requirements well. #313 and #315 were each filed by Product with full ACs,
  and #237's Discovery found real gaps (a missing file, the `check-no-dutch.sh` miscategorization).
- **QA** on #313 re-derived Product's AC6 file list independently rather than trusting it. That
  is the right instinct.
- **Developers** reported deviations honestly: the fourth self-reference on #237, and the
  dispatch-prompt-vs-issue name conflict on #316.

The crossings:

1. **Reviewer designed the W3 redesign (P3-10 below).**
2. **QA was skipped on #315's loop-back.** Architect's redesign (00:16:57) went straight to the
   Developer's commits (00:31:57). The redesign added three failure flags, a keyword filter,
   pagination, and later a reviews call. Its tests were designed by the Developer alone. A3
   requires all five roles "on the standard path or a loop-back", with any narrowing authorized
   by Ties and logged. Neither happened. This is the one genuine A3 narrowing in the pilot, and
   it was unannounced. It has a cost: the round-2 blocker (keyword only in the PR title) is a
   production-input check, which is QA's lane per pilot #1's B5.4. #314 was already merged and
   would have shown it.
3. **The Developer wrote Product's and QA's artifacts** (F35/S152, P3-6).

A smaller oddity, `PLAUSIBLE` only: #237's Architect report says "Correction to my own (Product's)
Discovery framing". A fresh Architect sub-agent should not call Product's report "my own". It
may be a slip, or context carried over between dispatches; the artifacts can't tell.

## B2 — Escalation, disputes, A7

- **DISPUTES.md's "zero genuine disputes" is accurate.** I found no role contesting another
  role's stated position. Architect corrected Product's AC2 scope draft on #313 and nobody
  objected. Architect accepted Reviewer's #316 finding "in full". The one divergence, #312's
  Reviewer making merge conditional on Ties' explicit acceptance of red link-3 while the
  Orchestrator merged on #309's standing decision, was not role-to-role. It was backed by Ties'
  own 2026-09-27 comment on #309.
- **P3-11 (Medium): the log's own resolution rule contradicts the architecture.** DISPUTES.md
  says: "Per this epic's own dispute-resolution rule … if that doesn't converge, Reviewer decides
  as a third party." I found that rule nowhere else: not in any `.md` in the repo, and not in
  #295, #294, #65, #307 or #309. Decision 2 says every escalation routes to Ties. Decision 4 says
  a two-role conflict goes to Ties "verbatim, side by side". #307 says the escalation path should
  be *deliberately exercised*. So the procedure for the one mechanism never tested in three pilots
  entered the record by direct commit, with no review, from a source that is not an artifact, and
  it says the opposite of the decided design. Reconcile it before the first real dispute uses it.
- **#315's loop-back to Architect was the right call.** A design defect went to the design role,
  not to a Developer patch. Decision 4 does not apply, since nobody disagreed. A9 is partly
  implicated upstream. Architect's original plan rested on "the one thing Dev must confirm
  empirically". QA passed the same unchecked fact on ("confirm with Dev"). The Developer's check
  tested CLI field support, not what the connection returns for a release-branch PR, and was
  reported as confirmation. Round-1 Reviewer said so: "That check should have been reported as
  inconclusive." That is A9's violation shape (a gap found only downstream after being built on),
  and A10's: a fact cheaper to look up than to caveat. One REST or MCP read of #313 would have
  shown zero closing PRs.
- **Loop-back routing was inconsistent.** Round 1's design defects went back to Architect.
  Round 2's were Architect's plan too (body-only filter, no reviews endpoint). The Developer fixed
  them directly from Reviewer's suggested fix. There is no written rule for when a Reviewer finding
  loops to Architect versus the Developer. Write one.
- **A7 and faithful relay.** The role reports quote their predecessors well. The defects are in
  relays by the Orchestrator and by Product:
  - #317's F-9/F-10 rewrites (P3-4).
  - #315's closing comment and #318 attribute the cross-script GraphQL risk to Architect. Round-1
    Reviewer raised it first, with a reproduction.
  - The OQ11 recommendation says "Quoting the 2026-09-27 note precisely, not paraphrased" and then
    silently drops "already" from "beyond what's already in flight".

  All small, all in the same direction: relays drift. Pilot #1's observation stands. The upstream
  artifact is safe when a downstream role *edits* it and unsafe when someone *summarizes* it.

## B3 — Round-trip cost

| | Pilot #1 (#296) | Pilot #2 (#299) | #237/PR #312 | W2 #313/PR #314 | W3 #315/PR #316 |
|---|---|---|---|---|---|
| Review rounds | 3 | 2 | 2 | 2 | **3** |
| Blocking findings, round 1 | 5 | 3 | 2 | 1 | 2 (+1a context) |
| Blocking findings, later rounds | — | — | 0 | 0 | 1 (+ F-6 should-fix) |
| Fix commits after review | 2 | 1 | 1 | 1 | 5 (2 fix rounds) |
| Loop-backs to an upstream role | 0 | 1 (Product↔Architect) | 0 | 0 | 1 (to Architect) |
| Wall clock, first role pass → merge | ~10.5h | ~2h | **59 min** | **40 min** | **1h41m** |
| Final approval → merge | — | — | 2m17s | 21s | 37s |

All three items took 3h33m from #237's Discovery (21:30) to #316's merge (01:04), and the OQ11
recommendation followed at 01:09. Two of three items hit the two-round floor that the sha-pinned
review implies. The third round on W3 was genuine: a real defect in the redesign. Per item, this
is the cheapest the pipeline has been.

Two cautions. First, the speed came partly from things not done: no labels, no pre-merge-review
markers or gates, no QA on the loop-back. Second, sub-minute approval-to-merge means nothing was
checked between the verdict and the merge. On #314 that includes Reviewer's own line "Merging
stays with Ties (A2/A11)". The merge came 21 seconds later, by the session.

## B4 — A3: not invoked, but not literally "full five roles" either

No A3 authorization appears on any of the three issues, and #237 and #313 ran all five roles in
order. #315 did not on its loop-back (B1, crossing 2). #237's and #313's QA wrote no test code,
and #237 got no `TEST-SCENARIOS.md` entry. Both were explicitly and correctly justified as
docs-only items, so that is full engagement, not narrowing.

The larger A3 issue is P3-8 below. A3 lists `pre-merge-review` as "absolute". Its mechanical form
did not run on any of the three PRs.

## B5 — Model choice

- **Markers.** Every stage of all three items has one, correctly formatted. Discovery, Planning
  and Test are on the issue; Implementation is in the PR body, plus #316's two reply comments;
  Review is in the PR reviews.
- **Review floor.** Review was `claude-opus-5-5` and Implementation `claude-sonnet-5` on every PR,
  so a genuinely different, more capable model, and no same-model exception was needed.
- **Unargued calibration (P3-15, Low).** Discovery, Planning and Test moved from Opus (both prior
  pilots) to Sonnet 5 at low/medium/high, and no report records why. Pilot #2 praised exactly
  that argument as the reusable part. I don't claim the shift caused #315's design miss. Both
  prior pilots concluded the lever there is contact with real inputs, not model size, and this
  pilot is consistent with that. But a floor decision with no recorded reasoning cannot be
  audited, and W3's Planning is the stage where the floor ("right risks surfaced") visibly wasn't
  met.
- **Missing self-declaration.** None of the three Implementation PR bodies opens with the
  one-line model self-declaration that `model-choice` requires of every written artifact.
- **Marker pollution.** #294 carries a "write-access probe — please ignore/delete" comment with a
  live `stage=Discovery` marker. W3 reads it: `#294 — stale … expected role:product`.

## B6 — Independence of review

- **Substance: genuinely independent and not a rubber stamp.** Each review re-derived claims with
  its own commands. #312 used a line-joined grep and found 6 stale quotes that QA's scenario could
  not see. #314 used `git diff -M` and found the one dropped clause. #316 made live 403
  reproductions, read the REST timeline, and ran mutation probes M1-M4 and MA-MF. All seven
  blocking findings are real. I re-checked the fixes for #312 and #314, and #316's reproduce live.
- **Isolation cannot be verified from artifacts.** Dispatch prompts are not recorded. One phrase
  in #316's round 2, "this Claude Code session (the one that 403'd in round 1)", is ambiguous
  between the same environment and the same agent. Everything else round 2 and 3 knew about
  earlier rounds is on the PR.
- **P3-10 (Medium): on W3 the Reviewer reviewed its own design, twice.** Round 1's "A REST
  alternative exists" section lists five endpoints and a body-only keyword filter. Architect's
  redesign call plan is those same five calls in the same order, and that plan contains both
  defects round 2 then caught (body-only filter, no `/reviews` call). Round 2's "Suggested fix"
  (title+body, a tightened ERE, a `/reviews` call) was implemented as written and approved by
  round 3. Credit where due: the Reviewer caught its own omissions. But the loop-back produced no
  second independent design mind. That is what "Architect's call" in round 1 was supposed to
  guarantee, and it is exactly the correlated-blind-spot risk `model-choice` names for same-model
  review. Rule suggestion: a Reviewer may *name* a defect and a falsifying check, but when a
  finding loops to Architect, Architect derives the design and records any alternative it
  considered beyond Reviewer's sketch.

## P3-7 — A5 was never exercised: no `role:<name>` label was applied at any point (High, process)

The REST timelines of #237, #313, #315, #312, #314 and #316 contain **zero** `labeled`/`unlabeled`
events, and no issue in the repo carries any of the five labels. Decision 3 names the label as
the identity record, and A5 says "Violated if the label is left stale after a phase transition".
It was stale for every transition of every item. The detector W3 built for this reports `stale`
on all three items that built it.

No report, review, closing comment, DISPUTES.md or the OQ11 recommendation mentions this.
#316's round-3 review saw it ("none of these issues carries a role label today") and treated it
as a fact about the test data, not about the pipeline. Either apply the labels on W4, or amend A5
and Decision 3. Building a staleness detector for a mechanism the pipeline doesn't use is the
clearest single sign that the pipeline's own procedure isn't checked against itself.

## P3-8 — The `pre-merge-review` evidence layer and this repo's guardrails were absent on all three PRs (High, process)

- **No markers.** None of #312/#314/#316 has a `pre-merge-review:done sha=<head>` marker or any
  `finding:<slug> status=` marker (grep over every review, comment and body; the only
  `pre-merge-review:done` in the recent trail is on #311). No review mentions running
  `scenario-gate.sh`, `model-record-gate.sh` or `finding-carryforward-gate.sh`. Per P3-2, the
  last two would have silently skipped anyway.
- **No guardrails installed.** The session has no `.claude/` in the checkout, no installed git
  hooks (`.git/hooks` holds only samples and `core.hooksPath` is unset), and no
  `~/.claude/CLAUDE.md`. The pre-commit `./check` gate, pre-push gitleaks, commit-msg and the
  `git-guardrails` merge guard were all inactive. `pre-merge-review` was not an invocable skill;
  reviews followed a bespoke format.
- **Merged with CI red.** All three PRs merged with the link-3 CI step red and no marker. The
  merge guard would block both conditions, so the merges went through a path it does not cover.
  `gh pr merge` is itself GraphQL-backed and would 403 here.
- **Why it matters.** The reviews were substantively excellent, so this is about evidence, not
  quality. But W1's gate 3 reads exactly this marker. The repo's promise that "nothing disappears
  silently" rests on the `finding:` slugs. A3 lists `pre-merge-review` as absolute. The pilot ran
  on the one tier of the process that is mechanically checkable, in an environment where the
  mechanics weren't installed, and none of the three reports noticed. The session-start setup
  should install the guardrails, or the reports should state that they are absent.

## P3-12 — Deferred findings leaked again, though less than in pilot #2 (Medium)

**Improvement:** #316's deferrals became #317/#318 within 2 minutes of merge. That is the first
time a pilot's deferrals got issues promptly.

**Still leaked:**

- the mawk follow-up (P3-1), "suggested" but never filed;
- #314's F5 and its PRD:230 observation;
- the g1 sub-arms (P3-4).

The `check-pr-issue-link.sh` follow-up is covered by #309's comment. Pilot #2's P2-4 root cause
is unchanged: with no `finding:` slugs (P3-8), there is nothing mechanical to carry. A "follow-up
suggested" that exists only as an in-session task card is not an artifact under Decision 1.

## P3-13 — Dispatch prompts are orchestrator state outside artifacts (Low-Medium)

The only window into them is what roles happen to report. That window already shows one wrong
prompt: #316's Developer says the dispatch prompt named the script `check-role-label-staleness.sh`,
contradicting #315's AC9. The Developer followed the issue, correctly.

A8's floor/ceiling statement lives in those prompts. Only 2 of 16 role reports (#313's Planning
and Test) declare their scoped input at all. A1 says an instruction not written to an artifact
"hasn't happened yet". Post each dispatch prompt, or at least its scope line and floor/ceiling
choice, on the issue.

## P3-14 — Merge authority rests on an open, unscoped issue, not on the architecture (Low-Medium)

All three merges were executed by the session under #309's "standing authorization" for
release-branch PRs. Ties' 2026-09-27 comment on #309 does back that. A2 still reads
"unconditionally … no future auto-approve exception", and #309 itself says the rule "exists only
in one conversation". Two Reviewers (#312, #314) stated that merging was Ties' call. That is a
sign the role contracts and dispatches don't carry the exception. Record it in A2, or in the
release-branch skill #309 proposes.

---

# Part C — the OQ11 recommendation on #294

**Direction: honest. Specifics: several wrong, and the errors run in both directions.** Its
framing deserves credit. It calls itself a recommendation, not a decision. It names the sample as
thin, meta and structurally favorable. It separates the letter of the loosened gate from W4's
purpose. It keeps propagation open. Those are the right qualifications, and I would keep its
bottom line ("validated for continued internal/dogfood use; broader integration open").

Checked against the trail, though:

1. **Wrong round attribution.** "Round 3 found Review-stage markers … were never read at all."
   That was round 2's F-6. Round 3 approved, with only F-9 and F-10, both non-blocking. The
   Orchestrator's own #315 closing comment has this right.
2. **Wrong effort claim.** "Reviewer consistently run at higher effort — Opus 5.5 high". #312's
   and #314's reviews were Opus 5.5 at **medium**, all four of them. Only #316 was high.
3. **A misquote while claiming precision.** "Quoting the 2026-09-27 note precisely, not
   paraphrased" drops "already" from Ties' "beyond what's already in flight" without an ellipsis.
4. **Damage oversold.** "`compliance-evidence.sh`'s own automated compliance comments may have
   been wrong or incomplete for #296, #313, and #315." No such comments were ever posted for
   #313 or #315, and #296's PR (#298) targeted `main`. The real consequence is prospective:
   W4's comment cannot be produced at all.
5. **#318 undersold.** It calls #318 "open, unconfirmed" and declines to run it as out of scope.
   Round 1 had already reproduced the transport's 403. One command confirms it (P3-2), and the
   recommendation's own bottom line hinges on it. That is an A10 miss: a fact cheaper to check
   than to caveat.
6. **"Three full five-role runs."** #315's loop-back ran without QA (B1).
7. **Omissions that bear directly on "does the pipeline work":** A5 labels never used (P3-7), no
   pre-merge-review markers and no guardrails installed (P3-8), W3 silently wrong under mawk
   (P3-1), and the DISPUTES rule contradicting Decision 4 (P3-11).

None of these flips the recommendation's direction. Together they mean it should not be accepted
as the OQ11 record in its current wording. Items 1-3 are the pipeline describing itself
inaccurately in the one artifact whose purpose is to describe it accurately.

---

# Findings summary

| ID | Severity | Summary | Verdict |
|---|---|---|---|
| P3-1 | High | W3 prints `not-started` (exit 0) for #313/#315 under mawk; s152/s150/s151 fail under mawk; PR #316's "passes under both" claim not reproducible; env awk switched to gawk mid-session; mawk follow-up never filed | CONFIRMED |
| P3-2 | High | #318 AC1 confirmed: W1 exits 4 on every PR in-session (incl. main-targeting #298); three pre-merge-review gates fail open (exit 0); five more scripts share the exposure; reviews-blindness has no AC | CONFIRMED |
| P3-7 | High | No `role:<name>` label ever applied on any of the 3 items (A5/Decision 3 unexercised); unmentioned anywhere | CONFIRMED |
| P3-8 | High | No `pre-merge-review:done`/`finding:` markers on any PR; repo guardrails not installed in the session; merges with red CI outside the merge guard | CONFIRMED |
| P3-3 | Medium | s152 does not pin no-label/no-marker/lookup-failure degrade (M3), live_text on reviews (M1), or `#N` word boundary (M4); code correct live today | CONFIRMED |
| P3-6 | Medium | W2 meets A4/A8/security letter but carries no pilot-#1/#2 contract lessons (tracked nowhere); codifies "Reviewer does not re-run"; no Orchestrator contract; A4 already diverged in W3; two #314 residuals untracked | CONFIRMED |
| P3-9 (B1.2) | Medium | QA skipped on #315's loop-back; A3 narrowing without authorization or record; round-2 blocker was QA-shaped | CONFIRMED |
| P3-10 | Medium | Reviewer authored the W3 redesign and its round-2 fix, then reviewed both | CONFIRMED |
| P3-11 | Medium | DISPUTES.md's "Reviewer decides" rule has no source and contradicts Decisions 2/4 | CONFIRMED |
| P3-12 | Medium | Deferred findings leaked (mawk, #314 F5, PRD:230, g1 sub-arms) | CONFIRMED |
| OQ11 | Medium | Recommendation directionally honest; 3 factual errors, 1 overstated and 1 understated risk, material omissions | CONFIRMED |
| P3-4 | Low-Med | #317 miscounts, drops g1, downgrades F-9, mis-specifies F-10/AC6 so it would not kill mutation ME | CONFIRMED |
| P3-13 | Low-Med | Dispatch prompts not durable; one known wrong; A8 unverifiable (2/16 reports declare scope) | CONFIRMED |
| P3-14 | Low-Med | Merge authority via open #309, not reconciled with A2's text; Reviewers believed otherwise | CONFIRMED |
| P3-5 | Low | Script header self-contradicts on GitHub keyword semantics; title-only-without-body-mention discovery untested | PLAUSIBLE |
| P3-15 | Low | D/P/T downgraded to Sonnet with no recorded argument; no self-declaration in PR bodies; probe comment on #294 carries a live marker | CONFIRMED |

# Recommendations, in priority order

1. **Before W4 starts:**
   - fix #318, widened per P3-2, and make "skip, exit 0" a non-zero outcome for every gate;
   - fix P3-1, and make a failing awk self-test fatal;
   - install this repo's guardrails in the session the pipeline runs in, or have the Orchestrator
     state loudly at session start that they are absent.
2. **Run W4 with the procedure the architecture actually specifies.** Apply `role:<name>` labels,
   and treat W3's own output as a gate on the Orchestrator's bookkeeping. Post the
   `pre-merge-review:done` marker and `finding:` slugs. Post dispatch prompts, or at least their
   scope/floor-ceiling lines. Route every loop-back through the roles after the one it returns to,
   QA included.
3. **Reconcile DISPUTES.md's resolution rule with Decisions 2/4** before the first real dispute,
   and add the escalation-exercise item from #307.
4. **Open one issue carrying both prior meta-reviews' role-contract recommendations into
   `role-contracts/SKILL.md`**, and replace "Reviewer does not re-run tests" with the live-run
   step (pilot #2 B6.4). Add an Orchestrator section covering dispatch recording, relay-by-quoting
   and finding disposition. Decide whether the Developer or QA/Product owns F-/S- entries.
5. **Correct #317** (count, g1, F-9's category, F-10's case and assertion), **add P3-3's three
   arms**, and file the mawk, #314 F5 and PRD:230 residuals.
6. **Write a loop-back routing rule.** Design defects go to Architect and then QA, whichever round
   they surface in. Reviewer names the defect and the falsifying check, not the design.
7. **Correct the OQ11 recommendation's items 1-5** before Ties uses it as the record.

# Overall assessment

**Is the process working as designed?** The review judgment is: better than ever, cheaper per
item, and reliably catching real defects with real evidence. The process *as designed* is not
being executed. A5 was never done, the pre-merge-review evidence form was never produced, QA was
dropped from a loop-back, and the dispute rule on file contradicts Decision 4. Nobody noticed any
of this, including the OQ11 recommendation.

**Are the deliverables solid?** Mostly:

- #237: clean.
- W2: faithful to its letter but already partly stale against what the pilots learned.
- W3: well built and correct under gawk in-session, but it silently lies under mawk, and its
  tests leave the epic's signature defect class unpinned.

**Does anything block declaring epic #295's current state trustworthy?** Yes, three things:

1. The evidence tooling this epic exists to create cannot run where the pipeline runs (P3-2).
2. One shipped detector gives confident wrong answers on a common platform (P3-1).
3. The pipeline's own compliance record (labels, review markers, finding slugs) is empty for all
   three items (P3-7/P3-8).

"W1-W3 done" is true of the code, subject to P3-1. It is not yet true of the claim that the
workflow is executable and evidenced, which is #295's stated goal.
