# Architecture decision — Install model for a second user (W37, #79)

This document records *why* the system is the way it is. `PRD.md` describes
what it must do; this is where the structural choices underneath that live,
which alternatives were weighed, and when a choice should be revisited.

Not every decision belongs here. Yes: platform choices, the split into
layers or components, who owns which data, and adding a substantial
dependency. No: how one function is written.

---

## The decision

**Decided on 2026-09-09: a new, git-only entrypoint `install.sh` pins a
checkout to a tagged release, separate from `adopt.sh`.**

`install.sh` runs after a manual `git clone`, from inside that clone
itself. It validates a clean working directory, checks out a given (or
otherwise the latest) tag, and reports the `SPEC_DRIVEN_GUARDRAILS_DIR`
line the user puts in their shell profile. It doesn't adopt a project —
that stays `adopt.sh`'s job. TiesL's own multi-machine usage (clone, always
follow `main`) doesn't change: this is a second, explicitly chosen path,
not a replacement.

---

## Evaluation criteria

| Criterion | Why it counts |
|---|---|
| Auditability | This repo's whole style is readable-through bash with no surprises (no `eval`, fail-open when in doubt). An install mechanism that undermines that would undercut exactly the trust the rest of the repo builds. |
| Reuse over building new | W29/#53 decision 5 was explicit: build on W22's existing tag/`CHANGELOG.md` mechanism, don't reinvent anything. |
| Separation of concerns | "Pin this checkout to version X" and "link this project to that checkout" are two different questions with different failure modes (a wrong tag vs. a wrong project) — mixing them makes both harder to reason about. |
| Fits the audience | W37's "second user" is someone already using Claude Code and git (the same workflow is being adopted) — no need for an install mechanism for someone without git. |

---

## Options weighed

### Option 1 — Documentation only, no new script
The consumer reads a new README section and carries out the clone, checkout,
and env-var steps manually. Smallest footprint, zero new code to maintain.
Downside: three manual steps are three places to mistype a tag name or
forget the env var, with no validation at all (for example a dirty working
directory silently overwritten by `git checkout`).

### Option 2 — Convenience entrypoint `install.sh` (chosen)
Automates checkout + validation right after the user has already cloned.
Adds exactly two new, testable guarantees option 1 doesn't give: a dirty
working directory is refused instead of overwritten, and an unknown tag
fails with a clear message instead of a cryptic git error.

### Option 3 — `curl | bash` self-install
One command, no prior clone needed. Rejected: runs external code without
the user reading it first — exactly the pattern this repo's own guardrails
(no `eval`, explicit failure paths) fight elsewhere. Would also solve a
separate, small hosting problem (where does the script live before the
clone) that the other options don't have.

### Option 4 — Packaged release artifacts (tarball/zip without git)
GitHub's automatic source archive per tag would give this partly for free.
But the audience already has git (see the criterion above), and
maintaining a separate artifact format for a need that doesn't exist yet is
exactly the kind of speculative building this repo's own `rule-of-three`
principle rejects elsewhere.

---

## Comparison and choice

Option 2 wins: it solves the two concrete failure modes option 1 leaves
open (silent data loss on a dirty working directory, unclear errors on a
wrong tag), without giving up option 3's auditability or introducing option
4's speculative complexity. What you give up for it: one extra script to
maintain, and the consumer still needs to be able to run `git clone`
themselves — accepted deliberately, see the audience assumption above.

---

## Architecture requirements that follow from this

### A1 — Never write to a dirty working directory
`install.sh` checks `git status --porcelain` before every `git checkout`
and refuses on uncommitted changes. This is visibly violated the moment a
future change puts the checkout step before the dirty check.

### A2 — `install.sh` never calls `adopt.sh`
The two scripts each have their own failure mode and their own target
directory (the shared checkout itself, versus an adopted project). Merging
them would make a bug in one step unrecognizable in the other.

### A3 — No externally fetched code execution
`install.sh` never fetches code only to then run it (no `curl | bash`, no
`eval` of fetched content). Everything that runs already lives in the
cloned checkout and is therefore readable by the user before it runs.

---

## System boundaries and ownership

- **`install.sh`** owns "which version is *this* checkout on" — it only
  changes git state within its own directory (`git fetch --tags`,
  `git checkout <tag>`).
- **`adopt.sh`** stays the owner of "which project is linked to which
  checkout" — unchanged by this decision.
- The two communicate only via `SPEC_DRIVEN_GUARDRAILS_DIR`, an environment
  variable the user sets themselves — no direct call between the scripts
  (see A2).

---

## Dependencies

None new. `install.sh` uses only `git`, already a requirement for any
checkout of this repo.

---

## When we would revisit this choice

- If W35 (#59) describes an audience without git — then option 4 (or a
  variant) becomes needed after all, not as a replacement but as an
  addition.
- If the number of manual steps before `install.sh` (clone, `cd`, run the
  script) itself proves to be a demonstrable source of errors — then option
  3 (with an explicit, readable intermediate step, not a blind
  `curl | bash`) is worth reconsidering.

---

## Still open after this document

- **Decided (2026-09-09): no formal GitHub Release for the existing tag
  before epic #52 itself is done.** `install.sh` and the bare git tag work
  no less well for it — a release now would only make a version
  discoverable that isn't yet what epic #52 promises (not yet translated,
  not yet condensed, no front page yet). A `gh release create` per future
  tag, with notes, therefore stays open until the last work items under
  #52 (W33-W35) land — only then is there something a second user should
  actually want to pin.

---

# Architecture decision — Git-environment isolation for `./check` and the test suite (#377)

**Decided on 2026-10-01.** git exports repo-local variables (`GIT_DIR`,
`GIT_INDEX_FILE`, `GIT_PREFIX`, ...) to every hook, `git rebase --exec`
command and `!` alias. A `./check` or test case that inherits them and
runs `git -C <fixture> ...` acts on the launching repo instead of the
fixture: a commit from a linked worktree moved the real `main`, added a
tag and set `core.bare=true`; a partial or `-a` commit had fixture entries
written into git's temporary index. Numbering follows the project-wide
A-series (A4-A13 in `wip/multi-agent-development/ARCHITECTURE-MULTI-AGENT-WIP.md`,
A14-A18 taken by #369/#371), not this file's own A1-A3, so the issue's
references stay valid.

### A19 — One seam for git-environment isolation, with two real callers
- **Module:** `lib/git-env.sh` (source, don't execute; bash 3.2), the only
  copy of the variable list:
  - `git_local_env_vars` prints the union of `git rev-parse
    --local-env-vars` (read at runtime) and a fixed floor of the 15 names
    git 2.50 prints. A newer git that adds a name is covered; a git that
    fails or lists fewer never clears less.
  - `git_local_env_clear` unsets every name in that list.
  - `git_local_env_assert_clear` returns non-zero, naming the first one
    still set.
- **Callers:**
  1. `hooks/pre-commit` clears the list only for the `check-commit` child,
     inside the command substitution. git's own commit flow (including a
     partial commit's temporary index) and the hook's branch and issue
     checks keep the real values; `project_dir` is computed before the
     clear, so the committing worktree's own `check-commit` runs. If
     `lib/git-env.sh` is missing, the hook warns and **skips** `check-commit`
     (the commit itself fails open, like a missing `rules.sh`): running
     it unisolated is the hazard itself.
  2. `test/lib.sh` clears the list when sourced, so a single case run by
     hand is covered too, and `sandbox_guard` refuses loudly if one is set
     again, the same way it refuses a real `HOME`.
- **Never cleared:** anything outside the list: the git identity
  (`GIT_AUTHOR_*`/`GIT_COMMITTER_*`), `GIT_CONFIG_GLOBAL`/`GIT_CONFIG_NOSYSTEM`,
  `GIT_EXEC_PATH`, `GIT_SSH*`, `GIT_TERMINAL_PROMPT`, `GIT_TRACE*`,
  `GIT_EDITOR`, `CLAUDE_WORKFLOW_GUARDRAILS_OFF`. `GIT_CONFIG_PARAMETERS`
  and `GIT_CONFIG_COUNT` *are* cleared: they carry the outer command's
  `git -c` settings, which belong to the outer repo.
- **Accepted cost:** a `check-commit` that inspects *staged* content during a
  partial or `-a` commit sees the real index, not git's temporary one. No
  known `check-commit` does this; a deliberately named variable can carry the
  path if one ever needs to.
- **Violated when:** a second copy of the list appears (in the hook, the
  test library or a test case; S168 checks this), or the hook clears the
  variables in its own process instead of the `check-commit` child's.
- **Rejected:** a static list only (misses future git variables); a runtime
  list only (degrades silently if the command fails); clearing in
  `test/run.sh` (misses a single case run by hand); clearing in `check`
  (doesn't reach an adopter's own `./check`); putting the functions in
  `hooks/rules.sh` (that file holds guard rules and messages, not test
  isolation).

### A20 — The hook change is recorded in `CHANGELOG.md`, not `CHANGES.md`
Adopters get the fix with no action of their own: `hooks/pre-commit` is a
symlink into the shared checkout, and `lib/git-env.sh` sits next to it.
`CHANGES.md` is for "something a project must make its own choice about",
and its grammar has no entry shape that asks nothing (an entry without a
question is either pending for every adopter or seeded as `yes`). The
precedent for an automatic hook change (#263, `./check` wired into
`pre-commit`) is a `CHANGELOG.md` line. Exception: a project that kept its
own pre-existing `pre-commit` hook (S51) does not get the fix.


### Issue #378 — the commit-time check

`hooks/pre-commit` ran the project's full `./check`, test suite included, on
every commit: about 90 s here, so a red-first commit (the failing test
committed before the fix, `tdd-seams`) was refused, and a hanging `./check`
blocked indefinitely. Numbering continues after A19/A20.

### A21 — The commit-time check is declared by an executable `check-commit`
- **The file is the declaration.** An executable `check-commit` at the
  project root is the opt-in; a project that never heard of it has none. It
  is a different file from `check`, so an adopter whose `check` ignores its
  arguments can never be run in full by accident. The hook passes no
  arguments, runs it from the project root with git's repo-local variables
  cleared (A19).
- **Three states, nothing parsed:** (1) `check-commit` executable: run it
  under the budget (A22), block on non-zero and show its output; (2) no
  `check-commit` but an executable `./check`: run nothing, print one line
  (`pre-commit: no check-commit declared; the full ./check runs in CI (see
  CHANGES.md ci-commit-check).`); (3) neither: the existing `no executable
  ./check` warning.
- **This repo's declaration:** root `check-commit` runs `check --no-tests`
  with `CHECK_SKIP_SHELLCHECK=1`. Measured (QA): shellcheck is 23-25 s of
  `check --no-tests` on an M2, which exceeds the 30 s budget; it is
  warn-only (never fails `check`), so it has no gating value at commit time
  and is skipped there. `./check` itself still runs it.
- **`check-convention`** lists `check-commit` as an optional third fixed
  name. `adopt.sh` does not scaffold it (scaffolding turns an opt-in into a
  default). The hook does not read `WORKFLOW-ADOPTION.md`: the file is the
  switch, the answer records the decision.
- **Rejected:** `./check --no-tests` from the hook (an adopter's `check`
  may ignore the flag and run in full); a command string in a config file
  (the hook would execute free text); `git config` (per clone, unversioned);
  driving it from the adoption answer (couples the hook to the parser); the
  names `check-quick`/`check-fast` (name a property that silently erodes).
- **Violated when:** the hook invokes `./check` at commit time in any state,
  or passes arguments to `check-commit`.

### A22 — A 30 s budget, enforced portably, where a timeout fails open
- **Constant:** `COMMIT_CHECK_BUDGET="${COMMIT_CHECK_BUDGET-30}"` (default only when unset: an empty value is rejected) in
  `hooks/pre-commit`, overridable from the environment for tests.
- **Mechanism (bash 3.2, no `timeout`/`perl`):** `set -m` so each background
  job has its own process group; `check-commit` runs in one, a watchdog
  (`sleep $budget; touch flag; kill -TERM -- -pid`) in another; the hook
  `wait`s, then kills the watchdog's group (so the orphaned `sleep` dies
  too). The flag file tells a timeout apart from a real failure. The group
  kill reaches `check-commit`'s children and grandchildren.
- **KILL fallback:** the watchdog sends TERM, waits a 2 s grace, then KILL to
  the group, so a check that ignores TERM cannot hang the commit. Because
  the watchdog is stopped as soon as the leader dies, the hook also KILLs
  the group after the `wait` whenever the flag is set: a grandchild that
  ignores TERM outlives its leader otherwise.
- **Budget validation:** `COMMIT_CHECK_BUDGET` must match `^[1-9][0-9]*$`.
  Anything else (empty, 0, negative, non-numeric) blocks the commit with a
  message naming the variable, before `check-commit` runs: a bad value would
  otherwise make `sleep` fail at once and read a real failure as a timeout.
- **On timeout:** the commit goes through with one warning naming the budget
  and CI. "Couldn't verify" is not "verified red" (the same distinction the
  hook makes for a missing `rules.sh`). The warning on every commit is the
  visible signal against a growing subset. This retired the PRD debt row
  about `./check` having no timeout (#263).
- **Rejected:** GNU `timeout`/`gtimeout` (not on stock macOS); `perl -e alarm`
  (extra dependency, kills only the direct child); no timeout (leaves the
  hang).

### A23 — Gate placement
| Point | Runs | Change |
|---|---|---|
| `pre-commit` | branch guards, then the declared `check-commit` | the `./check` call is removed |
| `pre-push`, `push-after-commit`, SessionEnd push | no check | none |
| CI (`ci.yml`) | full `./check` on PR and on push to `main` | none |
| merge guard (`check_ci_guard`) | refuses on failing or pending CI | none |

The adopter entry is `CHANGES.md` `ci-commit-check` (Default `question`,
`Applies if: has-check-command`), plus a `CHANGELOG.md` line. This repo
answers it `yes` in its own `WORKFLOW-ADOPTION.md`.

---

# Architecture decision — Multi-agent workflow adoptability (#369)

**Decided on 2026-10-01.** The five-role pipeline (v0.2.0) was only usable
inside this repo: the role contracts lived under `wip/`, which `adopt.sh`
does not install, and `CHANGES.md` had no entry to ask adopters. The
decisions below make it adoptable as an opt-in.

**Numbering.** A14 and A15 are #369's, continuing the multi-agent series
(A4-A13 in `wip/multi-agent-development/ARCHITECTURE-MULTI-AGENT-WIP.md`)
rather than this file's own A1-A3. #371's decisions follow as A16-A18. Together
the two fill the A14-A18 range reserved in the #377 section above; nothing
collides and nothing is renumbered.

### A14 — The `role-contracts` skill is the pipeline's sole adopter-facing Interface; the WIP documents are provenance, not dependencies
- **Module / Interface:** `skills/role-contracts/SKILL.md` is the Module; its
  Interface is the text a dispatcher quotes. It must be complete with only
  installed skills behind it (Locality: an adopter never opens the clone to
  run a role) and must not re-implement what another installed Module owns
  (Depth: one definition per fact).
- **(a) Pointers.** `vendor/grilling/...` and `vendor/codebase-design/...`
  become the installed skill names (`grilling`, `codebase-design`).
  Every pointer to the WIP design documents collapses into one Provenance
  paragraph: decisions are cited by id, and their sources live in the clone
  `SPEC_DRIVEN_GUARDRAILS_DIR` points at. Guardrails issue numbers are
  written `TiesL/spec-driven-guardrails#n` or dropped, because a bare `#n`
  links to the adopter's own issue.
- **(b) Single definition.** The skill does not restate the merge marker or
  the `model-record` marker; it names the obligation and points to
  `pre-merge-review` and `model-choice`. This is also what keeps S28 (the
  merge marker is defined in exactly one skill) true now that the skill is
  under `skills/`.
- **(c) "Running the pipeline."** One short section: a stage / role / label /
  `stage=` table (the same order and labels `role-label-staleness.sh` checks,
  asserted by S160), that every role takes part in every change, and the
  idempotent `gh label create` command for the five `role:*` labels.
  *Amended by A16 (#371):* the table moved to the skill's `ORCHESTRATOR.md`,
  the single home of the run rules; this section points to it.
- **(d) Opt-in guard** in the skill's `description` and first line: apply it
  only when the project's `WORKFLOW-ADOPTION.md` answers
  `process-multi-agent-roles` yes.
- **(e) Decision-maker by role** ("the project's human decision-maker"), not
  by person.
- **`adopt.sh` stays offline.** Creating labels needs `gh`, credentials and
  network, so it is part of what answering *yes* means (as with
  `process-issue-tracking`), not something `adopt.sh` does.
- **Violated when:** a pointer in the skill resolves only inside this repo (a
  `vendor/` or `wip/` path, or a bare `#n`), or the skill carries a second
  literal copy of a marker another skill defines (S158, S160, S28).
- **Revisit when:** a second adopter runs the pipeline and reports a step the
  skill does not cover; then promote that step from the WIP documents. Do not
  copy more beforehand.

### A15 — The three evidence scripts' clone-root paths are a supported, read-only Interface for adopters
- **Decision (the human accepted option A on #369):**
  `$SPEC_DRIVEN_GUARDRAILS_DIR/{compliance-evidence,role-label-staleness,classify-review-depth}.sh`
  are invoked with the adopted project's checkout as the working directory.
  They stay at the clone root: not copied, not installed, not wired into any
  `check` or CI. All three address `repos/{owner}/{repo}` through `gh`'s own
  placeholder, resolved from the working directory's remotes, so they report
  on the adopter's repo (S161).
- **Consequence:** moving or renaming them is now a breaking change for
  adopters. `pre-merge-review` already sent every adopter to
  `./classify-review-depth.sh`, a path that did not exist; it now uses
  `$SPEC_DRIVEN_GUARDRAILS_DIR/classify-review-depth.sh` (S162).
  This narrows `F34`-`F36`'s "this repo only" placement.
- **Violated when:** a script starts resolving its target repo from its own
  location, or gains a write path.
- **Revisit when:** `SPEC_DRIVEN_GUARDRAILS_DIR` being unset proves a real
  failure source; then move the scripts into a skill directory (precedent:
  `skills/pre-merge-review/model-record-gate.sh`).
- **Known limit:** with several git remotes `gh` may need `gh repo set-default`;
  the README, the `role-contracts` skill and the `CHANGES.md` entry say so.

---

# Architecture decision — Sessions apply the multi-agent pipeline automatically (#371)

**Decided on 2026-10-01, amended 2026-10-02.** #369 made the pipeline
adoptable, but nothing a session loaded told it to *run* the pipeline: a
session in this repo did a whole work item alone, playing every role. A
process that rests on an agent remembering prose doesn't happen (#238/#241).
The decisions below make activation conditional and mechanical, make a
role-played run detectable before merge, and stop future workflow changes
from shipping as prose no session loads. Continues A14/A15 (#369).

### A16 — Activation is a conditional SessionStart injection with a single source
- **Source of truth:** `skills/role-contracts/ORCHESTRATOR.md` (about 30
  lines) is the only place the run rules are stated: work item vs. not, the
  announce / `role:product` / dispatch-Product start, the stage → role →
  label → `model-record` table, fresh (never `fork`) dispatch with every
  prompt starting `ROLE SESSION: <role>`, the human override record, "can't
  dispatch: stop and ask", and resume from the latest evidenced stage
  (`role-label-staleness.sh`). Its first line tells a role session the file
  does not apply to it. `SKILL.md` points to it (A14(c) amended).
- **Channel:** the clone-root `session-context.sh <project>`, a third
  `SessionStart` command resolved through the project's
  `.claude/settings.json` symlink (`readlink`), like `pending-changes.sh`. For
  every `CHANGES.md` entry the project answers yes whose `Reaches session`
  field declares `session-context: <path>` (A17), it prints that file
  verbatim. A no, unanswered or not-applicable row prints nothing (AC3 by
  construction). The file is read from the clone on every run, so a later
  release reaches the next session without re-adoption (AC11). A missing
  declared file warns on stderr; the script always exits 0.
- **One yes rule:** `answered_yes <project> <id>` in `lib/changes.sh`
  (Answer column only, `WORKFLOW-ADOPTION.md` before `WORKFLOW-ADOPTIE.md`,
  `yes`/`ja`, pre-rename ids) replaces `adopt.sh`'s hard-coded
  `issue_tracking_answered_yes`. Callers: `adopt.sh`, `session-context.sh`,
  `model-record-gate.sh` and the merge guard.
- **`CLAUDE.md` drift:** `session-context.sh` (not the hook JSON, which stays
  a thin dispatcher) warns when the project's `CLAUDE.md` is not a symlink to
  the clone's `WORKFLOW.md`, with "run adopt.sh again".
- **This repo:** no special case (AC2); it answers its own row yes.
- **Platform facts (probed once, Claude Code 2.1.287, headless `-p`):**
  `SessionStart` output reached the top-level session and not a fresh
  `general-purpose` subagent it dispatched; the hook fired again with
  `source` `resume` (and the new text reached the resumed session) and with
  `source` `compact`. Not probed: interactive mode, a `fork` dispatch, and
  whether the post-compaction context keeps the text.
- **Rejected:** text in `WORKFLOW.md`/`CLAUDE.md` (unconditional, loads into
  role sessions too), a `UserPromptSubmit` hook (fires on every prompt, can't
  tell a work item from a question), a skill-description trigger
  (probabilistic, the failure itself), user-level text (per user, not per
  project), a `PreToolUse` `Edit|Write` block until Product is evidenced
  (needs `gh` on every edit, fires inside role sessions; held as the revisit
  trigger below).
- **Violated when:** the run rules appear in a second file, or the injection
  fires for a row that isn't yes (S177-S180).
- **Revisit when:** A18 flags two or more role-played runs without an
  override after #371 ships; then consider the `PreToolUse` block.

### A17 — Every `CHANGES.md` entry declares how it reaches a session
- **Field:** a required `**Reaches session:**` on every entry, one or more
  comma-separated values from a closed vocabulary (`none`,
  `always-loaded: <path>`, `session-context: <path>`, `hook: <path>`,
  `gate: <path>`). The vocabulary is documented once, in `CHANGES.md`'s
  preamble; `reaches_session_values`/`reaches_session_invalid` in
  `lib/changes.sh` read and enforce it (`session-context.sh` uses the same
  parser).
- **Machine-checked by `./check`** (§3a2): the field is present, each value
  is in the vocabulary (`none` stands alone), each path exists, and each path
  is named in at least one `test/cases/*.sh`. Failures name the entry, the
  field and the culprit.
- **Reviewer judgment, deliberately not mechanised:** whether `none` is
  honest for a given *Yes means*. No prose grep of *Yes means*.
- **Not a meaning change:** no **Meaning version** bump. All existing
  entries were backfilled at once, no exempt list (human decision).
- **Violated when:** an entry ships without the field, or a declared path
  isn't exercised by a test (S181, S182).

### A18 — Role-session guard and role-play detection, enforced at merge
- **Recursion (AC5):** three layers: the injection reaches only the
  top-level session (A16's probe), roles are dispatched fresh and never
  forked, and `ORCHESTRATOR.md`'s first line excludes any prompt starting
  `ROLE SESSION:`. No `SubagentStart` hook.
- **Override record (AC6):**
  `<!-- pipeline-override: decided-by="..." scope="single-session|skip=<Stage>" reason="..." -->`,
  live text (not fenced, not a code span, not a blockquote, same `live_text`
  rule as `compliance-evidence.sh`, copied verbatim and kept identical by
  S153), every field non-empty, `scope` from that closed list. Searched in
  the same sources as the markers. `single-session` waives every finding;
  `skip=<Stage>` waives only that stage's absence.
- **Detection (AC9):** `model-record-gate.sh`, only when `answered_yes`
  holds for the project it runs in, prints one line per finding starting
  `role-played: `: several different stages' live markers in one text
  (comment, review or PR description), or any of the five stages missing.
  The existing output is unchanged; exit stays 0. The comment and review
  calls frame each body with U+001E, after removing that byte from the body
  (so a body cannot forge a boundary and split one role-played text into
  several), so one text can be told from the next. Since #392 (round 4 of
  the PR #397 review) this framing applies in every project, because the
  marker parser needs it too (A24). A closing issue that
  can't be read skips the role-play check (a missing Discovery could be a
  lookup failure).
- **Amendment (2026-10-02, kept by the human):** the merge guard enforces it.
  `check_merge_guard` in `hooks/git-guardrails` gains a last step,
  `check_role_play_guard`: only when the project answers yes, it runs the
  clone's `skills/pre-merge-review/model-record-gate.sh` on the PR and
  refuses `gh pr merge` on any `role-played: ` line. One owner: the gate
  computes the rule, the guard reads the prefix. Fails open without `gh`,
  network, a resolvable PR number, or the lib/gate in the clone. Same gate
  as the review-marker check: the same `no` on `quality-review-before-merge`
  and `CLAUDE_WORKFLOW_MERGE_GUARD_OFF=1` turn it off (S186).
- **AC12:** `model-choice`'s "No behavior change" section is rewritten
  (single session is the norm only where the row isn't yes), and the gate's
  header no longer claims one session may do every stage (S184).
- **Accepted limit:** a session that deliberately forges five separate stage
  comments is not detected. Same non-adversarial trust model as every gate.
- **Violated when:** a role-played run without a valid override merges in an
  opted-in project with `gh` available, or a project that didn't answer yes
  sees a new finding or block (S183, S186).

---

# Architecture decision — Review at least as capable as Implementation (#392)

**Decided on 2026-10-03.** #244's different-model requirement for the Review
stage is reversed (human decisions on #392): the floor is Review's model and
effort, together, at least as capable as Implementation's. A24 and A25 are
the next free numbers after A23.

### A24 — The Review floor and its recorded judgment, `floor-basis`
- **Rule:** Review's model and effort, taken together, are at least as
  capable as Implementation's recorded model and effort. Among the
  combinations that clear that, pick the cheapest. A different model is not
  required. No model or tier is named anywhere.
- **Attribute:** `floor-basis="<one sentence>"` on the Review `model-record`
  marker, required on **every** Review marker, not only same-model ones:
  same-model detection inherits false "different" verdicts from short
  aliases (see the PRD debt row), so a conditional rule would skip exactly
  the reviews that were wrongly classified. Free text, not an enumeration:
  for the same model an enumeration would repeat what the gate computes; for
  different models it would be a bare claim with no reason. The only
  forbidden character is a double quote, which ends a value; `>`, `<`, `--`,
  even `-->` and a newline inside a quoted value are text, and the marker
  ends at the first `-->` outside quotes (the review of PR #397 found that
  the old `[^>]*-->` grammar made a `>` in `floor-basis` hide the whole
  marker from both scripts). A **malformed** marker (a quote anywhere but
  right after `name=`, text glued to a closing quote, a value not closed in
  its own comment, a `<!--` outside a value, or no closing `-->` in its own
  comment) is never read and
  never swallows a later marker: there is no fallback to the first `-->`,
  and the scan resumes right after its own `<!--`. The gate names it
  (`model-record: a stage=<Stage> marker is malformed and was ignored`);
  in the collector it is ignored when a well-formed marker of that stage
  exists and makes the gate `indeterminate` when none does; in
  `role-label-staleness.sh` it is a malformed marker (`indeterminate`, its
  AC6 rule). **Comment boundaries are respected:** all three callers pass
  the parser each comment, review, issue comment and description followed
  by U+001E, after removing that byte from the body itself (sanitised, not
  rejected: rejecting a body would hide its markers, and removing a
  non-printing control byte changes no Markdown meaning). Reaching that byte
  before the closing `-->` makes a marker malformed, so an unclosed quote or
  a missing `-->` stays in its own comment however the next comment starts
  (round 4 of the PR #397 review). The name does not
  end in `model=` or `effort=`, which the field extraction would otherwise
  capture.
- **What the gate does (`model-record-gate.sh`):** it reads live text only
  for its stage-presence and Review-floor checks: each body goes through
  its own copy of `live_text()` first, like the collector and
  `role-label-staleness.sh`, so a marker quoted in a code span, a fence or
  a blockquote is not a record (a Review marker only inside a fence is a
  missing stage); an indented code block is not stripped, in any of the
  three (PRD debt row). If `live_text()` fails, the gate prints a
  `model-record:` finding and skips these checks. The role-play check
  (A18) is unchanged (#400). The #244 same-model
  finding is removed. A missing, empty or unquoted `floor-basis` on the
  **latest** Review marker gives `model-record: stage=Review marker has no
  floor-basis ... (#392)`; when present, the text is never checked. The
  finding uses the `model-record:` prefix, never `role-played: `, so the merge
  guard (A18) is unaffected.
- **`compliance-evidence.sh` gate 2:** different models are
  `unverifiable-from-artifacts` (the capability ordering is not machine-
  checked; the `floor-basis` is quoted for a human to weigh); the same model
  with both efforts known is `evidenced` when Review >= Implementation and
  `not-evidenced` when lower; an unknown effort is `indeterminate`. Both
  same-model verdicts sit behind the #302/#336 lookup-failure guard (an
  unread marker can overturn either; Architect ruling on AC6). The
  inter-issue conflict key is the normalized model plus the effort.
- **`same-model-exception`:** ignored completely by both scripts, and it does
  not stand in for `floor-basis`. The documentation keeps one "legacy,
  ignored" mention for one release, then it goes.
- **Violated when:** a script ranks two different models, a script verifies
  the `floor-basis` text, or a #392 finding uses the `role-played: ` prefix.

### A25 — Effort scale and the shared model-record module
- **Scale:** low < medium < high, case-insensitive on the quoted
  `effort="..."` value: exactly the values in use. Compared only when both
  models normalize equal and both efforts are known. A missing, unquoted or
  unknown value (`unknown`, `session-default`) makes no claim: no finding in
  the gate, `indeterminate` in the collector. A role that does not know its
  effort records `effort="unknown"`. A short alias and its full id normalize
  as different models: no effort comparison, gate 2 reports
  `unverifiable-from-artifacts`, never a pass.
- **`lib/model-record.sh`** (sourced, bash 3.2), used by the gate, the
  collector and `role-label-staleness.sh`:
  `normalize_model` (moved unchanged, #268; the duplicate copy is gone),
  `effort_rank <value>` (0, 1, 2, or nothing), `marker_attr <marker> <name>`
  (the quoted value; the marker is tokenized, so text inside another value
  such as `beats model=` or a lookalike name such as `reviewer-model` is
  never read as an attribute), `marker_find <Stage> <text>` (every
  well-formed marker of a stage, the one marker grammar: quote-aware end at
  the closing `-->`) and `marker_scan <text>` (every marker, well-formed or
  malformed, with its stage token). All three scripts, and gate 1 of the
  collector, read markers only through these. The parser's awk programs run
  under `LC_ALL=C` (every delimiter is ASCII; under a UTF-8 locale macOS awk
  aborted on a multibyte character right after `stage=`), and a failure is
  never silent: the function prints nothing, says so on stderr and returns
  non-zero; the gate then prints a `model-record:` finding, the collector's
  gates 1 and 2 go `indeterminate`, `role-label-staleness.sh` goes
  `indeterminate`. The gate sources it via
  its symlink-resolved clone path, like `lib/changes.sh`; it fails open
  without it. The collector, at the repo root, sources `lib/` next to itself.
- **Meaning version 3** of `quality-review-before-merge` (`CHANGES.md`), with
  the gate named in `Reaches session:`; adopters who answered yes are asked to
  re-confirm.
- **Violated when:** either script carries its own copy of `normalize_model`
  or its own attribute extraction.

### A26 — Markers are produced by one command; an unreadable field is a finding (#402)
- **Why:** the dry run on a scratch repo (release head fa1beae) showed
  dispatched roles writing unquoted markers and an orchestrator typing a
  quoted `stage="..."`; both are unreadable, and the gate was silent.
- **`marker_emit <Stage> <model> <effort> [<floor-basis>]`**
  (`lib/model-record.sh`, bash with `local LC_ALL=C`): prints exactly one
  line, `<!-- model-record: stage=<Stage> model="<model>" effort="<effort>"[ floor-basis="<sentence>"] -->`,
  or prints nothing, gives a reason on stderr and returns 2. It refuses: a
  stage other than the five names (emitted bare); a model that is empty,
  over 200 characters or not one token of `[A-Za-z0-9._:@/+-]` (a model id:
  no space, quote, `=` or control byte); an effort other than `low`,
  `medium`, `high`, `unknown`; a floor-basis missing or blank on Review or
  present on another stage (A24); a floor-basis with a double quote or a
  control byte (newline, tab, U+001E, ...) or over 500 bytes. Nothing else:
  `>`, `<`, `--`, `-->`, `<!--`, `=` and non-ASCII are text in a quoted
  value (the maintainer's #392 decision), so the emitter is never stricter
  than the grammar for a floor-basis. This replaces the first A26 draft,
  which also refused `-->` and `<!--` there (GitHub may then show the text
  after a `-->` in the rendered comment; the marker still reads back).
- **Safety: the round trip.** Before printing, `marker_emit` parses its own
  line with `marker_find`, `marker_scan` and `marker_attr`; unless the line
  reads back as exactly one well-formed marker of that stage with the same
  model, effort and floor-basis, it is refused, never printed.
- **Wrapper:** `skills/pre-merge-review/model-record-emit.sh --stage <Stage>
  --model <id> --effort <e> [--floor-basis <sentence>]`, next to the gate.
  It only parses flags (unknown, missing, repeated or value-less flag, or a
  positional argument: exit 2); the rules live in `marker_emit`. It finds
  the lib from its own real directory (`pwd -P`), so it works through an
  adopted project's symlinked `.claude/skills`; without the lib, exit 3.
- **Who fills what:** the orchestrator gives the command in each dispatch
  prompt with `--stage` and `--effort` (`unknown` when it can't set or find
  out the effort) and names the model it requested; the role adds `--model`
  with its own exact id (the Reviewer also `--floor-basis`) and pastes the
  output unchanged as the first line of its report (human decision on
  #402). A role whose prompt has no command runs the wrapper itself and
  says so (`role-contracts`, "Shared").
- **One owner of the format:** `model-choice` ("Machine-readable form",
  "Marker grammar") holds the templates and the grammar; `ORCHESTRATOR.md`
  restates no grammar, `pre-merge-review` points to `model-choice`.
- **The gate (safety net for hand-typed lines):** for the latest marker of
  each of the five stages, an unquoted, empty or missing `model` or
  `effort` is one `model-record:` finding per stage and field
  (`effort="unknown"` is quoted: no finding); a malformed marker of any
  stage, including an empty or quoted stage (shown as `stage=?`), is named.
  Exit stays 0, the prefix is never `role-played:`, so the merge guard and
  A18 are unchanged; the collector already said `indeterminate` here.
- **Violated when:** a skill or the orchestrator carries a second copy of
  the marker template or grammar, the emitter prints a line the parser
  does not read back, or a #402 finding uses the `role-played:` prefix.

# Architecture decision — Process rules from the #405 meta review (epic #408)

**Decided on 2026-10-04.** The meta review of the #369/#371/#392/#402 epic
(#405) found a Reviewer agent continued through `SendMessage` across PR
#397 rounds 3 to 5 and then for #403, while ORCHESTRATOR.md forbade only
`fork`. A27 to A30 are the next free numbers after A26 (A27 #414, A28 #410,
A29 #415, A30 #409); each is recorded in its own item's PR.

### A27 — Every Review round is a fresh Reviewer dispatch, briefed from artifacts (#414)
- **Review round:** one Reviewer dispatch that ends in exactly one findings
  comment on the PR, for one head SHA, opening with a Review `model-record`
  marker; verdict approve or request-changes. Lens-Adapters belong to the
  round of the Reviewer that started them. #410 and #415 use this term.
- **Fresh dispatch:** a new agent started by the dispatch tool with a type
  other than `fork`. Not fresh: `SendMessage` to an existing agent, the
  dispatch tool's `fork` type (inherits the orchestrator's context), or
  continuing an agent that already posted a round. That `fork` is not
  `pre-merge-review`'s `context: fork`, which means an isolated context;
  rule text names "the dispatch tool's `fork` type" so the two are not
  confused.
- **Rule (three places):** the Reviewer contract (`role-contracts`
  SKILL.md), ORCHESTRATOR.md's Dispatch paragraph and `pre-merge-review`
  state that every Review round, a re-review after a fix commit included, is
  a new dispatch of a fresh Reviewer, never continued by `SendMessage` or the
  `fork` type. Nothing here decides whether other roles may be continued
  (#412).
- **Brief from artifacts:** the PR number, head SHA and diff command, the
  work-item issue, a link to the previous findings comment with its open
  `finding:` slugs, and the `finding-carryforward-gate.sh` command. Never the
  earlier Reviewer's conversation, a summary of it, or the orchestrator's
  paraphrase. Carried-forward findings are inputs the new Reviewer
  re-checks against the new head, not memory; the carry-forward gate is
  unchanged.
- **Stated limit:** no GitHub artifact shows that two rounds came from
  different agent instances. Every comment comes from the same account, two
  rounds by one model carry identical markers, an agent id in a comment is
  self-reported, and the platform transcripts that hold agent ids are local
  to one machine. So freshness is not machine-checked and no check claims it.
- **Fallback, recorded not verified:** the orchestrator's **Pipeline log**,
  one comment per work-item issue that it writes and edits, never carrying a
  `model-record` marker, with one line per dispatch written at dispatch time
  (stage, round for Review, the agent id the dispatch tool returned, model
  requested, effort observed afterwards; how effort is observed is #413's).
  Before asking for a merge, the orchestrator runs a self-check, "every Review
  round in the pipeline log has its own agent id, and no message went to an
  earlier Reviewer", and records its result in that log. It is a recorded
  self-check, not a pass. #410 and #415 add their lines to this one list.
- **Rejected:** an agent-id field on the `model-record` marker (the marker
  format is #411's, and a self-reported id there proves no more than in the
  log); a script comparing the log's ids (it would check the orchestrator's
  record against itself).
- **Violated when:** a later round's Reviewer is reached by `SendMessage` or
  the `fork` type, a brief carries an earlier Reviewer's conversation or a
  paraphrase of it, or the pipeline log is missing an agent id for a Review
  round.
- **Revisit when:** the platform exposes an agent instance id in an artifact
  CI can read; then the self-check can become a check.

### A28 — Findings carry a class; design defects loop back to the Architect, then QA (#410)
- **Why:** on PR #397 every Reviewer finding of a design defect (free text
  inside a parsed marker) was patched in code, often with the Reviewer's own
  suggested fix, over five rounds; none went back to the Architect (#405
  W1, pilot-3 recommendation 6).
- **Class, one per finding:** a new **Class** field in the shared finding
  structure (`role-contracts` SKILL.md), next to Category (Category is the
  kind of defect; Class is where the fix starts), with these routes:
  - `design`: the cause is a decision about structure (a format, a contract
    or Interface, a Seam, a parsing approach, where a responsibility lives,
    a data shape); a correct code fix would leave that decision in place.
    Architect, then QA, then Developer, then a fresh Reviewer (A27).
  - `code`: the implementation departs from a sound design; the fix changes
    no Interface or Seam the Architect decided. QA (a red test), Developer,
    fresh Reviewer.
  - `test`: a test does not falsify what it claims. QA, Developer, fresh
    Reviewer.
  - `spec`: an acceptance criterion or the PRD is wrong, ambiguous or
    missing. Product, the Architect if the design is affected, QA,
    Developer, fresh Reviewer.
  Four classes because each maps onto the one role that owns the fix; with
  only design and code, test and spec defects get patched as code. The class
  is prose, not a `finding:` slug prefix (the slug belongs to the marker
  design, A31-A37).
- **Never a fix:** a finding names the defect, its class and a **Falsifying
  check** (the observable condition a correct fix must meet), never a fix, a
  patch or code. No exception for typo-level findings (maintainer default,
  #408). The same applies to findings from QA and the Developer. The
  orchestrator never relays a suggested fix text as a decision; the next
  role's brief links the findings (A27).
- **Who classifies:** the reporting role proposes; the orchestrator never
  downgrades a class. A doubted or missing class goes to the Architect, who
  may record "not a design defect, route as code".
- **From any stage:** a Developer or QA that finds a design defect stops the
  change, saves the attempted patch (A12) and reports it with class
  `design`; it is routed like any other finding.
- **Two-round trigger:** a Review round (A27, A37) counts when it reports at
  least one open finding of severity medium or high, new or carried. Two
  consecutive counting rounds on one PR, any component, make the
  orchestrator dispatch the Architect for a redesign step before any
  Developer fix. The Architect posts a comment with a Planning marker on the
  PR and may conclude that no design change is needed. Counting starts again
  after that recorded step.
- **Override:** a maintainer instruction to patch a design defect in code
  waives a contract rule, so A29 (#415) applies: one Architect pushback, a
  numbered human decision naming this rule and linking the pushback, and an
  Architect risk note in A29's format. No format or marker is defined here.
- **Self-check lines** in A27's "Before asking for a merge" list: no
  design-class finding was fixed without an Architect step before the fix
  commit; the two-round trigger did not fire, or its Architect step is on
  the PR.
- **Stated limit:** class and severity are judgments. Severity is prose, not
  in any marker, so no script can tell whether a round counts. A script can
  only show that the route left evidence.
- **`review-rounds.sh <pr> [<issue>]`** at the clone root, read-only, with
  the evidence scripts' Interface (A15): run by path, needs `gh`, REST only,
  never writes, never blocks. It prints `review-round: <n> at=<timestamp>`
  per round in time order, `planning-after: <n>` for a round followed by a
  Planning marker on the PR or the given issue (reported against the latest
  round before it), `review-rounds: <N>`, and a fixed line that severity is
  not machine-readable. A failed fetch prints a warning on stderr, no
  `review-rounds:` line, exit 0. A round is A37's: one body (PR comment or PR
  review) whose first marker candidate is `stage=Review`, well-formed or
  malformed, plus legacy bodies with only `pre-merge-review:done`; "time
  order" is `created_at`/`submitted_at`. The round logic is one function,
  `rr_rounds`, so #426 can move it to `lib/review-rounds.sh` unchanged; it
  reads markers only through `lib/model-record.sh` (A25), never `finding:`
  slugs. It is not a gate and not wired into the merge guard: the trigger
  turns on severity, which it cannot see. The orchestrator runs it in its
  self-check.
- **Rejected:** a `severity=` attribute on `finding:` markers (a marker
  format change, #411's); a "same component" trigger (a component judgment
  the orchestrator would make alone); wiring the round count as a gate (a
  false block on rounds with only low findings).
- **Violated when:** a finding carries a fix or has no class; a design-class
  finding is fixed with no Architect step before the fix commit; a Developer
  fix follows two consecutive counting rounds with no Architect step; a
  second copy of the round logic appears outside `rr_rounds`.
- **Revisit when:** finding severity becomes machine-readable; the trigger
  can then be counted by `review-rounds.sh`.
