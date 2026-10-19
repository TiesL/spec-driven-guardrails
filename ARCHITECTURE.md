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
- **Override record (AC6), amended by #427 (A31a):**
  `<!-- pipeline-override: decided-by="..." scope="single-session|skip=<Stage>" reason="..." -->`,
  one whole line starting in column 0 outside quoted text (fences, spans,
  blockquotes and indented code). Values may not contain `"`, `<`, `>` or a
  control character. The literal scope substitutes one of the five stage
  names for `<Stage>`. The strict `rec_scan_bundle`/`rec_field` reader owns
  grammar; decided-by and reason must be non-blank, scope from that closed
  list. Searched in the same sources as stage records. `single-session`
  waives every role-play finding; `skip=<Stage>` waives only that stage's
  absence. Invalid live overrides give one near-miss and waive nothing.
- **Detection (AC9):** `model-record-gate.sh`, only when `answered_yes`
  holds for the project it runs in, prints one line per finding starting
  `role-played: `: several different stages' live markers in one text
  (comment, review or PR description), or any of the five stages missing.
  Only strict ok records supply presence and multi-stage evidence; quoted
  records count as nothing and inline candidates are named near-misses.
  Exit stays 0. The comment and review
  calls frame each body with U+001E, after removing that byte from the body
  (so a body cannot forge a boundary and split one role-played text into
  several), so one text can be told from the next. Since #392 (round 4 of
  the PR #397 review) this framing applies in every project, because the
  marker parser needs it too (A24). A closing issue that
  can't be read emits `role-play-unchecked: ` and skips dependent checks;
  a genuine HTTP 404 is instead noted and ignored, leaving Discovery missing.
  Every opted-in early exit (including reader failure) emits unchecked stdout.
  The guard prints unchecked lines as warnings and near-misses as context,
  and still blocks only on `role-played: `. Both remedies are shown: re-post
  via the emitter or provide a valid override. The hook prints the
  warning; in the #430 AC3 run it appeared in the stream transcript only and
  did not reach the agent as command output (https://github.com/TiesL/spec-driven-guardrails/issues/430#issuecomment-6132587414).
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
- **Rule (effort part superseded by A33, #424):** Review's model is at
  least as capable as Implementation's recorded model; effort is no longer
  compared or recorded. Among the models that clear that, pick the cheapest. A different model is not
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
  `live_text()` (`lib/markdown.sh`, one definition since #423) first, like the
  collector and `role-label-staleness.sh`, so a marker quoted in a code span, a fence or
  a blockquote is not a record (a Review marker only inside a fence is a
  missing stage); an indented code block is not stripped, in any of the
  three (PRD debt row). If `live_text()` fails, the gate prints a
  `model-record:` finding and skips these checks; a failure on a role-play
  body is a `model-record:` finding too (#423). The role-play check
  (A18) is otherwise unchanged (#400). The #244 same-model
  finding is removed. A missing, empty or unquoted `floor-basis` on the
  **latest** Review marker gives `model-record: stage=Review marker has no
  floor-basis ... (#392)`; when present, the text is never checked. The
  finding uses the `model-record:` prefix, never `role-played: `, so the merge
  guard (A18) is unaffected.
- **`compliance-evidence.sh` gate 2:** different models are
  `unverifiable-from-artifacts` (the capability ordering is not machine-
  checked; the `floor-basis` is quoted for a human to weigh); the same model
  is `evidenced` (model-only, self-reported; as amended by A33/A33a, #424,
  the former effort comparison is gone). That same-model verdict sits behind
  the #302/#336 lookup-failure guard (an unread marker can overturn it;
  Architect ruling on AC6). The inter-issue conflict key is the normalized
  model alone (the effort part was removed by #424).
- **`same-model-exception`:** ignored completely by both scripts, and it does
  not stand in for `floor-basis`. The documentation keeps one "legacy,
  ignored" mention for one release, then it goes.
- **Violated when:** a script ranks two different models, a script verifies
  the `floor-basis` text, or a #392 finding uses the `role-played: ` prefix.

### A25 — Effort scale and the shared model-record module
- **Status: superseded by A33 (#424).** Effort left the marker and the floor; the scale, `effort_rank` and the effort comparisons below are history. The shared `lib/model-record.sh` module itself stays.
- **Scale:** low < medium < high, case-insensitive on the quoted
  `effort="..."` value: exactly the values in use. Compared only when both
  models normalize equal and both efforts are known. A missing, unquoted or
  unknown value (`unknown`, `session-default`) makes no claim: no finding in
  the gate, `indeterminate` in the collector. A role that does not know its
  effort records `effort="unknown"`. A short alias and its full id normalize
  as different models: no effort comparison, gate 2 reports
  `unverifiable-from-artifacts`, never a pass.
- **Historical shared module** (sourced, bash 3.2), then used by the gate,
  collector and `role-label-staleness.sh` (the tokenizer retired in V8, #429):
  `normalize_model` (moved unchanged, #268; the duplicate copy is gone),
  the former generic quoted-attribute tokenizer
  (the quoted value; the marker is tokenized, so text inside another value
  such as `beats model=` or a lookalike name such as `reviewer-model` is
  never read as an attribute), the former per-stage lookup (every
  well-formed marker of a stage, the one marker grammar: quote-aware end at
  the closing `-->`) and the former marker classifier (every marker, well-formed or
  malformed, with its stage token). All three scripts, and gate 1 of the
  collector, read markers only through these. The parser's awk programs run
  under `LC_ALL=C` (every delimiter is ASCII; under a UTF-8 locale macOS awk
  aborted on a multibyte character right after `stage=`; the locale guarantee
  as a whole is the structural rule of A32c, below), and a failure is
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

### A32c — The locale guard is structural (#423, round 3 of PR #443)
- **Why:** review rounds 1 and 2 each found one more text command that ran in
  the ambient locale on text from GitHub. A per-site rule without a single
  oracle makes every round find the next unpinned site; `local LC_ALL=C` in a
  bash 3.2 function does not reach a child process, so it is not the guarantee.
- **Rule:** the four scripts that read text from GitHub
  (`skills/pre-merge-review/model-record-gate.sh`, `compliance-evidence.sh`,
  `role-label-staleness.sh`, `review-rounds.sh`) run `export LC_ALL=C` as their
  first statement after the shebang, comments and `set`, so every command they
  run, and bash's own matching, uses the C locale. The two text-reading libs
  (`lib/markdown.sh`, `lib/model-record.sh`) are sourced, so they cannot set
  process state (a subshell per function costs a fork per call on macOS).
  Every external text command in them (awk, grep, sed, tr, cut, sort, uniq)
  carries the per-command prefix `LC_ALL=C`, and grep is always called as
  `grep -a`. The other libs (`changes.sh`, `git-env.sh`, `nfr.sh`) do not read
  GitHub text and are outside this rule. Existing per-command prefixes in the
  four scripts are redundant and stay; no new ones are added.
- **Enforcement:** S235 is a static lint (L1 exports, L2 lib prefixes, L3
  self-mutants). A class-L finding inside the guarded set is a lint defect, not
  a site to patch. S230 stays the behavioural proof, one arm per script.
- **Also decided (A32c):** a fence opened on a list item's continuation line
  and closed at column 0 is an accepted limit (follow-up #445). A32c's
  ordered-start rule is superseded by A32d below; the locale part stands.

### A32d — Revert the ordered-start rule; `ordered-item-after-paragraph` is an accepted limit (#423, round 3 of PR #443)
- **Why:** the A32c rule (an ordered item numbered above 1 after paragraph
  text is not a list-fence opener) fixed one shape and moved the error onto
  neighbours: wrapped items, lazy lines and items after a blockquote read a
  quoted marker as live. Extending a list-fence recognizer one shape at a time,
  without list-context tracking, repeats the #422 pattern. A32c's claim that
  declining an opener is "the safe direction" was false.
- **Decision:** the `_MD_AWK` program in `lib/markdown.sh` is byte-identical
  to the one reviewed at 5ea3a5b. Class-L changes (the `LC_ALL=C` prefixes and
  exports) stay. `ordered-item-after-paragraph` (shape s1) is an accepted limit
  that goes in the bad direction (a marker inside the top-level fence after
  `text` / `2. ```` reads as live); it is out of the threat model (accidental
  at most, very unlikely). Follow-up #446: quote under every plausible reading
  (union of quoting), which may also close #445.
- **Safe direction:** a marker GitHub renders as quoted must never read as
  live; over-quoting is the safe error.
- **Violated when:** a single-reading list-fence rule is added to `handle()`
  without a union or list-context mechanism.

### A26 — Markers are produced by one command; an unreadable field is a finding (#402)
- **Why:** the dry run on a scratch repo (release head fa1beae) showed
  dispatched roles writing unquoted markers and an orchestrator typing a
  quoted `stage="..."`; both are unreadable, and the gate was silent.
- **`marker_emit <Stage> <model> [<floor-basis>]`** (no effort since A33, #424; the line below shows the A26 form that carried one)
  (`lib/model-record.sh`; locale per the A32c rule, section below): prints exactly one
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
  line with the then-current stage lookup, classification scan and attribute
  tokenizer (retired by V8, #429); unless the line
  reads back as exactly one well-formed marker of that stage with the same
  model, effort and floor-basis, it is refused, never printed.
- **Wrapper:** `skills/pre-merge-review/model-record-emit.sh --stage <Stage>
  --model <id> [--floor-basis <sentence>]`, next to the gate (a legacy
  `--effort` is accepted and ignored with one stderr line, A33, #424).
  It only parses flags (unknown, missing, repeated or value-less flag, or a
  positional argument: exit 2); the rules live in `marker_emit`. It finds
  the lib from its own real directory (`pwd -P`), so it works through an
  adopted project's symlinked `.claude/skills`; without the lib, exit 3.
- **Who fills what:** the orchestrator gives the command in each dispatch
  prompt with `--stage` and names the model it requested (it no longer
  passes `--effort`: removed by A33, #424); the role adds `--model`
  with its own exact id (the Reviewer also `--floor-basis`) and pastes the
  output unchanged as the first line of its report (human decision on
  #402). A role whose prompt has no command runs the wrapper itself and
  says so (`role-contracts`, "Shared").
- **One owner of the format:** `model-choice` ("Machine-readable form",
  "Marker grammar") holds the templates and the grammar; `ORCHESTRATOR.md`
  restates no grammar, `pre-merge-review` points to `model-choice`.
- **The gate (safety net for hand-typed lines):** for the latest marker of
  each of the five stages, an unquoted, empty or missing `model` is one
  `model-record:` finding per stage (the former per-field check on effort
  was removed by A33, #424; a legacy effort attribute is ignored); a malformed marker of any
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
  `rr_rounds` in `lib/review-rounds.sh` (#426): it reads rows on stdin
  (`created_at`, source, url, body), reads records only through `rec_scan`
  of `lib/model-record.sh` (A25) and prints `R`/`P` rows of six tab separated
  fields; a failed read prints nothing and returns non-zero, never "no
  round". `finding-carryforward-gate.sh` is its second caller: it fetches PR
  comments and PR reviews over REST (no GraphQL, #318), compares each round
  with the one before it (#421), buffers its findings and fails open with a
  warning on any fetch or tool failure; the `finding:` slug reading is its
  own and never in the lib: both sides read a slug as the maximal non-whitespace
  run after `finding:` and compare it whole, so a slug is mentioned only by
  exactly that token (#453). A37b (#426): a gap (open in round k-1, not
  mentioned in round k) is cleared by any later round that mentions the slug,
  open or resolved, so the gate reports a slug iff the latest round that
  mentions it leaves it open and is not the last round, one line per slug
  ending ` (round <k>)`, k the round that dropped it. A37c (#470): the source
  decides what a body can be. In `rr_rounds` a body with source `issue` can
  only be a `P` row, never an `R` row, so an issue-comment Review record
  (the holistic review on the release epic) is no round and takes no round
  number; a Planning record on the issue keeps its `P` row against the
  latest PR round. The rule lives in `rr_rounds` alone, so both callers
  agree with no caller-side filter. It is not a gate and not wired into the merge guard: the trigger
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

### A29 — Bounded orchestrator decisions, one pushback, and an Architect risk note (#415)
- **Decision:** put a short "Decided without asking" table in
  `skills/role-contracts/ORCHESTRATOR.md`, the A16 source for run rules. Its
  Interface is a decision, rule, and log location per row. Seed it with the
  scratch-run tool, role model when the floor is clear, low-severity finding
  disposition, and conventional naming/numbering; the existing notice rule
  may be a fifth row. A row settles only a choice the contracts leave open.
  The never-list covers merges into `main`, version and meaning-version
  bumps, spec content, outward-facing actions, security trade-offs,
  departures from a role's recommendation, and contract waivers.
- **Module and Seam:** the existing orchestrator run-rule Module owns the
  table and its issue-log Interface. Its Seam remains the injected
  `ORCHESTRATOR.md`; there is no new runtime Seam or adapter. A separate
  skill would depend on optional loading and add adoption surface. Deleting
  this table would return routine choices to individual dispatches and
  maintainer questions. Keeping the rules together gives Leverage across
  work items and Locality for changes; its Depth comes from resolving
  several recurring decisions behind one short, always-read Interface.
- **Record:** a decision by rule is normal prose in a "Decisions by rule"
  section of A27's issue Pipeline log: date, row, decision, and the
  maintainer's objection deadline. Orchestrator records carry no
  `model-record` marker. Per human decision 2 (issue #415 comment
  6119460026), the maintainer may object to a decision taken by rule until the
  change reaches `main`, including after a work-item merge into a release
  branch; the record states that deadline.
- **Overrule:** before recording a departure from a role's recommendation,
  dispatch that recommending role for one pushback stating its arguments
  and the cost of the alternative; relay it, let the maintainer decide, and
  link it from a numbered human decision. Do not repeat pushback after the
  maintainer holds the position. A Reviewer is fresh under A27. #412 owns
  any reuse choice for other roles. If the maintainer overrules another
  role, or waives a contract rule, dispatch the Architect for a risk note.
  An Architect pushback can include the note in its "If overruled" section.
  The note is an Architect issue report with its own Planning marker and
  normal prose headed "Risk note": **Decision** (link), **What is
  accepted**, **Likely consequence**, **Early signal**, and **Revisit when**.
  This is the format referenced by A28's route override.
- **Low-severity findings (decided, Q1; superseded by A38, #488):** per human decision 1 (issue #415
  comment 6119460026), a low-severity finding is filed as an issue by default.
  A narrow text-only fix is allowed only during a round already required for a
  medium/high finding. An out-of-scope finding still needs its recorded
  Disposition and any scope-expansion decision.
- **Trade-off and limit:** printing the table costs roughly 600 tokens per
  opted-in session, but keeps the rule at the existing Seam where it will
  be read. Revisit a plain linked `DECISIONS.md` if the table exceeds about
  ten rows or the injected file approaches S180's 80-line cap; keep the
  rule sentence and never-list in `ORCHESTRATOR.md`. Tests can check the
  seeded rows, exclusions, record shape, pushback text and note fields;
  whether every suitable choice is represented or a row is applied
  correctly in a live session remains human judgment. Add to A27's
  pre-merge self-check that no orchestrator comment has a `model-record`
  marker and every overruled recommendation has an Architect risk note.
- **File structure (round 1, F44):** in `ORCHESTRATOR.md` the "Decided
  without asking" section is the last section of the file, so no closing
  heading is needed and the later run rules (merge self-check, model per stage,
  marker line, no self-granted shortcuts, cannot dispatch, resume) sit above
  it, not under it. The "When a recommendation is not accepted" paragraph is
  separated from its neighbours by blank lines. The file stays at or under S180's
  80-line cap (the move costs one blank line; the "Limit:" sentence folds into
  the self-check paragraph to pay for it). Not the DECISIONS.md trigger: that
  fires on more than about ten rows or an overrun; the cap is unchanged. The
  Override paragraph points to that in-file paragraph and `SKILL.md`, not to a
  bare issue number.

### A38 — A low review finding is fixed in the PR when its fix is trivial; otherwise deferred in one bundle (#488)
- **Decision:** supersedes human decision 1 of #415 (the A29 bullet "Low-severity findings", low = issue by default), at the maintainer's request. The "Decided without asking" row in `ORCHESTRATOR.md` keys on two axes: severity (unchanged, medium/high block) and a Reviewer-proposed `Fix cost` of `trivial`, `small` or `large`. A low finding with a verified `trivial` fix is fixed in the PR; every other low is deferred into one bundled issue per PR. Cost of delay is one comparison (trivial fix plus one delta re-review against a later full pipeline run); there is no numeric model.
- **Module and Locality:** the `trivial` definition (T1-T6, with its numeric limits and the git commands that measure them) lives in one place, the `Fix cost` field of the Reviewer finding format in `skills/role-contracts/SKILL.md`. The `ORCHESTRATOR.md` row holds the decision rule (fix or defer, the one-fix-commit cap, the delta-scope re-review, the log line) and points to that field; it does not restate T1-T6. `ORCHESTRATOR.md` is at 79 of S180's 80 lines, so a second copy of the definition would not fit and would drift. `skills/pre-merge-review/SKILL.md` gains one sentence: a re-review after a trivial-fix commit is scoped to that delta for new findings, but still carries every earlier slug. Deleting the row returns the choice to each dispatch; deleting the field leaves the tag undefined. Deep Interface: one short row over one definition.
- **Tag format:** a prose `Fix cost:` line in the finding, beside Class and Severity. It is not inside the `<!-- finding:<slug> status=... -->` marker, so `rr_rounds`, `review-rounds.sh`, `finding-carryforward-gate.sh` and the merge guard are unchanged. A missing or doubtful tag means not trivial.
- **Mechanical check, no new script:** only T1, T2 and T6 are measured: the fix commit's files against `git diff --name-only <base>...<reviewed-sha>` (the head the findings were pinned to, not the new HEAD, or the check is tautological), `git diff --numstat` for changed lines, `git diff -U0` for hunks, CI on the fix commit. T1 and T2 measure the trivial-fix commit F alone, never a range: `git diff --name-only F^ F` (each file must be in the reviewed-sha set above), `git diff --numstat F^ F`, `git diff -U0 F^ F -- <file> | grep -c '^@@'`. A range `<reviewed-sha>..F` would also count a blocking-fix commit pushed beside F, or a merge of `main`, and push a genuinely trivial fix toward deferral. F must be a single commit with exactly one parent (`git rev-list --parents -n 1 F` prints two fields); a merge commit, or a fix folded into a blocking-fix commit, cannot be measured and is not a trivial-fix commit, so the finding is not trivial. T1 and T2 run after F exists, so a failure there takes the same path as a red CI (below). T3-T5 are judged by the orchestrator reading the diff. A helper script would have one caller and one adapter (git), so the two-adapters rule does not justify a new Seam, test surface and adoption surface; the commands in the field are the Interface. Revisit if the orchestrator misapplies the check in a recorded run.
- **Class route kept (A28 not waived):** `trivial` is a Fix cost, not a Class, and the row never skips the A28 route. Only `code` and `test` lows can be trivial: a `design` or `spec` low starts at the Architect or Product and changes spec content, which T5 already excludes, so it is deferred. For a `code` or `test` low tagged `trivial` the route runs in full: QA, then Developer, then a fresh Reviewer (the delta round). QA's step is the A28 "red test for the defect" met without a new test case (T5 stays whole): QA names the check that is red on the reviewed sha for this defect, either an existing test, gate or `./check` step, or the Reviewer's `Falsifying check` run as a command (for a docs file such as `CHANGELOG.md`, that command is the red check, e.g. the line-length `awk`). QA adds no test, scenario or assertion. If QA can name no such red check, the `trivial` tag is void and the finding is deferred. QA does this once for all trivial-tagged lows of the round, because only one trivial-fix commit is allowed. The Developer makes the fix commit F (A4: application source and files are the Developer's, and the orchestrator writes no work-item artifact). So T4's code and test allowance stays reachable, and AC4's PR #485 replay (class `code`, a docs-file defect) still ends in "fix in the PR". Open risk: a maintainer who reads "red test" in A28 as strictly "a new test case" must decide this; this entry reads it as "a red check", the same observable condition the Falsifying check field already requires.
- **Cap and loop:** at most one trivial-fix commit per PR, kept apart from any blocking-fix commit so that its lines are measurable; it may be pushed together with one. The re-review is a fresh Reviewer round (A27) whose new findings are limited to the fix delta; new lows there are deferred; a new medium or high blocks as today and follows the two-round trigger (A28). The bundle is filed once, after the last round, with every deferred low of the PR. If CI fails on the fix commit (T6), or T1 or T2 fails when measured after it exists (AC12), the fix is reverted, its finding is deferred, and the revert is a normal commit that needs a fresh review of the new HEAD; no second trivial fix is allowed. One failure path, not two: a trivial fix is attempted at most once per PR, and the attempt is spent even when it is reverted. The bundle holds only lows deferred by this rule that have no `Disposition` of their own; an out-of-scope low with Disposition `issue` is filed as its own issue immediately, as before (AC14), and is never added to the bundle.
- **Gates unchanged:** the fix commit moves HEAD, so round 1's marker is stale and the merge guard needs round 2's marker on the new HEAD (#225). Each round is one A37 round, so `review-rounds.sh` counts it; a low-only round does not count toward the two-round trigger. `finding-carryforward-gate.sh` needs round 2 to mention every slug round 1 left open: fixed lows as `status=resolved`, deferred lows still `status=open`. A delta-scoped Reviewer must therefore be briefed with the earlier slugs as inputs; the scope limit is for new findings, not for carrying old ones.
- **Reconciliations with #488's text:** "changes no behavior" (R5, T5) cannot hold beside T4's off-by-one and wrong-variable fixes; the rule is "no new behavior: the code is brought to what the spec, existing oracle or surrounding code already states". In a test file T4 applies to lines that are not assertions or expected values (T5 owns those). A file counts as docs only by path: any `*.md` file anywhere, including `templates/**/*.md` (AC13). Scripts and `ci.yml` under `templates/` are code or test. A comment-only change in any other file is a code/test file for T1 and T2.
- **Adopted projects:** `ORCHESTRATOR.md` reaches an opted-in project through the symlinked checkout with no choice of its own, which is A20's case. The notice is a `CHANGELOG.md` line unless the maintainer bumps the meaning version of `process-multi-agent-roles`, a decision the orchestrator does not take.
- **Not decided here:** that every "tiny code fix" stays tiny. T6 shows only that nothing regressed, not that the fix is right; the delta round and the finding's falsifying check carry that. Accepted limit: T3-T5 and the one-commit cap are judgments logged in the Pipeline log (R8), not gated.
- **Violated when:** `ORCHESTRATOR.md` restates T1-T6 or exceeds 80 lines; a low is fixed without a `Fix cost: trivial` tag and a recorded T1/T2/T6 check; a second trivial-fix commit lands on one PR; a script reads `Fix cost`; a delta re-review drops an earlier open slug; a trivial-fix commit is measured as a range or is a merge commit; a `trivial` low is fixed without QA naming a red check; a `design` or `spec` low is fixed as trivial; an out-of-scope low with Disposition `issue` goes into the bundle.

### A33 — Effort is removed from the marker pipeline; the floor is judged on the model (#424, #413)
- **Why:** the dispatch tool takes no effort argument, so effort was never set or verified: #405 W2 found that all 33 agents ran at medium whatever their markers said. A recorded effort was a claim nobody could check.
- **Emitter:** `model-record-emit.sh` no longer writes `effort`. It accepts `--effort` and ignores it for one release, printing one stderr line, "effort is no longer recorded (#413); drop --effort from your prompt", so stale prompts in adopted projects keep working. The next release removes the flag (PRD debt row).
- **Gate and collector:** the gate's lower-effort finding is gone and its per-field check covers `model` only. Collector gate 2 is `evidenced` on the same model and `unverifiable-from-artifacts` on different models; gate 1 and the inter-issue conflict key read the normalized model alone. `effort_rank` is deleted from `lib/model-record.sh`. A legacy `effort` attribute of any shape is still read without error and ignored.
- **The limit (A33a):** the floor is judged on the model, and effort is neither chosen nor checked, so the same model at a lower effort meets the floor. This is an accepted risk. Revisit when the dispatch tool gains an effort parameter.
- **Meaning versions:** `quality-review-before-merge` goes to 4 and `process-model-choice` to 2, once, in this slice.
- **Violated when:** a script, skill or the orchestrator tells a role to pass `--effort`, or a finding or verdict reads an `effort` attribute.

### A31 — The record grammar v2 reader, initially beside the former parser (#425, slice V4 of #411; A31a, A32a)
- **Why (at V4):** the former walker (`former stage lookup`, `former classification scan`, `former attribute tokenizer`) tokenizes quotes, `-->` and `<!--` across lines, which is where the #405 defect classes (a `>` or odd quote in a value, an open quote, a split record) came from. A record is now one whole line from a closed value set, so there is nothing to tokenize and nothing that can swallow a later record.
- **Grammar:** `MR_STRICT_ERE`, `MR_LOOSE_ERE`, `PO_STRICT_ERE`, `PO_LOOSE_ERE` in `lib/model-record.sh` are the whole grammar for `model-record` and `pipeline-override`. The record starts in column 0; a value byte is anything but `"`, `<`, `>` and a control byte (0x80-0xFF are values); the loose pattern needs the colon. Matching runs on bytes.
- **Reader:** `rec_scan_bundle <kind> <bundle>` and `rec_scan <kind> <body>` print one row per candidate line, `<body-index> TAB <ok|near-miss|quoted> TAB <stage-or-?> TAB <line-or-reason>`; indices count from 1 and no field is empty. One awk pass per bundle, the one program in `lib/markdown.sh` (mode `rec`), so a record is quoted where `live_text` would blank it (a fence, state reset at every U+001E; a blockquote; a code span) plus indented code (an indent of 4 or a tab), which only rec mode quotes: `live_text` keeps those lines. Every row ends in an ASCII byte (the text of a near-miss or quoted row is wrapped in quotes, so `read` never splits a UTF-8 sequence); consumers may rely on this. The strict pattern then classifies each live candidate in bash. Text before the opener, or 1-3 leading spaces, is a near-miss.
- **Fields:** `rec_field <line> <name>` is a left-to-right walk, one `<blanks>name="value"` per step, first occurrence wins, so a value ending in ` floor-basis=` is never an attribute.
- **Failure:** grep exit 1 is "no hit"; grep or awk exit 2 or more, or `[[ =~ ]]` result 2, prints nothing on stdout, one line on stderr and returns non-zero. Every external command carries `LC_ALL=C` (S235) and grep is `grep -a`.
- **Emitter (A33a):** `marker_emit` reads its own line back through `rec_scan` and `rec_field` and, during V4 migration, also through the former parser. V8 (#429) retires that additional round trip after the last caller moves. Its floor-basis deny-list: `"`, `<`, `>`, C0 and DEL, the C1 controls, U+2028/2029 and the bidirectional controls U+202A-202E and U+2066-2069. Limits are 500 bytes (floor-basis) and 200 bytes (model). The wrapper refuses a value equal to one of its flag names (`--model --floor-basis`); a value that merely starts with `--` is allowed.
- **Not in this slice:** no caller moves yet (the gate, collector and staleness script kept the former parser until V6 to V8); the old functions are deleted with the last caller.
- **Violated when:** a script outside `lib/` carries its own record pattern; a near-miss is read as a record; a reader failure becomes "no record".


### A39 — One canonical workflow policy, two runtime adapters, explicit installation ownership (#455)

- **Decision / scope:** implements F45–F54 using the completed `v0.4.0`
  workflow meaning. Records the [Architect planning decision](https://github.com/TiesL/spec-driven-guardrails/issues/455#issuecomment-6144735967)
  without redesigning roles, evidence or adoption semantics. This checkout
  descends from `v0.4.0`; release evidence still requires real Claude, Codex
  CLI/desktop and second-machine dry runs, not a structural installation claim.
- **Canonical owners:** the Workflow policy Module owns `policy/WORKFLOW.md`,
  extracted from current WORKFLOW.md without semantic edits. `skills/<name>/`
  remains the sole skill-content owner, including role-contracts/ORCHESTRATOR
  and model-choice; CHANGES.md owns adoption and meaning versions. Runtime
  mappings are `adapters/claude/INSTRUCTIONS.md` and
  `adapters/codex/INSTRUCTIONS.md`, limited to discovery/execution instructions
  and capability limitations. No adapter-specific policy override is permitted.
  A38 (#488) updates those shared owners: the Fix cost definition stays in
  `skills/role-contracts/SKILL.md`, and the fix/defer rule stays in
  `skills/role-contracts/ORCHESTRATOR.md`. Both runtimes consume that same
  policy, including QA's red check, the single trivial-fix attempt, fresh delta
  Review with prior slugs, and deferral rules. No adapter copy of T1–T6 or
  separate low-finding route is introduced. AC10 continuation follows these
  current shared routes; it does not freeze the pre-#488 route wording.
- **Generation Interface:** `generate-workflow-adapters.sh` deterministically
  emits root `WORKFLOW.md` (Claude compatibility path) and
  `adapters/codex/AGENTS.md` (managed-block payload): generated header,
  canonical policy bytes, selected mapping bytes, in that order. Outputs are
  committed and never edited directly; no timestamps or machine paths.
  Codex embeds policy because a Markdown link does not import instructions.
  Both mappings require reading applicable session-context output and invoked
  skill content before dependent work. `session-context.sh --runtime
  claude|codex <project>` defaults to Claude, preserves CHANGES/answered_yes
  selection and emits ORCHESTRATOR verbatim only when opted in; runtime selects
  diagnostics, never different workflow rules.
- **Adoption/update Interface:**
  `SPEC_DRIVEN_GUARDRAILS_DIR=<local-checkout> adopt.sh [--runtime claude|codex] [project]`
  defaults to Claude/current directory. Repeat adoption performs update/repair;
  rerun after checkout/version/machine changes. `install.sh [tag]` selects only
  checkout version, never adoption. Unknown/multiple runtimes, invalid inputs
  or option combinations, and `--runtime codex --user` exit 2 before writes;
  `--user` remains Claude-only. Install only the selected adapter plus existing
  shared scaffolding/adoption work. Each run reports runtime, project, checkout
  revision and each managed path as created/unchanged/repaired/removed/conflict,
  with conflict reason. Exit 0 means installed, not live-loaded; 1 means conflict
  or operational failure. Preflight conflicts cause no project/index writes;
  unexpected write failures report incomplete installation, never success.
  Transactional rollback is not promised. Existing foreign native Git hooks
  retain the leave-alone warning and unavailable-coverage behavior.
- **Codex ownership:** root AGENTS.md is project-owned outside exactly one
  `<!-- spec-driven-guardrails: begin -->` / `<!-- spec-driven-guardrails: end -->`
  block. Create an absent file, append to an unmarked regular file preserving
  existing bytes, or replace only a sound owned block. Duplicate, unmatched or
  nested markers, any AGENTS.md symlink, or root AGENTS.override.md are preflight
  conflicts. Parent/deeper instruction precedence and instruction budget require
  manual loading checks. The block contains no absolute path and directs an
  explicit read of `.guardrails/source/session-context.sh --runtime codex <project>`
  output and required skill files.
- **Skill/link ownership:** install individual `.agents/skills/<name>` links to
  the same canonical skills used by Claude; `.agents/skills` must be a real
  directory or absent. Child regular files/directories and foreign symlinks
  conflict. Local ignored `.guardrails/source` links to the selected checkout;
  local ignored `.guardrails/installation.json` records runtime, checkout and
  exact owned symlink paths/targets as provenance, never adoption evidence.
  Malformed/foreign records conflict. Live links resolving to canonical targets
  may be adopted; otherwise repair/remove only links matching recorded ownership.
  Broken unrecorded or manually redirected links conflict. Removed canonical
  skills remove only still-owned links. Ignore exact child paths using a separate
  guarded block, never the entire project skill namespace; malformed ignore
  markers or tracked absolute managed links conflict, with explicit remediation
  paths rather than index edits. Preserve project skills, adoption answers,
  AGENTS bytes outside the block and all Codex config/trust/permissions/hooks/plugin
  state. Claude retains its existing CLAUDE/settings/skills/native-hook paths and
  legacy backups; Codex never invokes that replacement path.
- **Status/drift Interfaces:** `adopt.sh --status --runtime claude|codex [project]`
  is read-only: reports inventory/revision, compares Codex block bytes to payload
  and links to recorded/canonical targets, names stale/broken/foreign paths and
  config/hook coverage. Exit 0 structurally current, 1 incomplete/conflicting/stale,
  2 invalid/unreadable; never claims live loading.
  `check-workflow-adapters.sh [workflow-checkout]`, included in `check` including
  static mode and CI, recomputes without writes, compares exact generated bytes,
  verifies both mappings/canonical owners and names every missing/mismatching
  source/output. Exit 0 clean, 1 drift/missing contract, 2 invalid/unreadable.
  A policy sentence mutation makes both outputs stale; regeneration puts it in
  both; changing/deleting one output names it. After regeneration Codex's copied
  block stays stale until re-adoption, while Claude's WORKFLOW symlink follows
  live. Byte equality cannot detect contradictory mapping prose; semantic review
  remains required. These are falsifiable S1/S4 installation/drift outcomes.
- **Evidence / S7 failure outcomes:** reuse `lib/model-record.sh`,
  `lib/markdown.sh`, `lib/review-rounds.sh`, the emitter and existing consumers;
  no adapter parser or ranking table. Preserve whole column-0 record v2,
  latest-near-miss behavior, ignored legacy effort/no new effort, model-only
  Review floor with floor-basis and script-specific unavailable/error outcomes.
  Failed reads never become zero rounds or successful validation. Preserve fresh
  Review sessions, artifact-only briefs, finding-class routes, two-round
  Architect reset and numbered bounded override/pushback/risk-note chain.
  Unavailable fresh role dispatch stops that stage for the existing human
  override; no role collapse. Runtime metadata must not silently hide shared
  skills: supported-version discovery failures return to Architect, without
  duplicated bodies. CLI and desktop share one local installation; no required
  plugin publication or meaning-version bump.
- **Actual runtime coverage:** initial Codex installs no runtime hooks and reports
  `runtime-hooks: not-installed; runtime shell interception unavailable`.
  Context/fetch/push and guards are instructions/manual actions plus shared Git/CI
  enforcement, not automatic Codex SessionStart/PreToolUse/PostToolUse/SessionEnd
  interception. Claude retains its existing SessionStart fetch/context notices,
  Bash PreToolUse tokenized destructive-Git/issue-first/merge gates and
  PostToolUse/SessionEnd push behavior. Existing non-Bash/indirect bypasses,
  missing gh/network/readers, fail-open warnings, post-action failure notices
  and branch exceptions remain. Native pre-commit/commit-msg/pre-push and shared
  check/evidence/CI remain shared: foreign hooks/hooksPath/--no-verify, missing
  dependencies and escape hatches retain their limits; native hooks do not
  intercept gh-pr-merge. CI proves configured artifact checks, not authorship,
  role freshness or obedience. QA uses existing Claude token/exit oracles and
  verifies Codex adoption leaves those paths untouched; Codex bypass cases expect
  absent interception plus documented shared coverage. Future translated hooks
  require a new Architect event/input/output contract and QA negatives.
- **F54 continuation addendum (AC10):** once the five-role workflow is
  authorized, stage completion is evidence for the next dispatch, not a new
  user approval gate. The canonical `skills/role-contracts/ORCHESTRATOR.md`
  owns this continuation rule for routine handoffs and existing finding routes,
  including fresh-role requirements and the two-round Architect step. Existing
  genuine human decisions, contract overrides, unavailable required dispatch
  and confirmation before a merge into `main` remain stops. Resume from durable
  issue/PR artifacts, stage markers, Pipeline log and open findings to determine
  the next required stage or route; a completed initial stage does not discharge
  a later finding route. The Codex mapping in `adapters/codex/INSTRUCTIONS.md`
  directs the orchestrating session to read and follow that canonical guidance,
  continue with available fresh dispatch, and recover from those artifacts;
  it does not duplicate route tables, override policy or introduce a dispatch
  framework. Regenerate its managed payload through the existing generator.
  This is instruction-driven continuation, not a claim of background scheduling,
  runtime hook enforcement or proven live autonomy; structural checks and the
  supported-runtime human dry run provide distinct evidence.
- **Module / Interface / Seam / Depth / Leverage / Locality:** installation
  filesystem and runtime instruction loading are the external Seams; adoption,
  status and drift commands are test Interfaces. Workflow policy and
  Adoption/update are deep Modules, hiding extraction, mapping, ownership,
  collision and repair complexity. Deletion would spread this complexity across
  both callers: Depth earns shared Leverage and concentrated Locality. A forwarding
  parity facade adds none. The two-adapters rule is satisfied by real Claude and
  Codex mappings; no speculative CLI/desktop/plugin Module or dispatch framework.
- **Revisit when:** observed supported-runtime discovery/loading failures,
  changed Codex hook capabilities, or actual drift/ownership failures require a
  new contract. Structural checks supplement the F52/F53 human dry runs; they
  cannot certify practical runtime behavior.

### A41 — Run rules get stable IDs, a condensed core in two self-standing parts and behavior tests; session-context output fits the hook cap; the `Agent` dispatch hook quotes the core (#499)

- **Why:** Claude Code keeps at most 10,000 characters of one hook's stdout in
  context and saves the rest to a file it does not ask the model to read.
  `ORCHESTRATOR.md` reached 13,933 characters, so opted-in sessions saw only a
  2,000-character preview. Human decisions 1-2 on #499: every rule stays
  injected verbatim, no rule moves to a voluntary read, and one stateless
  `PreToolUse` hook on `Agent` is in scope. Human decision 4: rules get stable
  IDs, the core is condensed in caveman style, wording tests give way to
  behavior tests, and slots are only a fallback. Human decision 5: two
  parts, fundamentals and procedure, each self-standing and
  order-independent, plus a committed differential-run stamp. QA's Test
  findings on #499 (Q1, Q2) add declared intended changes with their own
  verdict and the `continue_agent` and `merge` schema values. A41 is used
  because #515 has reserved A40.
- **Budget:** one value, `CONTEXT_BUDGET_CHARS=9000` (10% under the cap), in
  `lib/context-budget.sh` with `context_chars`, which counts UTF-8 code points
  in Python. That is the same number as `wc -m` in a UTF-8 locale, without
  depending on the locales a CI image has. The budget applies to each hook's
  output string, because that is how the platform measures. Only tests source
  the module; no run-time guard (Human decision 3). The docs that state the
  number (the `CHANGES.md` Reaches session field, PRD F38) are kept equal to
  the constant by a test.
- **Rule IDs:** every rule in `ORCHESTRATOR.md` is one list item (or one
  sub-item) that starts with its ID, `OR<n>` followed by a space, for example
  `- OR20 Two-round trigger. ...`. `OR` is used because adopted projects
  already use single-letter IDs (`O1`-`O5` in one of them). IDs are never
  renumbered or reused; a removed rule keeps its row with tier `retired`.
  Cost: about 5 characters per rule, about 220 for 45 rules, plus one header
  line. A paragraph-sized rule is split into several IDs only where a test or
  the hook needs to point at a part of it (the four self-check items, the
  Reviewer brief).
- **Condensed core:** `ORCHESTRATOR.md` is rewritten in the caveman style
  (#409): no articles or filler, terms, numbers, paths and negations
  (`not`, `never`, `only`, `except`) kept verbatim, at most 20 words per
  sentence. A rule enforced by the dispatch hook is one line in the core, and
  that line is the deny text. A Planning scratch rewrite that keeps all 45
  rules measured 10,252 characters (from 13,933); with the CLAUDE.md-link
  warning at 100-character paths (about 365) the worst case is about 10,600,
  over the budget. So Human decision 4's fallback applies, as the two parts
  below (Human decision 5).
- **Two parts (Human decision 5; amends the Human decision 4 slot
  fallback):** `ORCHESTRATOR.md` is two parts, both always injected in full,
  each by its own `SessionStart` command. The split exists for failure and
  ordering, not for loading: hooks run in parallel, outputs arrive in any
  order, and one hook can fail on its own.
  - **Part 1, fundamentals** (violation is irreversible or outward-facing):
    OR1-OR8, OR11-OR13, OR33-OR35, OR43, OR45 (16 IDs). Sections: "Role and
    pipeline" (OR1-OR6), "Dispatch" (OR7, OR8, OR11-OR13), "Shortcuts,
    stops, human gates" (OR33-OR35, OR43, OR45).
  - **Part 2, procedure:** OR9, OR10, OR14-OR32, OR36-OR42, OR44 (29 IDs).
    Sections: "Dispatch brief and Review round" (OR9, OR10, OR14-OR16),
    "Findings" (OR17-OR21), "Log and self-check" (OR22-OR27), "Models and
    markers" (OR28-OR32), "Resume" (OR36), "Decided without asking"
    (OR37-OR42, OR44).
  - **Placement calls.** OR43 ("never decided by the orchestrator") and OR45
    (pushback, then numbered human decision) leave the "Decided without
    asking" section for part 1, as Human decision 5 names them as human
    gates. OR37 (what a row may settle) stays in part 2 with its table.
    OR12 and OR13 (fresh Reviewer, no `SendMessage`) are fresh dispatch, so
    part 1; OR14-OR16 (brief contents) are part 2. OR3 and OR4 (what a work
    item is, first request) decide whether the pipeline starts, so part 1.
    OR9 and OR10 (contract quote, own report) are dispatch procedure, so
    part 2.
  - **Header.** Each part opens with a heading line, a blank line and one
    sentence line. For part 1 (part 2 swaps `1`/`2` and the two names):

    ```
    # Multi-agent pipeline run rules, part 1 of 2: fundamentals

    Part 2 of 2 (procedure) also applies; parts arrive in any order. Part 2 not in context: tell human before any dispatch or merge. `OR<n>` = stable rule ID; cross-part reference by ID only; never renumber.
    ```

    The sentence line replaces the single `OR<n>` header line. It is a fixed
    template, tier `core`, with no ID.
  - **Cross-part references.** By ID only. Three rules need the other part:
    OR21 and OR37 (part 2) already say "OR45"; OR31 (`--stage`) and OR36
    (resume "at first stage without marker") need the stage order in OR5
    (part 1), so OR31 gains "Stage names: OR5." and OR36 reads "first stage,
    in OR5 order, without marker". No part-1 rule needs part 2 to be read
    correctly: OR6's "finding-route steps" and OR12's fresh Reviewer stand
    as written. The words "above" and "below" do not occur in
    `ORCHESTRATOR.md`.
  - **OR11 wording.** Human decision 5 puts "merge into `main` only after
    the maintainer confirms the final head SHA" in part 1. OR11 reads:
    "Merge into `main` only after human confirms final head SHA; new commit
    after confirmation needs new confirmation." (Maintainer question on
    #499 if this goes beyond what was meant.)
  - **Split marker.** One line `<!-- session-context: slot -->` between the
    parts, the only such line in the file. It is not a list item, so the
    dispatch hook never reads it as a rule. `session-context.sh` never
    prints it.
  - **`session-context.sh --slot <n>`.** `<n>` is a positive integer;
    anything else exits 2 before any read, like the other invalid options.
    The script builds its normal output (Claude: the CLAUDE.md warning; Codex:
    its two lines; then a blank line and each declared file), splits it at
    each marker line, drops the marker lines and prints only chunk n. So slot
    1 is the warning plus part 1, slot 2 is part 2, and a slot past the last
    chunk prints nothing and exits 0. Without `--slot` it prints every chunk
    in order with the marker lines dropped, which Codex and the differential
    runner's arm text use.
  - **Wiring.** `settings/session-hooks.json` replaces the one session-context
    command with two in the same matcher-less `SessionStart` group, so both
    run on every source, `startup` and `compact` included (also `resume` and
    `clear`): the same dispatcher command with `--slot 1` and `--slot 2`,
    status messages "session context, part 1 of 2" and "part 2 of 2". An
    adopted project gets both through its existing settings symlink.
  - **Worst-case size** (scratch rewrite split as above, with the OR11, OR31
    and OR36 changes, and the CLAUDE.md warning at 100-character paths, 364
    characters): slot 1 about 4,260 (part 1 alone 3,890); slot 2 about
    6,980. Both are under 9,000; part 2 has about 2,000 of headroom.
  - **Inventory.** `orchestrator-rules.tsv` gains a `part` column:
    `id<TAB>name<TAB>tier<TAB>part<TAB>covered_by`, `part` is `1` or `2`, and
    `-` for `retired`. Moving a rule between parts is then a visible
    inventory change.
  - **`./check` asserts** (deterministic, from the files):
    1. `ORCHESTRATOR.md` has exactly one marker line, so exactly 2 parts.
    2. Each part starts with its two header lines, with `n` equal to its
       position and `m` the other part.
    3. Every non-retired ID occurs in exactly one part, and that part equals
       its inventory `part`.
    4. No `above` or `below` as a word in either part.
    5. Worst case per slot: `session-context.sh --slot <n>` output, with the
       warning at 100-character paths, is at most `CONTEXT_BUDGET_CHARS`
       for n = 1..K.
    6. The number of chunks equals K, the count of `--slot` commands in
       `settings/session-hooks.json`, and those are `--slot 1..K`.
    7. Slots 1..K joined equal the output without `--slot`.
- **Rule inventory:** `skills/role-contracts/orchestrator-rules.tsv` has one
  row per rule: `id<TAB>name<TAB>tier<TAB>part<TAB>covered_by` (`part`:
  see "Two parts"). `name` is a short
  kebab-case label that AC lists and tests refer to; it is not injected.
  `tier` is one of:
  - `judgment`: a decision only a model makes; covered by at least one
    behavior scenario.
  - `hook:<check>[,<check>]`: enforced by the dispatch hook; covered by the
    hook's deterministic tests.
  - `gate:<script>`: enforced by an existing gate; covered by that gate's
    tests.
  - `core`: a fact, pointer, literal template or disclaimer; covered by a
    deterministic structure or absence check.
  - `retired`: the ID is gone from the core and is never reused.

  `covered_by` lists the `S<n>` tests and `OB<n>` behavior scenarios that
  verify the rule. `./check` asserts: every non-retired ID occurs exactly once
  in `ORCHESTRATOR.md`, at the start of an item, and every ID there has a row;
  the AC4 rule names are all present; the hook check ids equal
  `agent-dispatch.py --list-checks`; every `judgment` row has an `OB` that
  exists and every `OB` cites only existing IDs; every `gate:` script exists.
  Nothing tells a session to read the inventory, and it holds no rule text.
  The ID replaces the anchor substring of the first A41 draft.
- **Behavior scenarios:** `test/behavior/orchestrator-scenarios.md` holds
  `OB<n>` scenarios, each one block:
  `### OB<n> · OR<a>[, OR<b>]`, then `Given:`, `When:` and
  `Then: <field>=<value>; ...`. The fields form one closed schema owned by the
  runner: `next_action` (`dispatch`, `continue_agent`, `merge`, `ask_human`,
  `stop`, `answer_directly`, `comply_and_record`, `self_check`,
  `record_decision`), `next_role` (the five roles or `none`),
  `starts_pipeline`, `asks_human` (booleans), `low_finding` (`fix_in_pr`,
  `defer`, `file_issue_now`) and `model_choice` (`same_or_stronger`,
  `weaker`), plus an ungraded `reason`. `Then` lists only the graded fields.
  A `./check` structure test parses the file: every field and value is in
  the schema, and every scenario cites an existing ID.
  - **`dispatch`, `continue_agent`, `merge` (QA finding Q2).** `dispatch`
    starts a new agent; `continue_agent` sends a further message to an agent
    that already exists (`SendMessage`), with `next_role` naming its role;
    `merge` runs a PR merge now. `answer_directly` excludes all three. With
    one value for both kinds of agent call, a mutant that drops "never
    `SendMessage`" (OR12, OR13, OR45) grades `same`; with merge folded into
    `answer_directly`, OR11's merge-or-not cases grade on a value that also
    covers "explain" or "run a command". The fresh-Reviewer rule and the
    merge gate are part 1, so their scenarios must be able to fail. The
    runner's fixed preamble carries the scenario file's Schema definitions
    word for word, so both arms read each value the same way.
  - **Intended changes (QA finding Q1).** A scenario whose `Then` follows a
    decided rule change the old text may not state is declared in the
    file's last section, `## Intended changes`, one list item per scenario:
    `- OB<n> (OR<a>[, OR<b>]): <change>`, continuation lines indented, the
    item citing the decision as at least one `#<n>`. The parser reads only
    that section. `./check` asserts: each listed `OB` exists, its `OR` list
    equals that scenario's heading IDs, no `OB` is listed twice, and each
    item has a `#<n>`. Whether the cited decision is real is reviewer
    judgment. The list sits inside the stamp hash, so adding an entry needs
    a fresh run.
- **Differential run:** `test/behavior/orchestrator-diff.sh [--base <rev>]
  [--runs N] [--model M] [--max-budget-usd X] [--calibrate]` compares the
  `ORCHESTRATOR.md` at `<rev>` (default `origin/main`) with the working
  tree's. For each scenario and arm it runs N times (default 3):
  `claude -p --model <M> --system-prompt-file <arm text plus a fixed preamble>
  --tools "" --strict-mcp-config --setting-sources "" --settings
  '{"disableAllHooks":true}' --no-session-persistence --output-format json
  --json-schema <schema>`, from an empty scratch directory, with Given and
  When as the prompt and never Then. Hooks are disabled so the
  session-context hook cannot inject the current file into the old arm.
  `--bare` is not used because it requires an API key and ignores the OAuth
  login. (Probed on Claude Code 2.1.301: `structured_output`,
  `total_cost_usd` and the resolved model id under `modelUsage` are in the
  JSON result.)
  - **Majority:** per arm and graded field, the value reached by more than
    half of the runs; none means `unstable`.
  - **Verdict per scenario,** first match wins; "equals `Then`" means every
    graded field's majority equals its `Then` value:
    1. `unstable`: the new arm has no majority on a graded field.
    2. `changed-as-intended`: the scenario is listed under Intended
       changes, the new arm equals `Then` and the old arm does not (a
       missing majority included).
    3. `unstable`: the old arm has no majority on a graded field.
    4. `same`: both arms equal `Then`.
    5. `old-wrong`: the old arm misses `Then` (a scenario or old-text
       defect, for a human to settle).
    6. `diverged`: the old arm equals `Then` and the new arm does not.

    A listed scenario only relaxes the old arm: the new arm must still equal
    `Then`, so a listing cannot hide a new-text defect. A listed scenario
    that comes out `same` is not an error, and an entry may stay after its
    change is on `main`. Exit 0 only when every scenario is `same` or
    `changed-as-intended`. Baseline (old against old, AC12): its pass
    criterion is every unlisted scenario `same`; listed scenarios are
    reported, and their expected verdict there is `old-wrong`.
  - **Calibration (`--calibrate`):** an A/A run (old against old) measures
    the noise floor, and a mutant arm (the new text with one `never` or `not`
    removed in a `judgment` rule) must come out `diverged`. This shows that
    the test catches the moved-`not` failure that Human decision 4 named.
  - **Report:** a Markdown table (scenario, old, new, Then, verdict, resolved
    model id, cost) for the PR. It is acceptance evidence for a rewrite, not a
    `./check` gate.
  - **Model:** the current Sonnet alias at its default effort; the resolved id
    goes into the report. The orchestrator in real runs is at least that
    capable, and a much weaker model raises the noise floor. Both arms run
    with the same model on the same day, so model drift cancels out of the
    comparison; `Then` catches both arms going wrong together.
  - **Cost:** 50 scenarios × 2 arms × 3 runs = 300 calls of about
    4,500 input and 400 output tokens, roughly USD 1.9-3.8 at list price per
    full run (under a subscription login it counts against plan usage).
    `--max-budget-usd` caps it (default 5).
  - **Where it runs:** locally, on demand, when `ORCHESTRATOR.md` or the
    scenarios change. Not in CI: it needs an API-key secret, costs money on
    every push, and is not deterministic.
  - **Seam:** the pure core (`orchestrator_diff.py`) turns run results into
    verdicts. `./check` tests it with a stub `claude` named by `CLAUDE_BIN`
    that returns canned JSON, so the majority and verdict logic is
    deterministic and free.
  - **Stamp (Human decision 5 point 2).** When every scenario is `same` or
    `changed-as-intended` (the exit-0 condition), the runner writes `test/behavior/orchestrator-diff.stamp`: one line
    `sha256=<hex> base=<rev> model=<resolved id> scenarios=<count>`, where
    the hash is SHA-256 over the bytes of `ORCHESTRATOR.md` followed by the
    bytes of `orchestrator-scenarios.md`. The stamp is committed. `./check`
    recomputes the hash and fails when it does not match, so a change to
    either file needs a fresh passing run. `./check` never runs the model;
    it only compares hashes.
- **Existing wording scenarios:** absence checks (no model names, tiers,
  `--effort`, grammar copies, risk-note field lists or new markers) and
  plumbing checks (S177-S179, S182, S184, S206 path resolution) stay
  deterministic. Presence-of-phrase checks on `ORCHESTRATOR.md` shrink to
  "the ID exists, has its tier and sits in the core", and the behavior they
  protected moves to `OB` scenarios. S283's paragraph oracles and the
  S288/S291 clause and mutation checks are replaced by the inventory and by
  the `OB` scenarios and the calibration mutant on OR43 (removing its opening "Never" flips the never-decided list; OR40's only `never` is redundant with "deferred").
- **Dispatch hook, Module and Interface:**
  - **Files and wiring.** Two new files, `hooks/agent-dispatch` (bash adapter)
    and `hooks/agent-dispatch.py` (pure core), not added to `git-guardrails`,
    which has a different matcher, input and deletion test. Wired as a second
    `PreToolUse` entry with `matcher` `Agent`, `timeout` 10, through the same
    `readlink` dispatcher, so an adopted project gets it through its existing
    symlink.
  - **Adapter.** It honours `CLAUDE_WORKFLOW_GUARDRAILS_OFF`. It exits 0 unless
    `answered_yes "${CLAUDE_PROJECT_DIR:-.}" process-multi-agent-roles` (the
    one yes rule, A16). Without `python3` it warns and exits 0. Otherwise it
    runs `python3 -I agent-dispatch.py <ORCHESTRATOR.md> <inventory>` with
    stdin passed through. Both paths are in the clone, so the deny text is the
    injected text.
  - **Core.** It reads `tool_name`, `agent_id` and
    `tool_input.{prompt,subagent_type,model}`. The tool name and field names
    are constants that exist only here, and `--print-contract` prints them for
    the drift test against the settings matcher. Its precedence:
    1. A tool other than `Agent` exits 0 silently.
    2. A non-empty `agent_id` (a call inside a subagent) exits 0 silently.
    3. Input that is not JSON, or has no `tool_input` object, or whose
       `prompt` is not a string, exits 0 with one stderr line.
  - **What counts as a role dispatch.** A prompt with a line that starts
    `ROLE SESSION:`, or a line that has `model-record-emit.sh` followed by
    `--stage`. Anything else is allowed silently.
  - **Checks.**
    - `prefix`: the first non-blank line is `ROLE SESSION: ` followed by one of
      Product, Architect, QA, Fullstack Developer or Reviewer.
    - `no-fork`: `subagent_type` is not `fork`.
    - `marker-command`: `model-record-emit.sh` with `--stage <one of the five
      stages>`.
    - `model`: a non-empty `model` argument.
    - `reviewer-pr`, `reviewer-sha` and `reviewer-gate`: Reviewer only. A PR
      number or `/pull/<n>`, a 7-40 character hex SHA, and the literal
      `finding-carryforward-gate.sh`.
  - **Result.** All checks pass: exit 0, no output. Any check fails: exit 2.
    stderr lists, once each, the `ORCHESTRATOR.md` lines whose IDs the
    inventory maps to the failed checks, then one line on how a non-role
    prompt avoids detection.
  - **Fail open.** If the inventory or `ORCHESTRATOR.md` is unreadable, or a
    mapped ID has no line, the call is allowed with a stderr line.
  - **Limits.** No network, no `gh`, no state.
- **Not in the hook:** the two-round trigger (needs `gh`), the fresh-Reviewer
  `SendMessage` check, deny-once and new merge gates (the follow-up issue),
  the content quality of the contract quote, and "no paraphrase". The checks
  test presence and shape, not correctness; that residual risk is accepted.
- **Module / Interface / Seam / Depth:**
  - **Deletion test.** Deleting the hook removes exactly the dispatch-shape
    enforcement and nothing else, so the hook earns its place. Deleting the
    differential runner leaves judgment rules protected by nothing but
    reviewer reading, which is the failure Human decision 4 rejects.
  - **Seams.** The hook's pure core (synthetic JSON on stdin plus two file
    paths) and the runner's verdict core (run results in, verdicts out) are
    the test Seams; neither needs git, a project or a model.
  - **Adapters.** The bash adapter is the only part of the hook that knows
    about the environment or adoption, and `claude -p` is the runner's only
    model adapter. One real adapter each, so no runtime or provider
    abstraction is built.
- **Violated when:** a hook-tier rule's deny text differs from its
  `ORCHESTRATOR.md` line; a rule has no ID or two rules share one; a
  `judgment` rule has no behavior scenario; a slot or `pending-changes.sh`
  output exceeds `CONTEXT_BUDGET_CHARS` in its worst case; a declared chunk
  has no wired slot; a rule ID sits in no part or in both, or in a part other
  than its inventory row; a part refers to the other part other than by ID;
  the stamp hash does not match `ORCHESTRATOR.md` and the scenarios; `ORCHESTRATOR.md` changes reach `main` without a
  differential report on the PR; or a rule is delivered only by a file
  nothing injects.
- **Revisit when:** Claude Code changes the cap or the `Agent` input shape;
  K would have to go above 2 (then the run rules need a redesign, not a third
  part); the A/A calibration shows more than one scenario in ten
  `unstable` at 3 runs; or either part's worst case comes within 500
  characters of the budget. The split is not undone when the whole core
  would fit one slot: it exists for failure and ordering (Human decision 5).
