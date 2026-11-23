# Architect role report — `agentic-workflow-installer` v1 (co-thinking session, epic #65)

Model/effort: Claude Opus (general-purpose agent, Architect role).

Scope: `PRD.md`, `ARCHITECTURE.md`, `TEST-SCENARIOS.md`, and the Product role's `CO-THINKING-PRODUCT-REPORT.md`. Also read `adopt.sh` (513 lines) in full, since two of the three handed-off questions can only be answered against the real step list, not the docs' description of it. Did not re-validate product framing.

Headline: the *decision* (Option 1 over Options 2/3/4, plugin-first build order) is sound and well-argued. The *design underneath it* has one contradiction, one structurally broken mechanism, and one missing decision large enough that no work item below it can be sized. None of these is fatal; all three are cheaper to fix now than after E5 starts.

---

## 1. Architecture soundness check

### 1.1 The missing decision: nothing says what the primitives are implemented in, or how the payload reaches the machine

`ARCHITECTURE.md` decides splits, manifests, primitives, state, and boundaries. It never decides **what language/runtime the plugin's primitive scripts are written in**. That is the load-bearing platform choice the document's own preamble says belongs here ("Yes: platform choices"). It is absent, and it is the decision A5's satisfiability hangs on — "cross-platform-safe primitives" is not a property you can assess without knowing whether they are Bash, Node, Python, or Claude-Code tool calls driven by a skill.

Second half of the same gap: the adoption model is **symlinks into an absolute path on this machine** (`$CLAUDE_WORKFLOW_DIR`). `adopt.sh` presupposes that path exists and is exported. The plugin's whole reason for existing is that the non-engineer has not done that. So the plugin must either (a) clone `spec-driven-guardrails` somewhere and become the owner of that path, or (b) use the plugin's own installed directory as `CLAUDE_WORKFLOW_DIR`. These have completely different update, ownership, and uninstall consequences. Neither is chosen; neither is even named as open. (This also settles whether `clone_repository` is a real primitive or a speculative one — see §2c.)

**This is the single biggest omission in the document.** It should be a decision made before any epic starts.

### 1.2 Direct contradiction: "no general shell primitive" vs. `run_approved_command`

"The decision" states, in consecutive sentences, that the primitive set is `check_tool, install_package, clone_repository, copy_template, write_config, run_approved_command, assert` and that there is **"No general `shell` primitive in v1"**, because a generic shell step "would make preview, cross-platform behavior, safety, and idempotence a per-manifest concern again."

`run_approved_command` *is* that escape hatch under a friendlier name. Every property the paragraph claims to protect becomes per-call the moment it exists. And it is currently the only way to express two things v1 genuinely needs (`gh auth login`, `chmod +x`). So the rule as written is either violated on day one or blocks real steps.

Resolution needed, not deferral: either drop it and add named primitives (`set_executable`, `authenticate_github`), or redefine it as a **closed whitelist** where each allowed invocation ships its own plan and verification function — which is the same discipline as a primitive, just packaged differently. What cannot stand is the current text claiming both.

### 1.3 F5's aggregation model is structurally broken for the real step list

`PRD.md` F5: "F5 is the aggregation of those per-primitive previews, not a generic mechanism layered on top." `TEST-SCENARIOS.md` S5 promises "for every step F4 would run, its own plan/dry-run function reports what would change" *before* anything runs.

That does not hold, and today's `adopt.sh` proves it. In `adopt_project`, the CONTEXT.md step's *plan* depends on the *effect* of the adoption-table step in the same run (a `grep` check against `WORKFLOW-ADOPTION.md` after `seed_adoption_table` has already run). There is at least one more of these (`if [ -f "$project_dir/package.json" ]` gates four further steps, and a prior step could in principle create it).

Consequence: summing independent per-primitive previews cannot produce an honest whole-run preview. The honest options are (i) plan against a simulated overlay so step N plans against step N-1's *simulated* effect — which is exactly what chezmoi does and why the doc cites it, but it means building a virtual-filesystem layer that appears in no estimate anywhere; or (ii) narrow F5's promise to "preview the next step, and the independent steps," and say so in the PRD and S5. Right now the doc promises (i)'s behavior while describing (ii)'s mechanism.

A related, smaller point: for the two managed-file-merge steps, an honest plan function must essentially run the full transform against a copy and diff it. `write_gitignore_block` is ~90 lines of awk with corrupted-marker detection. Its plan function is not a small add-on to it; it is roughly a second implementation. The "no primitive ships without a plan function" rule (S5b) is right, but its cost is concentrated in exactly two primitives and nobody has said so.

### 1.4 The generic/specific split's violation signal is too weak to be trusted

The stated signal is "a `spec-driven-guardrails` literal appearing in the generic side's files." That catches the *name* and misses the *shape*. `seed_adoption_table` — the most project-specific function in the file — can be written as "merge rows into a Markdown table with these column names" and pass a grep for the string while being entirely specific to this workflow. W1's CI check will go green on a split that is broken.

Related over-claim in "Build order decided": it names `backup_if_real_file`, `scaffold_if_missing`, `skill_symlink_update`, `install_skills`, `install_git_hooks` as "generic-shaped but not yet separated." The first three genuinely are. `install_skills` hardcodes this workflow's `skills/*/` layout and one-symlink-per-skill policy; `install_git_hooks` hardcodes `pre-commit`/`pre-push` and a `hooks/` source directory. Both are parameterizable, but they are *not* generic today, and `write_gitignore_block`'s managed markers are project-branded strings.

The honest reading: the genuinely generic residue is about three small functions. The value of the plugin is therefore **not** the reuse of lifted logic — it is the plan/verify/narrate wrappers around it. Worth saying plainly, because it changes what "extraction is cheap later" means.

### 1.5 The ownership boundary contradicts F3's own two modes

"System boundaries and ownership" states the installer "may only write within the target directory the user confirmed (F3)" and "may never assume or modify anything about the user's broader machine beyond installing declared prerequisites."

But F3's flagship example question is *per-project vs. machine-wide*, and `adopt_user_trigger` writes `$HOME/.claude/CLAUDE.md` and `$HOME/.claude/skills/adopt-workflow`. `install_git_hooks` also writes inside `.git/hooks`, which is inside the target but explicitly excluded from git's own content model. So one of F3's two modes is outside the boundary the architecture draws.

This is very likely *why* Product found zero scenario coverage for the `--user` path: the boundary model does not admit that mode exists. Fix the boundary text to name a second, explicitly-scoped user-level write region, or drop the mode from v1 — but don't leave a documented mode that the ownership rule forbids.

### 1.6 A6's admission gate is drawn one step too early

A6 narrows the precondition to "install and sign into the Claude Desktop app." Verified and correct as far as it goes. But the plugin is only reachable after *marketplace add + plugin install*, and the plugin cannot perform those — it is not installed yet. So the admission gate is really "Desktop app + signed in + marketplace added + plugin installed," and A6 currently stops two steps short of its own boundary.

Product's E1 covers this pragmatically. Architecturally, A6's text should be widened, because the boundary is what tells you which things are permanently out of the core's reach.

Same defect, sharper form: F1 lists "a specific Claude Code version" as a detectable prerequisite. A Claude Code old enough to fail that check is, in the relevant cases, too old to have loaded the plugin that runs it. The check is either unreachable or belongs entirely in the admission gate. Product flagged the F1/F2 tension; I'd go further than "carve out the wording" — move it out of F1.

### 1.7 A5 is stated narrowly and used broadly

A5's own text scopes itself to "prerequisite detection and resolution (`PRD.md` F1/F2)," and its violation signal is "a prerequisite check or fix that only runs under Bash/POSIX." "Build order decided" then extends cross-platform to *all* the plugin's primitive scripts, which is much more demanding. Both readings are in the document. Given §2c below, this is not a wording nit — the broad reading is the expensive one and it is the one being relied on.

### 1.8 Unproven assumptions currently treated as settled

- "Reimplementing `adopt.sh`'s logic as cross-platform primitives is achievable" — asserted in "Build order decided" as a straightforward consequence of rejecting the wrapper. §2c shows it is not.
- "The generic-shaped functions carry no project literals" — over-claimed (§1.4).
- "Marketplace add + plugin install works, and works for a non-engineer" — this is the distribution path the entire delivery depends on and it appears in ARCHITECTURE.md only as a resolved-and-closed item. Product's risk 6 is right; architecturally it is an unnamed dependency risk on infrastructure outside the project's control.

### 1.9 What is genuinely sound, and should not be reopened

The Option 1-vs-Option 4 resolution is the strongest reasoning in the document, and the argument it turns on — a progress marker cannot prove a side effect happened, and an interruption can land between an effect and its record — is correct and is the right reason to reject prompt-as-execution-engine. "Build order decided" (single plugin, internal split, extraction on a second real consumer) is also correct and resists the obvious temptation. The prior-art selection (chezmoi for dry-run/state, dotbot for a deliberately small action set) is apt and actually informed the design rather than decorating it. None of my findings above touch these.

---

## 2. Answers to the Product report's three asks

### (a) Is E5's F4+F5 fusion workable in the primitive design, or does it strain it?

**Workable, and I go further than Product: the fusion is not a product preference, it is architecturally mandatory.** "Every primitive owns its own plan function; no primitive ships without one" means F5 is not a feature layered on F4 — it is a constructor argument of every primitive. You cannot build F4 first and add F5 later without rewriting each primitive. Product's instinct ("splitting them invites a v1 where preview is added later and never is") is right for a stronger reason than they gave.

**What strains — and it is real, not deferrable:** the fusion is fine at the *primitive* level and breaks at the *aggregation* level, per §1.3. What breaks concretely: the user-facing promise in S5 of a whole-run preview before anything executes. With order-dependent steps (`seed_adoption_table` → CONTEXT.md scaffold; `package.json` presence → four CI-template steps), steps after the first state-changing step cannot be honestly previewed without a simulation layer.

So: **keep the fusion, but E5 must carry an explicit decision** — build the overlay/simulation layer (real cost, currently unestimated, chezmoi is the model) or narrow F5's promise and amend S5. My recommendation: narrow the promise for v1. "Here is everything the first N independent steps will do, then I'll show you each remaining step before I run it" is honest, deliverable, and arguably *better* for a non-engineer than one long upfront wall of planned changes.

Second strain, smaller: I do not think E5 should be one unit — see §3, E5a/E5b. That is a split on preview-difficulty grounds, not a rejection of the F4/F5 fusion, which survives intact in both halves.

### (b) What does cutting or thinning E7 actually cost the state model?

**It is a nearly clean cut, and the reason is a tension already inside A3.** A3 says: "On resume, the core re-checks actual target state against `verified` rather than trusting `started` or a bare `done` flag." S6b says the same. But if re-checking actual state is authoritative — and for this payload it is trivially cheap, since every step's verification is a file-state question (does this symlink resolve to X, is this managed block present, is this file executable) — then **the verification function is the source of truth and the marker is an optimization, not a correctness mechanism.** The heavy A3 fields (`started`, `verified` evidence, input hash) are largely redundant with the thing A3 itself says overrides them.

That is the clean part. Three places where it ripples:

1. **`definition-version` is the one field that is not redundant — and it serves an out-of-scope use case.** It answers "which version of the step definitions did this run under," which is useless for resume (you re-verify anyway) and is exactly what an **update / re-adoption** needs (Product's Gap 7). So the most defensible field in A3's state model exists for the operation v1 excludes, and the fields that serve in-scope resume are the ones verification makes redundant. If E7 is cut, record explicitly that update will have to introduce a step-version record later.

2. **Idempotence is not uniform across the real step list, so "just run it again" is not safe everywhere.** Symlink steps, `scaffold_if_missing`, and `write_gitignore_block` (block replace) are genuinely idempotent — re-running is safe. `backup_if_real_file` is the exception: it *moves* a user's real file to `.bak`. It is safe on immediate re-run, but a second run after the user has restored their file will overwrite the earlier backup. Product's counter-argument ("if E7 is cut, E5's idempotence has to be strong enough") lands precisely on this one function.

3. **Test coverage: S6, S6b lose their subject, and S3b's "no progress-marker state for steps that never started" becomes vacuous.** Cheap to absorb, but should be done deliberately in TEST-SCENARIOS.md, not silently.

**My recommendation: thin, don't cut — and don't keep it as a separate epic at all.** Keep a minimal completion marker (which steps finished, under which definition version) as optimization plus audit trail; drop per-step input hashes and stored verification evidence; require every primitive to be verify-idempotent, with `backup_if_real_file` carrying an explicit "don't clobber an existing `.bak`" rule. That is roughly 20% of E7's cost and keeps the one field that has a future.

The structural point, and the reason I move it in §3: **A3's state is a cross-cutting property of every step in E5** (Product says this themselves). Retrofitting a cross-cutting property onto a finished step set is dearer than building it in. Sequencing it "last," as Product's sequencing view does, is the most expensive possible order for it.

### (c) Is the 6-8 primitive set derived from v1's real step list, or speculative? And what does A5 really imply for Windows?

**Derivation: partly derived, partly speculative, and it misses the two operations that dominate the real work.** Every operation `adopt_project` and `adopt_user_trigger` actually perform:

| Real operation in `adopt.sh` | Covered by the stated primitive set? |
|---|---|
| `ln -s` — `CLAUDE.md`, `.claude/settings.json`, one per skill, 2 git hooks, `~/.claude/CLAUDE.md` | **No primitive exists for this** |
| `write_gitignore_block` — marker-delimited managed block inside a user-owned tracked file, with corrupted-marker abort | Nominally `write_config`; badly understated |
| `seed_adoption_table` — merge rows into `WORKFLOW-ADOPTION.md` | Nominally `write_config`; same |
| `scaffold_if_missing` — copy template only if absent | `copy_template` OK |
| `copy_issue_templates` — directory copy | `copy_template` OK |
| `backup_if_real_file` — move real file aside, delete existing symlink | No primitive; is a *policy* of the symlink primitive |
| `skill_symlink_cleanup_if_orphaned` — remove stale links | No primitive (and note: it is an undo-shaped operation, in a design that declares no rollback) |
| `mkdir -p` | No primitive |
| `chmod +x` | No primitive (only via `run_approved_command`) |
| conditional gating on target state (`package.json` present; adoption-table row = yes) | **No construct at all** |
| refuse-and-report on a foreign git hook | No primitive; a policy |
| `check_tool` / `install_package` (F1/F2) | Real, but belong to E2/E3, not the adoption steps |
| `clone_repository` | Not used by `adopt.sh` at all — but see §1.1: it may be genuinely needed, and nobody has decided |
| `assert` | Overlaps per-primitive verification; role ambiguous |

Three conclusions:

- **`symlink` is missing, and it is the single most-used operation in the entire adoption.** It is not `copy_template` and not `write_config`: it has its own preview (what the link will point at), its own verification (`readlink` resolves to X), its own idempotence rule (replace only if the existing link is already ours — `install_git_hooks` implements exactly this), and, critically, its own cross-platform story. Omitting it from the derived set is how the Windows problem below stayed invisible.
- **`write_config` conceals two of the hardest steps in the system.** A marker-delimited merge into a *user-owned, git-tracked* file is a different risk class from writing a config file. `adopt.sh`'s own comments say so at length: an earlier version with an unmatched begin marker silently erased the rest of a `.gitignore` that was excluding two nested git repos. Whatever that primitive is called, it should not be called `write_config`.
- **There is no conditional construct**, yet the real step list has at least two genuine conditionals. A declarative step list that must express them is under direct pressure to grow an `if` — which is the first step toward the general-purpose interpreter the design explicitly rejected.

So Product's risk 4 needs re-aiming (see §4): the set is not *oversized*, it is **mis-derived** — too generic where v1 does nothing (`clone_repository` undecided, `run_approved_command` self-contradictory) and silent where v1 does almost everything (symlink, managed merge). The fix is to re-derive it from `adopt_project` line by line, not to shrink the count.

**A5 and Windows — this is the biggest technical risk in the proposal, and the docs treat it as settled.**

The adoption payload *is* symlinks. On Windows:

1. **Creating a symlink requires Developer Mode or elevation** (`SeCreateSymbolicLinkPrivilege`). A default, non-admin Windows account cannot. The target audience — non-engineers — is the population *least* likely to have Developer Mode enabled, and enabling it is a settings change to their machine, which A4/A2 say must be explained and confirmed, and the ownership boundary (§1.5) arguably forbids.
2. **Git for Windows commonly ships with `core.symlinks=false`**, so even a successfully created link can round-trip through git as a plain text file.
3. **`chmod +x` is a no-op**; git hooks on Windows run through Git's bundled `sh`, so a symlinked hook's executability and interpreter both behave differently.
4. **The fallback is copies — and copies change the product's semantics, not just its implementation.** `adopt.sh`'s comments state the design intent explicitly: symlinks so that "the rule must always be the current version from spec-driven-guardrails, not a snapshot." A copy *is* a snapshot. So a Windows fallback silently converts the adoption from live-linked to snapshot-based, which means Windows users need a **re-sync/update mechanism** — which is precisely Product's Gap 7, the thing v1 excludes.

**Therefore A5-as-written does not cost "some porting work." It forces a second adoption model whose update semantics differ visibly from the primary one, and it pulls an excluded requirement into scope.** This is the place where a stated requirement and the real design do not line up, and it is not named as a risk anywhere in ARCHITECTURE.md.

Two acceptable resolutions, and Ties should pick one deliberately:

- **Narrow A5 for v1** to symlink-native platforms (macOS + Linux), record Windows in Known limitations with the reason, and revisit when a real Windows user appears. Product's risk 2 already asks whether the "OS is unknown in advance" premise is evidenced; if the first users are known people on known machines, this is nearly free.
- **Accept the second model**, and budget for it: a copy-mode adoption plus a resync path, roughly doubling E5's step logic and promoting update from out-of-scope to in-scope.

What is *not* acceptable is keeping A5 as written while sizing the work against the symlink model. That is the current state of the plan.

---

## 3. Final epic / work-item decomposition

Product's grouping is good and most of it is kept. Where it's agreed, that's said briefly. Every deviation carries its technical reason.

**W0 — Decide the implementation runtime and the payload-delivery model** *(new; blocks everything)*
What the primitive scripts are written in, and whether the plugin clones `spec-driven-guardrails` or acts as `CLAUDE_WORKFLOW_DIR` itself. *Reason for adding: §1.1 — no primitive can be written without the first, and the second decides whether `clone_repository` is real. Both are the platform-choice class ARCHITECTURE.md says belongs in ARCHITECTURE.md. Small, pure decision; nothing below can be sized without it.*
*Done:* both decisions written into ARCHITECTURE.md with alternatives weighed.

**W-A5 — Windows symlink spike, then renegotiate A5** *(new; runs parallel to E1, before E5 is sized)*
A one-day spike on a real non-admin Windows box: can the plugin create the required symlinks, do git hooks fire, does `core.symlinks` interfere. Then Ties picks narrow-A5 or accept-copy-mode. *Reason for adding: §2c — this is a model decision affecting every step in E5 and the update story, not a porting detail, and it is currently invisible in the plan.*
*Done:* A5 amended with an explicit platform scope; if copy-mode is accepted, its update semantics are written down.

**E1 — Bootstrap admission path (docs only)** — agree with Product: first, standalone. Two adjustments: (i) widen it to marketplace-add + plugin-install, per §1.6, because A6's gate stops two steps short of where the plugin can actually act; (ii) verify the distribution path works before writing the manual for it — Product's own risk 6, and a route that hasn't been walked can't be documented. So E1 = verify path, then write manual, then test on a real person.
*Done:* as Product stated, plus the distribution path confirmed end to end.

**E2 — Machine readiness check (F1, S1/S1b)** — agree with Product, including that this is where A5 first bites. One change: **move the Claude Code version check out of F1 into E1's admission gate** (§1.6 — a Claude Code too old to load the plugin cannot be checked by the plugin).

**E4 — Intake and target decision (F3, S3/S3b + Gaps 2 and 5)** — agree with Product, including sequencing before E3. Add one required output: **settle the `--user` mode against the ownership boundary** (§1.5). Either scope a second, named user-level write region in ARCHITECTURE.md, or drop the mode from v1. Also: today's code already has two contradictory behaviors for the non-git-target case (`adopt_project` hard-exits, `install_git_hooks` silently returns) — E4 is choosing between existing behaviors, not inventing from nothing.

**E5a — Walking skeleton: link/copy/scaffold steps, with preview** *(deviation: E5 split)*
`mkdir`, symlink (with the backup-and-don't-clobber policy), `scaffold_if_missing`, `set_executable`, orphan cleanup — each with its plan function, preview fused per F4+F5. *Reason for the split: §1.3 and §2a — these steps are order-independent and previewable honestly in isolation. The E5b steps are not. Keeping them in one epic hides a 2-3x cost difference and risks the skeleton never walking.* Includes the re-derived primitive set from §2c (symlink as a first-class primitive; `run_approved_command` resolved per §1.2).
*Done:* one real step carried end to end on one OS; every step previews honestly; a mid-run failure stops, is explained, is never reported as success.

**E5b — Managed-file merges and conditional steps** *(deviation: E5 split)*
`write_gitignore_block`, `seed_adoption_table`, and the two state-dependent conditionals (`package.json` → CI templates; adoption-table row → CONTEXT.md). *Reason for separating: these carry the corrupted-marker risk class, their plan functions are near-second-implementations, and they are the steps that force F5's aggregation decision (§1.3) and push toward a conditional construct the architecture rejected (§2c). They are also the least plausible candidates for the generic side.*
*Done:* F5's scope decision is made and written; a corrupted managed block aborts loudly and touches nothing; each conditional's preview behavior is defined, not implied.

**E6 — Verification and honest reporting (F7, S7/S7b)** — agree with Product, separate unit, and a stronger reason: E6 is the mechanism that makes thinning E7 safe (§2b). Verification-as-source-of-truth is what makes the marker an optimization rather than a correctness mechanism, so E6 must land before any E7 decision is executed. Keep Product's point that it should be runnable on demand, including against an `adopt.sh`-installed adoption. It should also settle what F7's "smoke command" proves.

**E3 — Guided prerequisite resolution (F2, S2/S2b/S2c)** — agree with Product entirely, including that E2-without-E3 is coherent and the reverse is not. Sequenced after the thin slice, as proposed.

**~~E7~~ -> folded into E5a/E5b as a property, plus a deferred work item** *(deviation: demoted from epic)*
Minimal completion marker + verify-on-resume built into the primitives from the start; per-step input hashes and stored evidence dropped; every primitive verify-idempotent, with `backup_if_real_file` carrying a don't-clobber-an-existing-`.bak` rule. *Reason: §2b — A3's state touches every step in E5, so it is a cross-cutting property, and retrofitting a cross-cutting property onto a finished step set is dearer than building it in. Product's sequencing puts it last, which is the most expensive possible order.* The `definition-version` record spins out as a small deferred item attached to update/re-adoption, since that is the only thing it serves.

**W1 — Boundary check for the generic/specific split** — agree it should exist, disagree it is sufficient (§1.4). Keep the literal grep, and add the test that actually proves something: **the generic-side files must be exercised by tests that never load the `spec-driven-guardrails` configuration.** A grep that passes on a broken split is worse than no check, because it manufactures confidence.
*Done:* both checks in CI; both fail on a deliberately introduced violation, including a shape-level one.

**W2 — Decide the fate of `adopt.sh`** — agree with Product, and raise its priority: it must land before E5's acceptance criteria are fixed. E5's stated pass condition is "the same state `adopt.sh` would produce today." If `adopt.sh` keeps evolving, that target moves during the build.

**Recorded, deliberately out of v1** (agree with Product these must be written, not silent): update / re-adoption — now with the added note from §2b that cutting E7 forfeits the one field that would have supported it, and from §2c that a Windows copy-mode fallback would make it mandatory rather than optional; and uninstall, with at minimum a manual removal path.

**Sequencing:** W0 first, gating everything. Then E1 and W-A5 in parallel — both are cheap, both are kill-criteria-shaped. Then the thin slice on one OS: E2 → E4 → E5a (one step) → E6. Then broaden: rest of E5a, E3, then E5b last among the code. W1 alongside the first code. W2 before E5's acceptance criteria are fixed.

This differs from Product's sequencing in three places: W0 and W-A5 are new and go first; E5 splits with E5b moved late; E7 disappears as an epic and moves *into* E5 as a property. Everything else is their order.

---

## 4. Points of genuine disagreement with the Product report

**4.1 What the biggest risk is.**
*Product's position (risk 1):* the largest risk is the value hypothesis — the installer succeeds and the person then can't use a git/issue/PR/TDD workflow.
*Architect's position:* technically, the largest risk is that the adoption payload is symlink-based and a default Windows account cannot create symlinks, so A5-as-written either is not buildable or silently introduces a second adoption model with different update semantics (§2c).
*Not in conflict, not overriding* — Product's is product-level, this is technical. Product's risk is best tested cheaply and early (their proposed manual walkthrough is a good de-risk); the Windows risk changes the plan now, before E5 is sized. Both belong at the top of the list.

**4.2 Product's risk 4 — "the primitive set may be oversized."**
*Product's position:* 6-8 primitives with execution/plan/verification may be over-built for a job that is "place some files, install some hooks, make a symlink, seed a table"; there is a risk of building the generic machinery anyway.
*Architect's position:* the instinct is right, the diagnosis is wrong. The set is **mis-derived, not oversized** (§2c). It omits `symlink` — the most-used operation in the entire adoption — understates the two managed-file merges as `write_config`, includes `clone_repository` which `adopt.sh` never does and whose necessity is genuinely undecided, and contains `run_approved_command` in direct contradiction of the same paragraph's "no general shell primitive" rule. Shrinking the count would be the wrong response and could drop the wrong primitives. Re-deriving from `adopt_project` line by line is the right one — likely resulting in *more* named primitives, each much smaller.

**4.3 E7 as a standalone epic and a cut candidate.**
*Product's position:* E7 is a separate epic, "the most expensive item per unit of visible value," "the item most defensible to cut or thin," sequenced last.
*Architect's position:* agree it should be thinned, disagree it should be a separate epic, disagree with sequencing it last (§2b). A3's state touches every step in E5 by Product's own description — a cross-cutting property, for which last is the most expensive order. Folded into E5a/E5b. Also disagree with a clean cut: the `definition-version` field should survive as a deferred item, because it's the only thing that will ever support update/re-adoption — which Product themselves identify as the operation that will become most frequent after month one.

**4.4 E5 as a single unit.**
*Product's position:* F4 and F5 belong in one unit; splitting invites a v1 where preview is added later and never is.
*Architect's position:* complete agreement on the **F4/F5 fusion** — and it's stronger than argued, since the per-primitive plan rule makes it structural, not a packaging choice. Disagreement only on E5 being one *epic*: split into E5a/E5b on preview-difficulty and risk-class grounds (§3). The fusion survives intact inside both halves, so Product's stated constraint is preserved exactly as asked.

**4.5 W1 as "the single thing that makes the deferred extraction actually cheap."**
*Product's position:* the literal-grep check converts split-intent into something enforced continuously.
*Architect's position:* the check is worth having but far weaker than that claim (§1.4) — it tests for a *name*, and the most project-specific logic in the system can pass it. The real cost of the later extraction is not literal leakage; only about three small functions are genuinely generic (§1.4), so "extraction is cheap" was already a smaller claim than it sounds. W1 is kept, with a test that has teeth. The concern is specifically that W1-as-framed creates false confidence in an abstraction the Technical-debt table is otherwise honest about.

**4.6 E1 being immediately testable.**
*Product's position:* E1 is "the only part that can be validated with a real non-engineer before any of the plugin exists," so do it first.
*Architect's position:* agree it goes first, but it has a prerequisite Product didn't have visibility into: E1's manual documents a distribution path (marketplace add + plugin install) nobody has verified end to end, and W0's payload-delivery decision (§1.1) determines what the manual has to tell the user to do. E1 = W0 → verify path → write manual → test on a real person. A manual written ahead of that verification will be rewritten.

**4.7 One endorsement worth recording, not a disagreement.**
Product's Gap 2 (non-git target) is more load-bearing than they could show from the docs alone: `adopt.sh` today already contains two contradictory behaviors for it. E4 is picking between existing behaviors, which makes the gap cheaper to close than it reads and removes any excuse for leaving it open.

---

### One-line summary for the decision

The decision and the build order are sound and should be accepted. Three things should be fixed before any work item starts, and none of them is expensive: **decide the implementation runtime and payload-delivery model (W0)**, **resolve `run_approved_command` against the no-escape-hatch rule**, and **spike Windows symlinks and renegotiate A5 (W-A5)**. The one structural correction is **F5's aggregation promise**, which today's `adopt.sh` demonstrably cannot satisfy as written.
