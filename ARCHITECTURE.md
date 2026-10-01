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
A14-A18 taken by #371), not this file's own A1-A3, so the issue's
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
