# Product role report — `agentic-workflow-installer` v1 (co-thinking session, epic #65)

Model/effort: Claude Opus (general-purpose agent, Product role).

Scope of this pass: the three docs in `wip/claude-code-plugin/` (`PRD.md`, `ARCHITECTURE.md`, `TEST-SCENARIOS.md`). Assessed whether the requirement is correct and complete, not whether the architecture is sound.

---

## 1. Requirement validation

**What is clear and holds up.** The problem statement in `PRD.md` "Context" is genuinely sharp on one point: `adopt.sh` exists, works, and fails a *specific* audience for *named* reasons (manual `SPEC_DRIVEN_GUARDRAILS_DIR` export, terse machine-oriented output, assumed existing git repo). That is a real, falsifiable gap, not a vague "make it easier". The v1 scoping decision — one plugin for one project, generic/specific split enforced internally, extraction deferred until a second consumer exists — is well-argued and correctly resists building an N-project core speculatively. `ARCHITECTURE.md`'s "Build order decided" and the Technical debt table are honest about what is unproven.

**Gap 1 — the user is described only by what they lack, never by what they want.** The whole audience definition is negative: "not software engineers", no git/terminal/env-var background. There is no statement of what this person is trying to *accomplish* after the install finishes. This matters because `spec-driven-guardrails` is a *software development* workflow — branch naming per issue, `gh issue create`, PRs, pre-merge review, TDD seams, a check/deploy convention. The PRD validates the gap in *getting it installed* while leaving entirely unstated the assumption that the installed thing is usable and valuable to someone with no engineering background. If that assumption is wrong, v1 delivers a beautifully narrated path to something the user then can't use. This is the single biggest unstated assumption in the document.

**Gap 2 — the one thing `adopt.sh` is criticised for has no requirement answering it.** Context says `adopt.sh` "assumes an existing git repository the user already understands". F1–F7 never address that. F3 collects a target directory; S3 validates only that the path *exists*. There is no functionality, and no scenario, for "the user points at a folder that is not a git repo" — init it? refuse with an explanation? walk them through creating a GitHub repo (which also implies `gh auth`, itself only mentioned in the NFR prose, never as an F or an S)? A named deficiency of the incumbent has no corresponding requirement in the replacement.

**Gap 3 — no success criterion for the product, only for its parts.** There is no statement of the form "a non-engineer starting from nothing reaches a working adopted project unaided". F1–F7 each have behaviours; the journey has none. Consequently there is nothing that fails if the parts all pass and the user still gets stuck — which `ARCHITECTURE.md`'s own "When we would revisit" list names as a live possibility ("real non-engineer users get stuck at a step the plain-language narration doesn't resolve").

**Gap 4 — "plain language" is load-bearing but not operationalised.** A2 and the Usability NFR make plain-language narration the project's central characteristic, and F1–F7 all restate it. Nothing makes it checkable. The only testable form anywhere is the negative in Failure modes ("a stack trace or raw exit code is never the last thing a non-engineer sees"). That negative should be promoted to an explicit acceptance criterion; the positive claim needs a named validation method (review by an actual non-engineer) or it will be asserted rather than met.

**Gap 5 — F3's own example question contradicts the premise.** F3 cites "is this a per-project adoption or the one-time, machine-wide setup" as a question to ask conversationally instead of requiring `--user`. Removing the flag removes the *syntax* problem, not the *concept* problem: a non-engineer cannot answer that question either way. Requirements should say how the plugin decides or recommends when the user cannot meaningfully choose — a good default with an explanation, not a question passed through.

**Gap 6 — `adopt.sh`'s future is undecided.** `ARCHITECTURE.md` A5 rules out wrapping `adopt.sh` and requires reimplementing the install logic cross-platform. That leaves two implementations of the same adoption behaviour in one repo, indefinitely, with no stated policy: is `adopt.sh` deprecated, frozen, or maintained in parallel? Which is the supported path for Ties' own machines? This is a product decision, currently absent.

**Gap 7 — install is specified; *update* is not.** This repo's own model (`CHANGES.md`, `WORKFLOW-ADOPTION.md`, the `adoption-registry` skill) assumes the workflow keeps evolving and adopting projects pull changes over time. F6's idempotent re-run is not the same as migrating an already-adopted project to a newer workflow version. For the target audience this is arguably the *more* frequent operation after month one. It isn't in scope, isn't in Known limitations, and isn't in Technical debt — it is simply absent.

**Gap 8 — no uninstall, and the omission isn't argued.** Deployability explicitly rules out rollback/undo for v1 (correctly distinguishing "declining a step" from "undoing one"). But uninstall is a different thing from rollback, the cited prior art (`agent-skill-installer`) is credited precisely for "clean uninstall ownership", and the audience most likely to want out is exactly the one who can't manually unpick symlinks and git hooks. Either in scope or in Known limitations with a documented manual removal path — not silent.

**Minor inconsistency.** F1 lists "a specific Claude Code version" as a detectable prerequisite, while A6 makes Claude Code a precondition guaranteed by the admission gate and forbids the core from taking responsibility for it. Detecting a version is fine; F2's promise to *resolve* every missing-or-outdated prerequisite cannot apply to the host the plugin is running inside. The F1/F2 wording needs to carve that out.

---

## 2. Acceptance criteria check

**Better than typical, and genuinely testable in structure.** `TEST-SCENARIOS.md` gives Given/When/Then for every F1–F7 with `Covers:` tokens, and — unusually good — it covers the negative and partial-failure paths, not just happy paths: S2b (user declines), S2c (unknown OS), S3b (user bails mid-intake, with the explicit "no progress-marker state for steps that never started"), S4b (step fails partway), S5b (primitive without an honest preview is refused), S6b (crash between side effect and status update), S7b (F4 lied, F7 catches it). S5b and S6b in particular encode real design commitments as observable behaviour. Every F has at least one scenario; no orphan functionality.

**What's missing as acceptance criteria:**

- **No end-to-end / journey scenario.** Nothing states the whole-run outcome from a cold start to a verified adoption. Every scenario tests a stage in isolation.
- **No scenario for the machine-wide (`--user`) path.** F3 names it as one of two modes; every execution scenario (S4, S4b, S5, S6, S7) assumes the per-project mode and a target directory. The second mode has zero coverage.
- **No scenario for a non-git target** (see Gap 2), and none for the `gh auth login` flow despite it being named in both the Security and Failure-modes NFRs.
- **No scenario for re-running against an already-adopted project** — distinct from resume (nothing was interrupted; the install is simply already done). The Data-integrity NFR asserts idempotence as an invariant, but the only scenario exercising it is the resume case.
- **Cross-platform is asserted, not tested.** A5 and the Portability NFR make macOS/Windows/Linux central. S2 is explicitly macOS; S2c covers *unsupported* OS. There is no acceptance criterion that Windows or Linux works. For the requirement carrying the largest cost in v1, that is the biggest coverage hole in the file.
- **"Same state `adopt.sh` would produce today" (S4) is under-specified** as a pass condition — it needs an enumerated criteria list, which is what F7 should own.
- **F7's "a smoke command exits zero" is a placeholder.** What proves an adoption actually *works* (a skill loads, a hook fires, the adoption table parses) is undefined, and it is the criterion that matters most to the user.
- **No acceptance criterion for the plain-language requirement** (Gap 4).

---

## 3. Proposed epic / work-item decomposition

Product-level grouping only; the Architect may regroup on dependency grounds. Ordered by when the value lands, not by build order.

**Recommended shape overall:** a walking skeleton first — one real adoption step carried end to end (detect → ask → preview → run → verify) on one OS — before broadening either the step set or the OS matrix. The decomposition below is written so that is possible.

---

**E1 — Bootstrap admission path (docs only)**
From "nothing installed" to "a Claude Code session with the plugin available": Claude Desktop install and sign-in per A6, marketplace add, plugin install, in A2's plain language. No code. It is a separate unit because it is the *only* part of the system that can be validated with a real non-engineer before any of the plugin exists, and because nothing else in v1 delivers any value at all until it exists — a plugin that the target audience cannot reach is worth zero to them. `PRD.md` currently files this as Technical debt and Out of scope; from a product standpoint it is the first shippable increment, not debt.
*Done:* a person matching the target profile follows it unaided, on their own machine, to the point where they can invoke the plugin — observed, not assumed. Failures feed back as fixes to the manual.

**E2 — Machine readiness check (F1, S1/S1b — detection only)**
Detect git, `gh`, and the host's own state; report present / missing / below-required-version in plain language; take no action. Separate because it is useful standalone ("is my machine ready?"), it is the natural first conversation turn, and — critically — it is where the cross-platform requirement (A5) first bites, so it is the cheapest place to discover what Windows and Linux actually cost before that cost is spread across the whole step set.
*Done:* correct report on macOS, Windows, and Linux for each of present/missing/outdated; detection never mutates anything (S1b's "detection only reports, it never acts"); the Claude-Code-version case is reported without implying the plugin will fix its own host.

**E3 — Guided prerequisite resolution (F2, S2/S2b/S2c)**
Explain why, propose the OS-standard path, confirm, then act — including the honest refusals: user declines (S2b) and unknown OS (S2c). Separate from E2 because detection is read-only and resolution is the first thing that changes the user's machine, which is a different trust and risk profile (A4) and a different test burden. Shipping E2 without E3 is coherent; the reverse is not.
*Done:* no install without explicit confirmation; declining stops cleanly with no partial side effect; an unsupported OS yields a named manual instruction, never a guessed command; `gh auth login` handled as its own explained, browser-based step with no credential ever typed into the conversation.

**E4 — Intake and target decision (F3, S3/S3b + the Gap-2 and Gap-5 cases)**
The conversational question flow: which directory, which adoption mode, validated one question at a time, with a clean bail-out. This must also absorb the two cases currently unrequired: the target that is not a git repo, and how the per-project-vs-machine-wide choice is decided *for* a user who can't decide it. Separate unit because its output — a validated, complete set of answers — is the contract everything downstream consumes, and because it is where the product's central usability claim is most exposed: this is the part a non-engineer either understands or doesn't.
*Done:* every question answerable by someone who has never seen a shell; invalid answers rejected with an explanation, not an error; a non-git target has one explicit, decided behaviour; stopping mid-intake writes nothing anywhere; the mode choice is reached without the user needing to know `--user` exists conceptually, not just syntactically.

**E5 — Preview and execution of the adoption steps (F4 + F5, S4/S4b/S5/S5b)**
The actual work: place skills, install hooks, symlink `CLAUDE.md`, seed the adoption table — each narrated, each with its own plan function, with preview as the user-facing aggregation. F4 and F5 belong in *one* unit despite being separate PRD entries: preview without execution delivers nothing, and for this audience execution without a truthful preview is the thing the product exists to avoid (S5b's "refused, not run blind" is a property of the step set, not a feature bolted on afterwards). Splitting them invites a v1 where preview is "added later" and never is.
*Done:* resulting target state matches what `adopt.sh` produces today for the chosen mode, against an enumerated list; every step previews honestly or is refused; a mid-run failure stops, is explained, and is never reported as success.

**E6 — Verification and honest reporting (F7, S7/S7b)**
Independent re-checking of declared success criteria, pass/fail per criterion, never "done" while one fails. Separate unit because it is independently valuable as a standalone "check my setup is still correct" capability — including against an adoption installed by `adopt.sh` — and because its whole point is not trusting E5's own report (S7b). Keeping it a separate unit keeps that independence real rather than nominal. This unit should also settle what F7's "smoke command" actually proves.
*Done:* per-criterion plain-language pass/fail; a wrong-target symlink is caught; the overall verdict is never "done" with any criterion failing; it can be run on demand, not only immediately after E5.

**E7 — Interruption resilience (F6 + A3 state model, S6/S6b)**
Progress marker with `started`/`verified`/definition-version/input-hash/evidence, and resume that re-checks reality rather than trusting a flag. A separate unit because it adds no new user-visible capability — it is pure robustness — and because it is the most expensive item per unit of visible value in the whole list (A3's amended state model touches every step in E5). It is also the item most defensible to cut or thin for a first real user, provided a failed run can be safely re-run from the start instead; that is a decision worth making deliberately rather than by default. Counter-argument to note: for this audience a half-finished install is the worst possible outcome, so if it is cut, E5's idempotence has to be strong enough that "just run it again" is genuinely safe.
*Done:* an interrupted run resumes to the same visible end state as an uninterrupted one; the crash-between-effect-and-record case resolves correctly; a mismatch between recorded and actual state is reported as incomplete, never silently marked done.

**W1 — Boundary check for the generic/specific split (work item, not an epic)**
A mechanical check — plausibly in this repo's `check` command — that no `spec-driven-guardrails` literal appears in the generic-side files, which is `ARCHITECTURE.md`'s own stated violation signal. Pure internal groundwork with no user value, but small and cheap, and it is the single thing that makes the deferred extraction actually cheap instead of nominally cheap. The Technical-debt table admits the split is "design intent, not yet a proven abstraction"; this converts intent into something enforced continuously rather than remembered.
*Done:* the check exists, runs in CI, and fails on a deliberately introduced violation.

**W2 — Decide and document the fate of `adopt.sh` (work item)**
One decision, recorded: deprecated, frozen, or maintained alongside; and which path is supported for which audience. Separate because it is a decision, not a build, it costs almost nothing, and leaving it open guarantees drift between two implementations of the same adoption (Gap 6).
*Done:* the decision is written in `PRD.md` / the repo's own docs, and it is unambiguous which entry point a given user should use.

**Named but deliberately out of v1 (should be recorded, not silent):**
- **Update / re-adoption** of an already-adopted project to a newer workflow version (Gap 7) — this will become the most common operation; it needs at minimum a Known-limitations entry with the manual path.
- **Uninstall** (Gap 8) — either scoped in, or documented as a manual procedure.

**Sequencing view.** E1 first and standalone — it is cheap, it is the largest usability risk, and it is testable immediately with a real person. Then the thin slice: E2 → E4 → E5 (one step only) → E6, on one OS. Then broaden: E3, the remaining steps in E5, the OS matrix, and E7 last. W1 alongside the first code; W2 whenever.

---

## 4. Open questions and risks for Ties

1. **The value hypothesis is untested and the docs know it.** No real non-engineer has ever tried to adopt this workflow. The largest risk is not that the installer fails, but that it succeeds and the person then can't use a git/issue/PR/TDD workflow. Cheapest possible de-risk before committing: do E1 by hand — walk one real non-engineer through Desktop install and a manual `adopt.sh`-equivalent setup, then watch them try to *use* the workflow for an hour. That test invalidates or confirms the premise for a fraction of the build cost.
2. **Cross-platform (A5) is likely the biggest single cost driver in v1, and it rests on an assumption.** "The non-engineer audience's OS is unknown in advance" is asserted, not evidenced. If the first one or two real users are known people on known machines, A5 could be scoped to what they actually run and widened later — saving substantial effort. Worth asking explicitly rather than inheriting. Related and unasked: what does "adopted" even mean on Windows, where the payload includes symlinked `CLAUDE.md` and git hooks? That is a product-level question about the deliverable, not only an implementation detail.
3. **Reimplementation instead of wrapping creates a permanent two-implementation problem.** A5's rejection of shelling out to `adopt.sh` is well-argued, but the consequence — two installers for one workflow, both needing to track `CHANGES.md` as the workflow evolves — is never costed. W2 is the minimum response.
4. **The primitive set may be oversized for v1's actual job.** `ARCHITECTURE.md` specifies 6-8 primitives, each with execution, plan, and verification logic, plus A3's full per-step state model. The job v1 actually does is: place some files, install some hooks, make a symlink, seed a table. There is a real risk of building the generic machinery anyway — through the primitive abstraction — after explicitly deciding not to build it speculatively. Worth a conscious check that the primitive set is derived from the steps v1 genuinely needs, rather than anticipated.
5. **The bootstrap manual is filed as debt but is actually the gating deliverable.** As scoped, v1 produces a plugin that the target audience has no documented way to reach. Recommend promoting it to E1 rather than leaving it as a Technical-debt row.
6. **Distribution depends on infrastructure outside the project's control.** v1 assumes marketplace-add plus plugin-install works, and works for a non-engineer. If that path changes or is gated, the entire delivery route changes. Worth verifying end to end early, as part of E1, not at the end.
7. **Nothing defines what "v1 is finished" means.** There is no release criterion, no target user, no success measure. Before committing, it is worth writing one sentence: who is the first real user, and what must they be able to do unaided for this to have been worth building?

---

### Handover note for the Architect

The three things most likely to change your grouping: (a) E5 deliberately fuses F4 and F5 on product grounds — if the primitive design makes that awkward, the fusion is the constraint to preserve, not the packaging; (b) E7 is positioned as cut-or-thin candidate, which materially affects how much state the step model must carry from day one; (c) two requirements are currently unbuilt because they are unwritten — the non-git target (Gap 2) and the per-project-vs-machine-wide default (Gap 5) — and both land in E4. Also worth your pass: whether the 6-8 primitive set is derived from v1's real steps or anticipated (risk 4), and what A5 implies for symlinks and git hooks on Windows (risk 2).
