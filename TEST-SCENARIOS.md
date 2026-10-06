# Test scenarios — spec-driven-guardrails

Purpose: these scenarios describe the intended/observed behavior (see
`PRD.md`). They're independent of the chosen technical solution and
describe only observable behavior.

Notation: **Given / When / Then**.

Every scenario carries a `**Covers:**` field with the functionality from
`PRD.md` that it tests — the convention from F13, decision b, applied here
to this repo itself. The prefixes are deliberately mixed: `R<n>` are the
regression scenarios from the original issue #7, `T<n>` the traceability
scenarios from #8, `S<n>` the new ones. That's not sloppiness but the proof
of F13, decision c: the integrity check must not hardcode a prefix.

**Red before green.** Every scenario is added and demonstrably seen red
before the corresponding implementation lands. The exception is R1–R9:
those are meant to be **green** on unchanged `main` — they record the
baseline and prove that the refactor preserves behavior, not that
something new is being added.

---

## Regression — behavior preserved across the refactor

### R1 — A fresh adoption seeds exactly the same rows
**Covers:** F3
- Given: an empty git project with no `package.json`
- When: `adopt.sh .` is run
- Then: `WORKFLOW-ADOPTION.md` contains exactly 17 rows, all with "requires
  substantiation during PRD/architecture"
- And: the legacy entry `prd-testscenarios-issue-templates` is **not** in it

### R2 — Pending questions after a fresh adoption
**Covers:** F3
- Given: the same fresh project, right after adoption
- When: `pending-changes.sh .` is run
- Then: exactly these 7 IDs appear as pending, in any order:
  `process-issue-tracking`, `test-integration`, `spec-performance-scale`,
  `spec-compliance`, `spec-portability`, `spec-usability`, `spec-cost-management`

### R3 — `package.json` makes `ci-convention` relevant
**Covers:** F3
- Given: the same project, now with a `package.json`
- When: `pending-changes.sh .` is run
- Then: `ci-convention` additionally appears as pending

### R4 — A `"deploy"` script makes `deploy-guards` relevant
**Covers:** F3
- Given: `package.json` with a `"deploy"` script
- When: `pending-changes.sh .` is run
- Then: `deploy-guards` appears as pending

### R5 — The NFR list stays 1:1 in sync
**Covers:** F4
- Given: the fifteen NFR IDs and the fifteen `###` subsections under
  "Non-functional characteristics" in `templates/PRD.md`
- When: both lists are laid side by side
- Then: an exact 1:1 correspondence, no side missing or surplus
- And: since F4, that happens via the `id`/`heading` pair from `nfr/*.md`,
  with no normalization heuristic

### R6 — Predicate behavior identical, and demonstrably correct
**Covers:** F3
- Given: six test projects, varying `package.json` presence, an
  executable `check` (#248 — independent of `package.json`), and
  `"deploy"`-script content
- When: the seed logic and `predicate_true()` all evaluate
  `has-check-command` and `has-deploy-script` against each of the six —
  no `CHANGES.md` row uses `has-package-json` directly anymore (#248);
  `package.json`'s own presence only still matters as the file
  `has-deploy-script` reads its `"deploy"` key from
- Then: all reach exactly the same answer for every combination, and the
  two new rows (an executable check without `package.json`, and
  `package.json` without an executable check) prove `has-check-command`
  is genuinely decoupled from `package.json`, not just a rename
- And: for **every** predicate there's at least one case where it's true
  *and* the corresponding entry is unanswered — otherwise a predicate that
  became too strict is invisible, since the difference lands nowhere in a
  pending set
- And: the outcome per combination is recorded explicitly, not only
  compared against each other; two identically broken predicates agree
  with each other and would pass a pure equality test
- And: what `adopt.sh` actually seeds is checked **directly** against the
  recorded outcome, not only via a union with the pending set. A union can
  only see that too much was seeded: whatever `adopt.sh` misses just stays
  pending and so cancels out against itself

### R7 — An adopted project still sees the full operational instruction
**Covers:** F12
- Given: an adopted project whose `CLAUDE.md` symlinks to the split-out
  `WORKFLOW.md`
- When: a session starts and `CLAUDE.md` is read
- Then: branching, quality review, the substantiation requirement,
  deploy-guards, and the adoption registry are all reachable — directly in
  the file, or via an explicit, directly followable reference
- And: every skill named in the routing table exists as a `SKILL.md`

### R8 — Retirement keeps working after restructuring `CHANGES.md`
**Covers:** F5
- Given: a retired entry, moved to `CHANGES-ARCHIEF.md`
- When: `adopt.sh` and `pending-changes.sh` run against a project
- Then: the entry is no longer seeded or asked about anywhere
- And: the ID stays findable via `grep` across `CHANGES.md` plus the
  archive file together, so a project that once answered the entry can
  trace where that row came from

### R9 — The four existing projects are never asked a question again
**Covers:** F2
- Given: the frozen baseline fixtures of `tennis-admin`,
  `tennis-registration`, `tennis-invoicing`, and `a2t-emails`
- When: `pending-changes.sh` runs against each fixture after the refactor
- Then: the number and identity of pending questions is exactly equal to
  the baseline
- And: if this diverges, the test fails naming the difference per ID — a
  silent change in the question set is never acceptable, not even as
  "cleanup"

### S66 — The source of the question set is fully frozen, including the nfr part
**Covers:** F2
- Given: the baseline fixtures, after W28
- When: a golden set is recomputed
- Then: every `spec-*` ID in it traces back to a frozen file in
  `test/fixtures/baseline/nfr.snapshot/`, verbatim equal to
  `CHANGES.md.snapshot`'s form
- And: no ID depends only on the current, non-frozen form of `nfr/`

### S67 — A change in the nfr register that affects the question set stands out
**Covers:** F2
- Given: an `nfr/` file with `applies-if: always` gets added (all fifteen
  existing ones carry that predicate, so any addition, removal, or
  retirement by definition touches all four fixtures)
- When: `pending-changes.sh` runs against a fixture after that change
- Then: the outcome diverges from the frozen golden set, naming the new
  ID — R9 already catches this, demonstrated with a mutation
- And: that difference can't be resolved by only adjusting the golden set:
  `nfr.snapshot` must then deliberately change along with it, with an
  explanation in the PR (see `LEESMIJ.md`)

---

## Test harness and `check`

### S1 — `check` fails on a syntax error in a script
**Covers:** F1
- Given: a script in this repo with a bash syntax error
- When: `./check` runs
- Then: exit ≠ 0, with the file in question named in the message

### S2 — `check` fails on invalid JSON in the hook configuration
**Covers:** F1
- Given: `settings/session-hooks.json` with a missing comma
- When: `./check` runs
- Then: exit ≠ 0 with a message naming the file
- And: this also happens when `shellcheck` isn't installed — JSON
  validation isn't an optional step
- And: if both `jq` and `python3` are missing, `check` still fails — it
  can't verify the file then, so it must not report "ok"

### S3 — The test sandbox refuses to run with the real `HOME`
**Covers:** F1
- Given: a test whose sandbox setup didn't redirect `HOME`
- When: that test starts
- Then: the run stops immediately with an explicit message
- And: nothing was written outside the temporary directory

### S4 — The baseline fixture records `a2t-emails` as found
**Covers:** F2
- Given: `a2t-emails` has no `WORKFLOW-ADOPTIE.md`
- When: the baseline fixture is created
- Then: the fixture records "everything pending"
- And: no `WORKFLOW-ADOPTIE.md` is created or fixed — the fixture holds
  the state, not the repair

---

## NFR register and archive

### S38 — A field with no preceding heading yields no entry
**Covers:** F3
- Given: a malformed source where an `Applies if` field appears before the
  first `## ` heading
- When: `iterate_entries` reads that source
- Then: no callback is called for that field — an entry with no ID would
  otherwise end up as a blank row in an adoption table
- And: the entries after the first heading are processed normally
- And: the same holds via `adopt.sh` itself, not just via the library
  directly: the adoption table contains no row with an empty ID

### S37 — Predicate and parser logic live in exactly one place
**Covers:** F3
- Given: `lib/changes.sh` holds the predicates and the parser skeleton
- When: `adopt.sh` and `pending-changes.sh` are searched
- Then: neither still has its own `heeft-*` branch or its own `## `
  heading-reader — they source the library
- And: the library does have them, so the test fails if it's gutted
  instead of only on recurring duplication
- And: both scripts **actually call** `predicate_true` from the library —
  established by instrumenting and running the function, not by searching
  text. A text match only sees literal copies; logic rewritten in another
  form slips through unnoticed

### S36 — An ID inside a note doesn't count as an answer
**Covers:** F3
- Given: a `WORKFLOW-ADOPTION.md` where the ID of a still-unanswered change
  appears in the free-text note of a *different* row
- When: `pending-changes.sh` runs
- Then: that change is still pending — only the ID column counts as an
  answer
- And: notes are free text and IDs like `test-integration` are ordinary
  words, so an unanchored match would silently make questions disappear

---

## NFR register and archive (continued)

### S5 — Generator and checked-in template don't drift apart
**Covers:** F4
- Given: an `nfr/*.md` whose `Guidance` has been changed without
  regenerating `templates/PRD.md`
- When: `./check` runs
- Then: exit ≠ 0, with the relevant NFR in the message

### S39 — A retired attribute disappears from both consumers
**Covers:** F4
- Given: an `nfr/*.md` with `status: retired`
- When: `pending-changes.sh` runs and the template block is generated
- Then: the attribute is no longer asked about and no longer in the block
- And: after regenerating, `check` doesn't complain — retirement here is a
  field, not a move, and that must carry through on both sides

### S40 — The order of the template block is fixed
**Covers:** F4
- Given: the `order` field determines where an attribute sits in the block
- When: the block is generated in a different order than what's checked in
- Then: `check` fails — a comparison that sorts by ID doesn't see that
  difference, so order is checked separately

### S41 — A broken register file doesn't silently disappear
**Covers:** F4
- Given: an `nfr/*.md` missing a required field or with one that's unusable
  (no `order`, CRLF line endings, a filename that doesn't match its `id`)
- When: `./check` runs
- Then: exit ≠ 0, with the file and the missing field in the message
- And: this isn't caught by the drift check alone — an attribute that
  falls out of the register disappears from *all* consumers at once, and
  then both sides of that comparison simply agree with each other

### S42 — Every reported change shows the question from its own source
**Covers:** F4
- Given: a project's pending changes, from both `CHANGES.md` and `nfr/`
- When: `pending-changes.sh` runs
- Then: every line shows the question text that belongs to that ID in its
  source
- And: a garbled or empty text is caught — a comparison on IDs alone
  wouldn't see that, while it's exactly what the user reads

### S6 — An entry without `Applies if` produces a warning
**Covers:** F5
- Given: `CHANGES.md` with a `## ` heading with no `Applies if` field,
  now that section separators have become `###`
- When: the shared parser reads that source
- Then: a warning appears naming the ID
- And: the entry is not seeded or asked about — a warning blocks nothing
- And: that also holds when the broken entry comes after a good one, and
  when it's the last one in the file — the parser state must not carry
  over from the previous entry
- And: a source with no trailing newline doesn't lose its last line;
  otherwise an entry would be silently skipped along with a misleading
  message

---

## Substantiation requirement and gates

### S43 — A healthy source produces nothing on stderr
**Covers:** F6
- Given: an adopted project with a well-formed `WORKFLOW-ADOPTION.md` —
  with pending substantiations, without, or without a table at all
- When: `pending-changes.sh` runs
- Then: nothing appears on stderr
- And: this isn't a cosmetic requirement. The SessionStart hook sends
  stderr to `/dev/null`, and every test call did too, which meant a shell
  error in the script stayed structurally invisible — including one that
  went off daily in three of the four real projects

### S7 — The signal counts rows still waiting on substantiation
**Covers:** F6
- Given: a freshly adopted project with 17 seeded rows carrying "requires
  substantiation"
- When: `pending-changes.sh` runs
- Then: a message appears, "17 row(s) … still waiting on substantiation"

### S8 — The signal doesn't change the pending set
**Covers:** F6
- Given: the same project
- When: `pending-changes.sh` runs
- Then: the list of pending IDs is identical to before F6 — the new
  signal sits alongside it, not inside it

### S9 — A stale adoption reports itself
**Covers:** F6
- Given: an adopted project with no `.claude/skills/`, while
  `$CLAUDE_WORKFLOW_DIR/skills` has skills
- When: a session starts
- Then: the hook reports that `adopt.sh` needs to run again
- And: the session just starts anyway — the message blocks nothing

### S10 — The production gate blocks a substantiation gap
**Covers:** F6
- Given: `skills/deploy-guards/SKILL.md`
- When: it's read
- Then: its Production conditions state that no row with
  `production-gate: yes` may still say "requires substantiation" —
  named as its own condition, the same way the other Production
  conditions are; a project's own `deploy` is what actually enforces
  this at runtime (per the skill), not a script in this repo

---

## Git guardrails

### S44 — The hook wiring lets the block through
**Covers:** F7
- Given: a project whose `.claude/settings.json` symlinks to this repo
- When: the configured `PreToolUse` command gets a command that should be
  blocked
- Then: exit status 2 comes out — the guard actually blocks
- And: the form `[ -x … ] && … || exit 0` does **not**: the `||` catches
  exit 2 and reports success, silently disabling the guard while it looks
  installed. Hence `if … then exec … fi; exit 0`

### S47 — Committing on `main` is blocked, with a workable way out
**Covers:** F7
- Given: `main` is checked out in a repo that already has commits
- When: `git commit` is called
- Then: it's blocked, and the message names `git checkout -b` and that the
  changes just come along
- And: the latter isn't courtesy but necessity — without that way out the
  work stays uncommitted, which is less safe than the local commit that
  was just stopped
- And: committing on a feature branch just goes through
- And: a repo with no commits is the exception: the very first commit of a
  new project is, by definition, on `main`, and that step is documented
  that way in `WORKFLOW.md`

### S45 — Text inside quotes is data, not a command
**Covers:** F7
- Given: a command with a `;`, `|`, or `&` inside a quoted string, or a
  heredoc whose body starts with `git`
- When: the guard evaluates it
- Then: it goes through — the content of a string or heredoc is data
- And: a quoted flag does count: `git reset "--hard"` is the same command
  as without quotes. Both requirements at once can only be met with real
  quote-aware tokenization; masking quoted spans solves the first and
  makes the second permanently impossible

### S46 — The branch is determined in the repo the command is about
**Covers:** F7
- Given: `git -C <path> push origin HEAD`, where `<path>` is a different
  repo than the directory the session is in
- When: the guard determines the current branch
- Then: it looks at the repo from `-C`, not at the session's directory
- And: `--git-dir` and `--work-tree` count the same way, and git itself
  works out how they relate — the guard doesn't reimplement those rules
- And: if that path doesn't exist or isn't a repo, no branch comes out and
  nothing is blocked

### S11 — Destructive commands are blocked
**Covers:** F7
- Given: the guardrails hook is active
- When: `git reset --hard`, `git clean -fd`, `git branch -D <name>`, or
  `git checkout .` is called
- Then: the command is blocked with a readable reason

### S12 — Push to `main` is blocked, including via a refspec
**Covers:** F7
- Given: a checked-out feature branch
- When: `git push origin main` or `git push origin HEAD:main` is called
- Then: the command is blocked
- And: `git push origin HEAD` while `main` is checked out is **also**
  blocked

### S13 — Push to a feature branch keeps working
**Covers:** F7
- Given: a checked-out feature branch
- When: `git push origin HEAD` is called
- Then: the command goes through — the existing `SessionEnd` hook keeps
  working

### S14 — The guard fails open if it's broken itself
**Covers:** F7
- Given: no `jq`, no `python3`, and no usable `sed` in `PATH`
- When: any git command passes through the guard
- Then: a loud warning appears
- And: the command is allowed — a broken guard never blocks the work

---

## Merge guard

### S15 — Merge without a review marker is blocked
**Covers:** F8
- Given: an open PR with no review marker in the comments
- When: `gh pr merge` is called
- Then: the command is blocked, referencing `pre-merge-review`

### S16 — Merge with a review marker goes through
**Covers:** F8
- Given: an open PR with the marker `pre-merge-review` places
- When: `gh pr merge` is called
- Then: the command goes through

### S17 — The merge guard fails open without network
**Covers:** F8
- Given: `gh` is missing or has no network connection
- When: `gh pr merge` is called
- Then: a loud warning appears that the review check was skipped
- And: the command is allowed

### S18 — A substantiated `nee`/`no` disables the guard
**Covers:** F8
- Given: a project whose `WORKFLOW-ADOPTIE.md` (pre-migration format, W42/#114)
  or `WORKFLOW-ADOPTION.md` has `kwaliteitsreview-voor-merge` respectively
  `quality-review-before-merge` set to `nee`/`no`
- When: `gh pr merge` is called on a PR with no marker
- Then: the command goes through, unblocked
- And: that happens without a network call — the row is read locally

### S64 — The merge-guard bypass disables only the merge guard
**Covers:** F8
- Given: the same command segment contains both
  `CLAUDE_WORKFLOW_MERGE_GUARD_OFF=1` and a destructive git command
  (e.g. `git reset --hard`)
- When: that segment is evaluated
- Then: the destructive git command is still blocked
- And: the bypass disables only the merge guard, not the rest of
  git-guardrails — otherwise the loud, targeted bypass from AC6 would in
  practice be a blank check for the whole segment

### S65 — `gh pr merge`'s value flags don't shift the target
**Covers:** F8
- Given: `gh pr merge --body "some text with words" --subject "title"` with
  no explicit PR number/url/branch
- When: the merge guard determines the target
- Then: it looks up the PR of the current branch (`gh pr view` with no
  argument), not `gh pr view "some text with words"`
- And: a marker-less PR therefore still gets blocked, instead of slipping
  through the fail-open path (a failed lookup of a non-existent "PR" with
  that name)

### S73 — Merge is blocked when CI isn't green
**Covers:** F8
- Given: a PR with the review marker, but with a failing check
- When: `gh pr merge` is called
- Then: the command is blocked, with the name of the failing check in the
  message

### S74 — Merge goes through when all checks pass
**Covers:** F8
- Given: a PR with the review marker and all checks `pass`
- When: `gh pr merge` is called
- Then: the command goes through

### S75 — No reported checks doesn't block
**Covers:** F8
- Given: a PR with the review marker, but with no reported checks (no CI
  adopted for that project, see F6)
- When: `gh pr merge` is called
- Then: the command goes through — no checks is not a red flag

### S76 — The CI check fails open if the lookup itself fails
**Covers:** F8
- Given: a PR with the review marker, but the CI lookup itself fails (no
  network, no access)
- When: `gh pr merge` is called
- Then: a loud warning appears that the CI check was skipped
- And: the command is allowed

---

## Relocation and dangling symlinks

### S78 — A single `adopt.sh` run fully repoints a project after a relocated checkout
**Covers:** F31
- Given: a project adopted from a checkout that then relocates (a rename,
  a move — e.g. W32/#56)
- When: `adopt.sh` runs again from the new location
- Then: both `CLAUDE.md` and `.claude/settings.json` are repointed to the
  new location in one action; a further run after that is a no-op

### S79 — A dangling `.claude/settings.json` reports itself, instead of running no hooks silently
**Covers:** F31
- Given: `.claude/settings.json` points at a checkout location that no
  longer exists (the relocation happened, this project hasn't re-adopted
  yet)
- When: a session starts
- Then: it reports the missing directory and says to run `adopt.sh`
  again, instead of silently running no hooks at all
- And: a healthy symlink stays silent (no false alarm), and a project
  that was never adopted (no `.claude/settings.json` at all) stays
  silent too

---

## Skills infrastructure

### S19 — `adopt.sh` installs per-skill symlinks
**Covers:** F9
- Given: an adopted project and a populated `skills/` directory in this repo
- When: `adopt.sh` runs
- Then: `.claude/skills/<name>` exists per skill as a symlink to this repo
- And: `.claude/skills` itself is a real directory, not a symlink

### S20 — Orphaned symlinks are cleaned up, real directories aren't
**Covers:** F9
- Given: `.claude/skills/old-name` points at a skill that no longer exists
  in this repo, and `.claude/skills/own-skill` is a real directory of the
  project
- When: `adopt.sh` runs
- Then: `old-name` is removed
- And: `own-skill` is untouched

### S21 — The `.gitignore` block is managed, not stacked
**Covers:** F9
- Given: a `.gitignore` with the two existing loose lines `CLAUDE.md` and
  `.claude/settings.json`
- When: `adopt.sh` runs
- Then: those lines appear exactly once, within the managed block
- And: lines outside the block stay untouched

### S22 — `adopt.sh` is idempotent
**Covers:** F9
- Given: an adopted project
- When: `adopt.sh` runs twice in a row
- Then: the file tree after the second run is identical to after the first
- And: `.gitignore` is byte-identical

### S23 — `adopt.sh` is a no-op without `skills/`
**Covers:** F9
- Given: a checkout of this repo from before this release, with no
  `skills/` directory
- When: `adopt.sh` runs
- Then: adoption succeeds with no error
- And: no empty `.claude/skills/` is left behind

---

## Skills and review

### S24 — Every skill in the register exists and is findable
**Covers:** F10
- Given: the skill register from `PRD.md` F10
- When: `./check` runs
- Then: every named skill has a `SKILL.md` with a `name` and `description`
  in its frontmatter

### S25 — The user-level skill sits at user level
**Covers:** F10
- Given: a non-adopted git project
- When: `adopt.sh --user` has been run and a session starts
- Then: `adopt-workflow` is available with no `.claude/skills/` existing
  in that project

### S68 — `tdd-seams` names the discipline concretely, not just encouragingly
**Covers:** F10
- Given: `skills/tdd-seams/SKILL.md`
- When: it's read
- Then: it names "seam", "red" and "green" (red-before-green), and the
  three anti-patterns by name: implementation-coupled, tautological, and
  horizontal slicing versus vertical slices

### S69 — `diagnose-bug` describes the mandatory order
**Covers:** F10
- Given: `skills/diagnose-bug/SKILL.md`
- When: it's read
- Then: reproduction, hypotheses, and regression test all appear, in that
  order, before the fix
- And: it explicitly states that hypotheses are shown before they're tested

### S70 — `CONTEXT.md` is scaffolded once the row is `yes`/`ja`
**Covers:** F10
- Given: a project whose `WORKFLOW-ADOPTION.md` (or, pre-migration
  W42/#114, `WORKFLOW-ADOPTIE.md`) has `process-context-document`
  respectively `proces-context-document` set to `yes`/`ja`
- When: `adopt.sh` runs
- Then: `CONTEXT.md` is created from `templates/CONTEXT.md`, if it doesn't
  exist yet
- And: an already-existing `CONTEXT.md` is never overwritten
- And: if the row is `nee`/`no` or missing, `adopt.sh` scaffolds nothing

### S26 — The review scope follows the answered `spec-*` rows
**Covers:** F11
- Given: a project whose `WORKFLOW-ADOPTIE.md` has only `spec-security` and
  `spec-data-integrity` set to `ja`
- When: `pre-merge-review` runs
- Then: the scope contains complexity and dependencies plus exactly those
  two NFRs
- And: NFRs set to `nee` or unanswered don't appear in the scope

### S27 — Missing anchors degrade, they don't block
**Covers:** F11
- Given: a project PRD without the anchors F4 places
- When: `pre-merge-review` runs
- Then: the skill falls back to the heading names
- And: it explicitly reports that the anchors are missing

### S28 — The review places a machine-recognizable marker
**Covers:** F11
- Given: a PR on which `pre-merge-review` posts its findings
- When: the merge guard judges that PR afterward
- Then: the marker is found and the merge is allowed

### S29 — The routing table resolves every moved topic in a single jump
**Covers:** F12
- Given: the five terms from R7 (branching, quality review, the
  substantiation requirement, deploy-guards, the adoption registry)
- When: `WORKFLOW.md` is grepped for each of those terms
- Then: for quality review, the substantiation requirement, deploy-guards,
  and the adoption registry — which *have* moved — every term yields a
  routing-table row pointing at exactly one existing skill
- And: two terms that land in the same skill get two rows of their own
- And: branching hasn't moved (F12 keeps the branch strategy in the core)
  and so resolves the way R7 allows: directly in the file, with no
  routing-table row

### S127 — `model-choice` never names a model or tier for a floor
**Covers:** F26
- Given: `skills/model-choice/SKILL.md`
- When: it's read
- Then: no model name or tier label ("mid-tier", a specific model ID)
  appears as part of a floor instruction
- And: every floor is stated as what the stage's output has to survive,
  not as a model name

### S128 — `model-choice` covers every pipeline stage, with the first stage floored on task demands
**Covers:** F26
- Given: `skills/model-choice/SKILL.md`
- When: it's read
- Then: it names all five stages from the multi-agent epic (#65) —
  Discovery, Planning, Test authoring, Implementation, Review — each with
  its own floor
- And: it states that every stage after Discovery anchors its floor to
  the stage before it
- And: it states that Discovery, having no predecessor, floors on the
  task's own demands instead

### S129 — `pre-merge-review` cross-references `model-choice` instead of restating it
**Covers:** F26
- Given: `skills/pre-merge-review/SKILL.md`'s "Model choice" section
- When: it's read
- Then: it refers to the `model-choice` skill for the canonical principle
- And: it still states the reviewer≥author floor and the always-record
  requirement for its own stage

---

## Traceability

### T1 — Full chain, everything covered
**Covers:** F13
- Given: `PRD.md` with `F1`; `TEST-SCENARIOS.md` with `S1` (`Covers: F1`) and `S2`
  (`Covers: F1`); an issue naming `S1` and `S2`; a PR referencing that issue
- When: the check runs
- Then: no errors, exit 0

### T2 — Functionality with no scenario
**Covers:** F13
- Given: `PRD.md` with `F2`, no scenario with `Covers: F2`
- When: the check runs
- Then: it fails with a message explicitly naming `F2`

### T3 — Scenario with no issue
**Covers:** F13
- Given: `S3` exists, no issue names `S3` in the field meant for that
- When: the gate in `pre-merge-review` runs
- Then: the finding explicitly names `S3`

### T4 — PR with no linked issue
**Covers:** F13
- Given: a PR with no `Closes #<n>` and no linked issue
- When: the CI check on the PR runs
- Then: the check fails and names the PR in question

### T5 — Preventing a false positive
**Covers:** F13
- Given: issue text naming `S1` in a sentence that isn't a reference
  (e.g. "we've already tested some s1 variants")
- When: the check runs
- Then: this does **not** count as a link — only the field meant for that
  counts
- And: a token like `S2b` does count, provided it's in the field

### S30 — Duplicate and unknown IDs are reported
**Covers:** F13
- Given: a `TEST-SCENARIOS.md` with two scenarios carrying the same ID, and
  a `Covers:` token that resolves nowhere
- When: the offline check runs
- Then: both problems are reported separately, with ID
- And: a `PRD.md` with no `F<n>` at all produces a **warning**, not a hard error

### S62 — Without coverage fields the check warns, and doesn't enforce
**Covers:** F13
- Given: a project where no scenario carries a `**Covers:**` field —
  all four existing projects are this case on the day of introduction
- When: the offline check runs
- Then: a warning appears and exit 0
- And: no uncovered item is reported at all. Without that exception the
  check would complain about *everything* at once on introduction, which
  is exactly the retrofit the design avoids
- And: once the first `**Covers:**` field is there, it does enforce —
  otherwise a single reference could leave the rest unpunished

### S63 — The check gets scaffolded and runs in a fresh project
**Covers:** F13
- Given: a project running `adopt.sh` for the first time
- When: adoption is done
- Then: `check-traceability.sh` is there, executable
- And: it runs there without failing — a scaffold that's immediately red
  gets switched off on first contact
- And: a project's own version of that file is never overwritten

### S71 — Existing projects still get the link-3 question
**Covers:** F13
- Given: a project with a `package.json` and an already-existing `ci.yml`
  that doesn't call `check-pr-issue-link.sh` (W19b's `scaffold_if_missing`
  leaves such a file alone — fixing the template only helps new projects,
  the same pattern as `ci-on-pr-and-main` in W24)
- When: `pending-changes.sh` runs
- Then: a new entry appears as pending
- And: a project with no `package.json` doesn't get that question

---

## Issue templates and release

### S31 — Blocking edges are in both issue templates
**Covers:** F14
- Given: `templates/ISSUE_TEMPLATE/work-item.md` and `epic.md`
- When: an issue is created from the template
- Then: both carry a `**Blocked by:**` and a `**Blocks:**` field, at the
  start of a line and in the `**Field:**` form the existing issues use
- And: a variant like `- Blocked by:` doesn't count — that reads the same
  to a human and is something different to a grep, and then the
  convention doesn't produce a graph but a feeling
- And: a project with an outdated template gets the new one on its next
  adoption

### S60 — Acceptance criteria in the template are named `AC<n>`
**Covers:** F13
- Given: `templates/ISSUE_TEMPLATE/work-item.md`
- When: an issue is created from the template
- Then: the acceptance criteria are numbered `AC<n>`, not `S<n>`
- And: as long as an issue names its own criteria `S1`, every grep for
  scenario references also hits the issue itself — then link 2 isn't
  verifiable
- And: this scenario belongs to W18 and awaits the outcome of W17; if that
  rename turns out differently, this scenario changes along with it
- And: this covers **F13**, not F14. The unsplit S31 carried `Dekt: F14`
  for both claims, but F13 point a is where the `AC<n>` rename is decided;
  F14 is exclusively about the blocking edges
- And: `S<n>` may only still appear in the template as a reference to
  `TEST-SCENARIOS.md`, not as its own numbering

### S61 — The scenario template carries the coverage field and the grammar
**Covers:** F13
- Given: `templates/TEST-SCENARIOS.md`
- When: a project scaffolds with it
- Then: every example scenario shows a `**Covers:**` field directly under
  its heading
- And: the token grammar `^[A-Z]{1,2}[0-9]+[a-z]?$` is stated explicitly
  alongside it, with `S2b` as an example — a template that models the
  form without naming it doesn't teach the exception, and then the first
  `S2b` runs into an enforcement nobody saw coming
- And: the template shows the field with a placeholder, not a made-up ID
  that means nothing

### S32 — Every active entry has a PR linkback
**Covers:** F15
- Given: `CHANGES.md` with an entry with no `**PR:**` field
- When: `./check` runs
- Then: exit ≠ 0, with that entry's ID in the message

### S33 — The CHANGELOG names the required manual actions
**Covers:** F15
- Given: this release's first `CHANGELOG.md` entry
- When: it's read
- Then: it names both `adopt.sh` per project and `adopt.sh --user` per machine

### S35 — `check` reports what it couldn't check
**Covers:** F1
- Given: a file `check` should examine but can't read (e.g. a script with
  no read permission)
- When: `./check` runs
- Then: a warning appears naming the file
- And: the file doesn't silently disappear from the check — silent
  degradation is the failure mode this repo pays for most dearly

---

## Issue templates and release (continued)

### S34 — The README describes the new structure
**Covers:** F16
- Given: `README.md` after this release
- When: the table of contents is read
- Then: it has rows for `skills/`, `hooks/`, `lib/`, `nfr/`, `test/`, `check`,
  and `CHANGES-ARCHIEF.md`
- And: the count of non-functional questions is fifteen, not five

---

## Coverage outside the agentic loop

### S48 — The CI template validates pull requests and `main`
**Covers:** F17
- Given: a project scaffolding with `templates/ci.yml`
- When: a pull request is opened and a push to `main` happens
- Then: the workflow runs in both cases
- And: it still calls only `check` — the CI convention itself doesn't
  change, only when it fires

### S49 — A custom `ci.yml` isn't overwritten
**Covers:** F17
- Given: a project with a hand-written `ci.yml` that deviates from the template
- When: `adopt.sh` runs again
- Then: that file stays untouched — `scaffold_if_missing` only writes what's
  missing
- And: the deviation doesn't stay invisible. The adoption registry asks the
  `ci-on-pr-and-main` question, and keeps asking until the project answers
  it. That's the mechanism, not a one-time notice in `adopt.sh` that
  appears once and is gone

### S50 — The guard also applies outside Claude
**Covers:** F17
- Given: an adopted project with `main` checked out and the git hooks installed
- When: `git commit` or `git push origin main` is called directly in a
  shell, so with no Claude involved
- Then: it's refused, with the same message as the `PreToolUse` guard
- And: the *rule* lives in exactly one place — which branch is protected
  and what the message says comes from the same source as the
  `PreToolUse` guard. The parsing layer necessarily differs: a native
  `pre-commit` gets no command string to tokenize

### S51 — An existing git hook isn't silently replaced
**Covers:** F17
- Given: a project with its own `pre-commit` hook not from this repo
- When: `adopt.sh` runs
- Then: that hook isn't overwritten without notice
- And: running twice produces an identical tree — hooks don't stack

### S52 — A commit on `main` outside a PR is reported
**Covers:** F17
- Given: a commit pushed directly to `main`
- When: the CI workflow runs
- Then: it fails, with the commit in question in the message
- And: a merge commit that does come from a pull request goes through
- And: the check applies both in `spec-driven-guardrails` itself and in
  every project scaffolding with `templates/ci.yml` — a rule this repo
  imposes on others but dodges itself isn't a rule

### S53 — The check judges the push, not the history
**Covers:** F17
- Given: earlier commits on `main` that don't meet the requirement
- When: the workflow runs on a new push
- Then: only that push is judged
- And: the check therefore isn't red on day one — a retrofit that always
  fails teaches you exactly one thing, and that's to ignore the message

### S58 — A git hook that can't render its verdict lets things through
**Covers:** F17
- Given: an adopted project where the git hook can't run its decision
  logic — the source script is missing, or the required interpreter isn't
  there
- When: `git commit` or `git push` is called
- Then: a loud warning appears saying the check was **not** performed
- And: the command goes through, same as S14 — a broken guard must never
  block the work, and especially not outside Claude, where no agent is
  watching who could interpret the message

### S59 — A CI check that can't render its verdict fails
**Covers:** F17
- Given: the workflow from S52 can't establish the origin of a push to
  `main` (no API response, missing permissions)
- When: the check runs
- Then: it fails, with the reason given
- And: that's deliberately the reverse of S58. A local hook that fails
  holds back work that could already be legitimate; a CI check that goes
  silently green reports that nothing's wrong while it knows nothing — and
  that's exactly the silent degradation this repo pays for most dearly

### S72 — Existing projects still get the main-via-PR question
**Covers:** F17
- Given: a project with a `package.json` and an already-existing `ci.yml`
  that doesn't call `check-main-via-pr.sh` (`scaffold_if_missing` leaves
  such a file alone — the same pattern as `ci-link-3-hard-block` in W19b)
- When: `pending-changes.sh` runs
- Then: a new entry appears as pending
- And: a project with no `package.json` doesn't get that question

### S80 — The check job has read access to pull requests and issues
**Covers:** F17
- Given: `templates/ci.yml` and this repo's own `.github/workflows/ci.yml`
- When: both files are checked for what token scope the `check` job gets
- Then: `pull-requests: read` applies to that job, at job or workflow level
- And: without that scope, `check-pr-issue-link.sh` (link 3) and
  `check-main-via-pr.sh` run under the default, minimal token scope, and
  both fail — not incidentally, as issues #83 and #85 both showed
- And: `issues: read` applies too — a separate gap: `closingIssuesReferences`
  (which `check-pr-issue-link.sh` reads) is about the linked issue itself,
  not the PR, and `pull-requests: read` alone turned out not to be enough
  there. Without `issues: read` the lookup silently returns an empty list,
  even when the link genuinely exists (discovered on PR #105 for this
  repo's own workflow, issue #99; the same gap applied to
  `templates/ci.yml`, issue #106)

### S83 — Link 3 also runs in this repo's own CI
**Covers:** F17
- Given: `.github/workflows/ci.yml`
- When: a pull request against this repo is opened
- Then: `check-pr-issue-link.sh` runs, with both `pull-requests: read`
  (S80) and `issues: read` — the latter is a separate gap: without it,
  `closingIssuesReferences` silently returns an empty list, even when the
  link genuinely exists (discovered on PR #105, run 34234378780)
- And: a PR with no `Closes #N` (or an equivalent link) in the PR body
  fails visibly in CI, while the PR is still open — not only visible
  afterward via `pending-changes.sh` or a manual `pre-merge-review`, as
  happened with PRs #96/#97 (2026-09-08)

---

## Self-adoption

### S81 — spec-driven-guardrails can adopt itself
**Covers:** F7, F8
- Given: a sandbox copy of this repo, used as both
  `SPEC_DRIVEN_GUARDRAILS_DIR` and the adoption target
- When: `adopt.sh` runs against it
- Then: it actually adopts — `CLAUDE.md` and `.claude/settings.json` are
  symlinks to its own `WORKFLOW.md` and `settings/session-hooks.json` —
  instead of showing the "no adoption needed" refusal
- And: no existing, committed file (`PRD.md`, `TEST-SCENARIOS.md`,
  `check`, ...) changes
- And: the git-guardrails hook is functional afterward: a fabricated
  `PreToolUse` call proposing a direct `git push origin main` is refused —
  the same check adopted projects get
- And: the native git hooks are also installed and refuse a direct
  `git push origin main` outside Claude Code (same pattern as S50)
- And: a second `adopt.sh` call is idempotent — no errors, no duplicate
  `.gitignore` lines

### S82 — A fresh WORKFLOW-ADOPTION.md names the right repo
**Covers:** F3
- Given: a freshly adopted project
- When: `adopt.sh` creates `WORKFLOW-ADOPTION.md`
- Then: the header refers to `spec-driven-guardrails`
- And: not to `claude-workflow` — the name from before the W32 rename (#56)

---

## Installation

### S84 — install.sh installs a pinned version, not the current main
**Covers:** F17
- Given: a clone of this repo with a tag on an older state, followed by a
  newer commit
- When: `install.sh <tag>` runs against it
- Then: the checkout ends up on the pinned commit, not the newer content
- And: a dirty working tree (uncommitted changes) is refused, with
  nothing checked out — otherwise `git checkout` would silently discard
  them
- And: an unknown tag fails with a clear message
- And: with no argument, the latest tag is used, explicitly reported on
  stdout — never silently

---

## Securing work without a session end

### S54 — Session start reports that `main` is checked out
**Covers:** F18
- Given: an adopted project with `main` checked out
- When: a session starts
- Then: a message appears naming `main` and suggesting `git checkout -b`
- And: that's before there's any work — the commit block from F7 only
  kicks in afterward, once branching no longer feels free

### S55 — On a feature branch, session start reports nothing
**Covers:** F18
- Given: the same project on `feature/<name>`
- When: `pending-changes.sh` runs
- Then: no message about the branch appears
- And: exit 0 and nothing on stderr, per S43 — a hook that produces noise
  gets dismissed and becomes worthless as a result

### S56 — A successful commit is pushed immediately
**Covers:** F18
- Given: a feature branch with a new commit
- When: the commit succeeds
- Then: the current branch is on `origin`
- And: the work is thereby safe the moment it's recorded, rather than
  only on a clean exit — which `SessionEnd` gives no guarantee of

### S57 — A failed commit or missing network pushes nothing
**Covers:** F18
- Given: a `git commit` that fails (nothing to commit, aborted editor), or
  an environment with no connection or no `origin`
- When: the hook runs
- Then: nothing is pushed, and nothing happens to `main` either way
- And: the hook reports it and doesn't hold up the work — a push that
  doesn't succeed must never block a command

### S85 — A project on the pre-migration format is reported per row, with an issue
**Covers:** F6
- Given: a project with a `WORKFLOW-ADOPTIE.md` (no `WORKFLOW-ADOPTION.md`)
  with rows in the old `ja`/`nee` format
- When: `pending-changes.sh` runs
- Then: every row on the old format is reported individually, without an
  already-answered row wrongly counting as a pending question
- And: an issue is created on the project's own repo, with a
  machine-recognizable marker
- And: if `pending-changes.sh` runs again while that issue is already
  open, no second issue is created (idempotent, marker-driven)
- And: if `project_dir` isn't its own git root (e.g. a directory inside a
  *different* repo, like the frozen baseline fixtures), `gh` isn't
  called at all — never write to the wrong repo

### S86 — The SessionStart/SessionEnd hooks work independently of the incidental cwd
**Covers:** F6, F18
- Given: `settings/session-hooks.json`'s `SessionStart` and `SessionEnd`
  commands, called from a directory other than the project itself, with
  `CLAUDE_PROJECT_DIR` correctly set — the PreToolUse/PostToolUse hooks
  already handle this correctly (S44), but `SessionStart`/`SessionEnd`
  didn't: a relative `readlink .claude/settings.json` respectively a bare
  `git` call with no `-C` then silently produces nothing, with no message
  at all — found during W42/#114's rollout to tennis-admin, where exactly
  this made both the pending-changes notice and the migration notice fail
  to appear
- When: `git fetch origin`, the `pending-changes.sh` call, and
  `git push origin HEAD` (on a non-`main` branch) run from that other
  directory
- Then: all three do exactly the same as if they'd run from the project
  directory itself — the fetch/push hit the right remote, and the message
  appears
- And: the original, cwd-dependent form of each command demonstrably fails
  the same scenario (silently doing nothing), confirming this was a real
  regression, not a coincidence

### S87 — A leftover Dekt: field doesn't silently disappear
**Covers:** F13
- Given: a `TEST-SCENARIOS.md` or `PRD.md` with a `**Dekt:**` field from
  before the Covers: cutover (W42/#114) — the token `check-traceability.sh`
  itself used before this migration
- When: `check-traceability.sh` runs on that project
- Then: it explicitly reports which file still carries a pre-migration
  Dekt: field and how many, referencing #114
- And: that field isn't silently parsed as a valid Covers: reference, and
  doesn't count as "this project doesn't use the convention yet" either —
  both would make the leftover token invisible

### S88 — No Dutch outside layer C
**Covers:** F13
- Given: this repo, after W38–W42, with `check-no-dutch.sh`'s fixed
  marker list and its two separate exclusion lists — permanent (layer C,
  historical, epic #65, `USER-CLAUDE.md`) and pending (tracked in
  #136/#137/#138, meant to shrink once those close)
- When: `check-no-dutch.sh` runs
- Then: no file outside those two lists still carries a word from the
  marker list
- And: `./check` calls this script itself (step 3c) and fails hard if it
  finds anything — not fail-open, since this is a repo-own check with no
  network dependency
- And: the script excludes itself from its own scan — the marker list it
  carries isn't untranslated prose

### S89 — An answer under a pre-rename NFR ID is still recognized
**Covers:** F3, F11
- Given: a project's `WORKFLOW-ADOPTION.md` answers `yes` under
  `spec-data-integriteit`, the pre-#156 ID (the NFR was later renamed to
  `spec-data-integrity`)
- When: `pending-changes.sh` runs
- Then: `spec-data-integrity` is not reported as pending — the old-ID row
  satisfies the current question, the same "never rewrite what a project
  already recorded" treatment W42/#114 gave the `ja`/`nee` format
- And: `pre-merge-review`'s `scope.sh` still resolves a readable heading
  for the row via the alias, instead of falling back to the bare ID

### S90 — CHANGES.md.snapshot stays in step with CHANGES.md
**Covers:** F2
- Given: `test/fixtures/baseline/CHANGES.md.snapshot`, the frozen
  human-readable reference copy of `CHANGES.md` from when the golden sets
  were measured
- When: `./check` runs
- Then: the snapshot is byte-identical to the live `CHANGES.md` — the same
  smoke-detector treatment S66 already gives `nfr.snapshot/`
- And: a diverged snapshot fails loudly, naming the exact diff, instead of
  drifting silently (found via #160: 562 lines of undetected drift since
  the snapshot was last refreshed in #127, long before three later
  translation PRs rewrote the live file)

### S91 — The SessionEnd push hook carries an explicit, realistic timeout
**Covers:** F18
- Given: `settings/session-hooks.json`'s `SessionEnd` push hook
- When: the hook configuration is read
- Then: it carries an explicit `timeout` field, generous enough for a
  network push (at least 10s) and within Claude Code's documented 60s
  ceiling for the shared `SessionEnd` budget
- And: `async` is not `true` — a failed push must stay visible, not
  silently backgrounded (found via #133: the default 1.5s `SessionEnd`
  budget cancelled a real `git push` more often than it succeeded)

### S92 — `check` runs this repo's own traceability check (link 1)
**Covers:** F13
- Given: this repo's own `check-traceability.sh`, self-adopted (#98) but
  never invoked by `./check` — found via #147, when S85's own malformed
  `**Covers:** F6, W42/#114` field sat undetected until the script was
  run by hand
- When: `./check` runs against a project whose `TEST-SCENARIOS.md` has an
  invalid `Covers:` token
- Then: `check` fails and names the broken token, instead of reporting
  green while schakel 1 is silently broken
- And: on this repo's own, currently-clean `PRD.md`/`TEST-SCENARIOS.md`,
  `./check` still runs `check-traceability.sh` and stays green — this is
  wiring the check in, not fixing a pre-existing gap in this repo's own
  coverage

### S93 — A yes-answered spec-* NFR without its PRD.md subsection is warned about
**Covers:** F4
- Given: a `spec-*` row answered `yes`/`ja` in `WORKFLOW-ADOPTION.md`,
  with no matching `### <heading>` subsection (or `<!-- nfr: id -->`
  anchor) yet in `PRD.md` — found during tennis-invoicing's adoption
  catch-up (PR TiesL/tennis-invoicing#18/#19), where the gap only stayed
  visible because someone happened to add a Notes explanation by hand
- When: `check` runs
- Then: it prints an explicit warning naming the row and its missing
  subsection, without failing the build — a freshly-answered `yes` gets a
  short, visible grace period
- And: the warning appears even when the row's Notes column explicitly
  references an open issue — the whole point is that the check no longer
  depends on someone remembering to add that note (AC3)
- And: a row answered `yes` whose subsection already exists, and a row
  answered `no`/`nee`, are both silent

### S94 — templates/ARCHITECTURE.md documents the multiple-decisions pattern
**Covers:** F1
- Given: `templates/ARCHITECTURE.md`, written for the common case of one
  project with one architecture decision
- When: a project needs to record several related decisions in one
  document — observed in `tennis-invoicing` (platform choice, a
  data-registration pattern, a dual-entrypoint structure), which had to
  invent the pattern itself
- Then: the template documents that pattern explicitly (repeat the
  decision/criteria/options/comparison block per decision, keep
  requirements/boundaries/dependencies/revisit-triggers shared), naming
  `tennis-invoicing`'s own document as the concrete reference
- And: the single-decision skeleton is unchanged — this is an addition,
  not a restructuring of the existing case

### S95 — An answer under a pre-rename CHANGES.md entry ID is still recognized
**Covers:** F3
- Given: a project's `WORKFLOW-ADOPTION.md` answers `yes` under
  `ci-conventie`, the pre-#175 ID (the entry was later renamed to
  `ci-convention`) — the exact case found in `tennis-admin`'s own
  frozen fixture
- When: `pending-changes.sh` runs
- Then: `ci-convention` is not reported as pending — the old-ID row
  satisfies the current question, the same alias treatment #156 gave
  the renamed `nfr/` IDs

### S96 — Branch creation without an issue number is blocked
**Covers:** F19
- Given: a `git checkout -b`/`git switch -c` for a `feature/`/`fix/`
  branch whose name doesn't match `^(feature|fix)/[0-9]+-[a-z0-9-]+$`
- When: the command runs
- Then: `git-guardrails` blocks it, pointing at creating the issue
  first and naming the branch after its number

### S97 — Branch creation against a closed or nonexistent issue is blocked
**Covers:** F19
- Given: a branch name that does match the pattern, but the numbered
  issue is closed or doesn't exist (`gh issue view <n> --json state`)
- When: the command runs
- Then: `git-guardrails` blocks it

### S98 — Branch creation against a real, open issue succeeds
**Covers:** F19
- Given: a branch name matching the pattern, and the numbered issue is
  open
- When: the command runs
- Then: the command goes through, unblocked

### S99 — The issue-first guard fails open without gh or network
**Covers:** F19
- Given: `gh` is missing, or the `gh issue view` call fails (no
  network/access)
- When: a branch name matching the pattern is created
- Then: a warning appears that the issue-existence check was skipped
- And: the command is allowed

### S100 — Non-Claude commits are covered by the native pre-commit hook
**Covers:** F19
- Given: a first commit on a new non-main branch made outside Claude
  Code (plain terminal, IDE — `git-guardrails`' PreToolUse hook never
  runs there)
- When: the branch name doesn't match the required pattern
- Then: the native `pre-commit` hook blocks the commit, syntax only, no
  network call

### S101 — Existing branches and plain checkouts are unaffected
**Covers:** F19
- Given: a branch that already exists (created before this change, or
  on another machine)
- When: it's checked out without `-b`/`-c` (`git checkout <branch>`)
- Then: nothing is blocked — only creation of a *new* branch is judged

### S102 — Closing the last open work item closes its epic
**Covers:** F20
- Given: an open epic, and two issues naming it via `**Epic:** #<epic>`,
  one already closed
- When: the second (last open) one closes
- Then: the epic closes automatically, with a comment naming both
  issues

### S103 — An open sibling keeps the epic open
**Covers:** F20
- Given: an open epic and two issues naming it, both still open
- When: one of them closes
- Then: the epic stays open — no close attempt

### S104 — A non-work-item issue closing does nothing
**Covers:** F20
- Given: an issue with no `**Epic:**` field in its body
- When: it closes
- Then: no epic is touched

### S105 — An already-closed epic is left alone
**Covers:** F20
- Given: an epic that's already closed
- When: another issue naming it closes (a late or duplicate trigger)
- Then: nothing happens — no duplicate close attempt, no duplicate
  comment

### S106 — A malformed or dangling Epic reference doesn't crash the mechanism
**Covers:** F20
- Given: a work item whose `**Epic:** #<n>` names itself, or names an
  issue number that doesn't exist
- When: it closes
- Then: the run completes without erroring and closes nothing

### S107 — A failed close is reported, not treated as success
**Covers:** F20
- Given: every referencing issue is closed, but the `gh issue close`
  call itself fails (network blip, permissions)
- When: the last work item closes
- Then: the mechanism exits non-zero — not silently treated as a
  successful close

### S108 — A stray commit-level Closes is blocked
**Covers:** F21
- Given: a PR whose own `closingIssuesReferences` names issue A, but
  one of its commits' messages contains a closing keyword for issue B
  (B ≠ A)
- When: `gh pr merge` is called
- Then: the command is blocked, naming issue B and the offending
  commit

### S109 — A commit-level Closes that agrees with the PR is not blocked
**Covers:** F21
- Given: a PR whose own `closingIssuesReferences` and every
  commit-level closing keyword name the same issue(s)
- When: `gh pr merge` is called
- Then: the command is not blocked by this check (the existing
  marker/CI checks still apply as normal)

### S110 — The stray-Closes check fails open without gh or network
**Covers:** F21
- Given: `gh` is missing, or `gh pr view`'s commit lookup fails (no
  network/access)
- When: `gh pr merge` is called
- Then: a loud warning appears that this check was skipped, and the
  command is allowed — independent of whether the review-marker/CI
  checks already passed

### S111 — The escape hatch covers the stray-Closes check too
**Covers:** F21
- Given: `CLAUDE_WORKFLOW_MERGE_GUARD_OFF=1` and a genuine stray
  commit-level Closes
- When: `gh pr merge` is called
- Then: the merge proceeds

### S112 — A reintroduced printf/echo-into-grep-q is caught, wired into check
**Covers:** F22
- Given: a script that pipes `printf`/`echo` into `grep -q...` (the
  SIGPIPE/pipefail race pattern)
- When: `check-no-sigpipe-race.sh` runs, directly or via `check`
- Then: it's reported as an error, naming the file and line — and
  `check` fails as a whole, the same as any other hard error

### S113 — Comments describing the pattern, and the script's own source, are excluded
**Covers:** F22
- Given: a comment line that merely documents the anti-pattern (as
  several fixed files now do), and the checker script's own source
- When: `check-no-sigpipe-race.sh` runs
- Then: neither is reported — only executable, non-comment code counts

### S114 — Any producer counts, not just printf/echo
**Covers:** F22
- Given: a non-printf/echo producer (e.g. `cat`) piped into `grep -q`
- When: `check-no-sigpipe-race.sh` runs
- Then: it's reported the same as a printf/echo instance would be

### S115 — A combined flag cluster is still caught
**Covers:** F22
- Given: `grep -qx`/`-qF` (a combined flag cluster, not a bare `-q`)
  piped into from a producer
- When: `check-no-sigpipe-race.sh` runs
- Then: it's reported

### S116 — A boolean || between two file-reading greps is not a false positive
**Covers:** F22
- Given: `grep -qx a "$f" || grep -qx b "$f"` — two independent greps,
  each reading a named file directly, no producer process and no pipe
  at all
- When: `check-no-sigpipe-race.sh` runs
- Then: it's not reported

### S117 — A pipe split across a backslash-continued line is still caught
**Covers:** F22
- Given: a producer and `| grep -q` split across two physical lines via
  a trailing backslash
- When: `check-no-sigpipe-race.sh` runs
- Then: it's reported, at the line where the logical line starts

### S118 — A missing python3 is reported visibly, not silently skipped
**Covers:** F22
- Given: no `python3` on `PATH`
- When: `check` runs
- Then: it prints a visible line saying the SIGPIPE/pipefail race
  check was skipped — `check` only prints a sub-script's own output
  on failure, so a successful-but-skipped run needs its own line

### S119 — A marker for an older commit is not accepted for a newer one
**Covers:** F23
- Given: a PR with a review marker posted for an older commit than the
  PR's current HEAD
- When: `gh pr merge` is called
- Then: the merge guard blocks — the same message as no marker at all

### S120 — stdout/stderr are kept separate when consulting the marker
**Covers:** F23
- Given: `gh pr view`'s response includes routine stderr noise
  alongside a valid, matching marker on stdout
- When: `gh pr merge` is called
- Then: the marker is still recognized — stream contamination must
  not silently fail this check open

### S121 — A reintroduced apostrophe-closed block is caught
**Covers:** F24
- Given: a `python3 -c '...'` block containing prose with an
  apostrophe (`it's`, `doesn't`, `#227's`), closing the bash string
  early
- When: `check-no-quote-break.sh` runs, directly or via `check`
- Then: it's reported as an error, naming the file and the line
  where the string actually closed

### S122 — Both legitimate closing shapes stay clean
**Covers:** F24
- Given: a `python3 -c '...'` block closing on its own (`')"'`), and
  one closing with trailing arguments (`' "$var" <<<"$data")"'`) —
  both with the closing `'` as the first character of its line
- When: `check-no-quote-break.sh` runs
- Then: neither is reported

### S123 — Wired into check as a hard error, visible without python3
**Covers:** F24
- Given: the script's own presence
- When: `check` runs, with and without `python3` on `PATH`
- Then: with `python3`, a reintroduced quote-break fails `check` as a
  hard error; without it, `check` prints a visible skip line rather
  than silently omitting the check

### S124 — The real repo's two copies are already identical
**Covers:** F25
- Given: `check-traceability.sh` and `templates/check-traceability.sh`
  as they stand today
- When: `check` runs
- Then: no drift is reported

### S125 — A drift is caught, and fixing it clears the error
**Covers:** F25
- Given: the root copy has been edited to differ from the template
- When: `check` runs
- Then: it fails, naming both files
- And: copying the template back over the root copy makes `check`
  pass again

### S126 — Gated on both files existing
**Covers:** F25
- Given: a target missing one or both of the two files
- When: `check` runs
- Then: the sync check doesn't run at all — no error, no false pass
  claim

### S130 — Every pipeline stage's model choice is machine-checkable, not just Review
**Covers:** F27
- Given: a PR and the issue(s) it closes, each carrying zero or more
  `<!-- model-record: stage=... -->` markers across their comments, in a
  project that does not answer `process-multi-agent-roles` yes (the
  opted-in additions are S183)
- When: `model-record-gate.sh <pr-number>` runs
- Then: a missing stage among Discovery/Planning/Test/Implementation/Review
  is reported, one line per stage; nothing is reported once all five are
  present; without `gh` the gate fails open with a warning, not a block
- And (#424, which removed effort from the floor, A33/A33a): Review and
  Implementation recording the identical model at a LOWER legacy Review
  effort is NOT reported (the effort attribute is read and ignored), nor is
  it at equal or higher effort; a legacy `same-model-exception` field on
  Review's marker is ignored as well; the floor rule itself is S189

### S131 — A review finding surfaces if it silently vanishes between fresh-context rounds
**Covers:** F28
- Given: a PR's previous `pre-merge-review:done` comment left a finding
  marked `<!-- finding:<slug> status=open -->`
- When: `finding-carryforward-gate.sh <pr-number>` runs after a new
  `pre-merge-review:done` comment is posted
- Then: the slug is reported if it's missing from the new comment, and
  not reported if the new comment re-flags it as still open or marks it
  `status=resolved`; with only one review round so far, or without `gh`,
  nothing is reported

### S132 — The 4th traceability link: an issue's own AC/Covers/work-item structure
**Covers:** F29
- Given: the issue(s) a PR closes
- When: `issue-structure-gate.sh <pr-number>` runs
- Then: a work item issue with no `### AC<n>` heading, or no `**Covers:**`
  field, is reported (one finding per missing piece); an epic issue whose
  Work items list has no real `#<n>` entry (only the unfilled template
  placeholder) is reported; a well-formed issue produces no findings;
  without `gh`, the gate fails open with a warning

### S133 — The native commit-msg hook rejects a Co-Authored-By trailer
**Covers:** F17
- Given: a commit message carrying a `Co-Authored-By:` trailer (any case),
  written directly into `-m` rather than added by Claude Code's own
  commit template
- When: the commit is attempted
- Then: it's blocked, naming the trailer; a message with no trailer
  proceeds; the `CLAUDE_WORKFLOW_GUARDRAILS_OFF` escape hatch still lets
  it through

### S136 — CI scaffolding is gated on an executable check, not package.json
**Covers:** F9
- Given: a project with an executable `check` at its root but no
  `package.json`
- When: `adopt.sh` runs
- Then: `ci.yml`, `check-pr-issue-link.sh`, and `check-main-via-pr.sh` are
  all scaffolded; a project with `package.json` alone and no executable
  `check` gets none of them, with `adopt.sh` printing why, not silently;
  the scaffolded `ci.yml` calls `./check` directly (never `npm run
  check`), with the npm setup steps conditional on `package.json` existing

### S135 — CI-enforcement policy for a genuinely code-less project
**Covers:** F8
- Given: `CHANGES.md`'s `ci-gate-on-merge` entry
- When: read
- Then: it states the policy for a project with no check command and no
  CI at all — `no` (not yet), not `yes`, since `yes` claims real CI
  gating is happening — and points at
  `adoption-postcondition-gate.sh` (#239) as the mechanical backstop for
  a project that answers `yes` anyway

### S134 — A managed path already tracked before adoption is untracked
**Covers:** F30
- Given: `CLAUDE.md` committed as a real, tracked file before `adopt.sh`
  ever ran
- When: `adopt.sh` runs
- Then: the path is no longer tracked (`git rm --cached`), the working-tree
  file is kept (now the real symlink `adopt.sh` creates, never deleted),
  and `.gitignore` lists it; a project where the path was never tracked is
  unaffected

### S137 — A "no" answer distinguishes a permanent decline from "not yet"
**Covers:** F9
- Given: `adopt.sh`'s seeded `WORKFLOW-ADOPTION.md` header
- When: read
- Then: it explains that `no` covers two cases — a permanent decline, or
  "not yet" (applicable, precondition doesn't hold) with a concrete
  trigger to revisit, same shape as `PRD.md`'s Technical debt table —
  documented consistently in the seeded header, this repo's own
  `WORKFLOW-ADOPTION.md`, and the `adoption-registry` skill

### S138 — Adoption postcondition gate: a "yes" answer is checked, not trusted
**Covers:** F9
- Given: `WORKFLOW-ADOPTION.md` rows answered `yes` for `traceability-link-1`
  and `ci-gate-on-merge`
- When: `adoption-postcondition-gate.sh <project_dir>` runs
- Then: a finding is reported for each row whose actual precondition
  doesn't hold (no `check-traceability.sh`, not wired into `check`; no CI
  workflow, or one that never invokes `check`); no finding when both
  genuinely hold; a `no — not yet` row (S137) is never checked at all

### S139 — .github/ISSUE_TEMPLATE/ is gated on process-issue-tracking, not unconditional
**Covers:** F9
- Given: a fresh project with `process-issue-tracking` unanswered
- When: `adopt.sh` runs
- Then: `.github/ISSUE_TEMPLATE/` is not created; once the row is answered
  `yes` (current or pre-migration `ja` format, either id spelling), the
  next run creates it; an already-existing directory is still always
  refreshed regardless of the row's answer (S31/AC3, unaffected)

### S140 — pre-merge-review documents the pending adoption gate
**Covers:** F10
- Given: `skills/pre-merge-review/SKILL.md`
- When: read
- Then: it documents running `pending-changes.sh` as a PR-time finding,
  not only relying on the `SessionStart` notice a session can scroll past

### S141 — A materially tightened row re-surfaces for a project that already answered it
**Covers:** F9
- Given: a project's `WORKFLOW-ADOPTION.md` answers a row `yes` with no
  `(meaning v<N>)` marker, and `CHANGES.md`'s own `**Meaning version:**`
  for that row is now higher than 1
- When: `pending-changes.sh <project_dir>` runs
- Then: the row is reported separately from "never answered", naming the
  old and new version; re-confirming with the current version marker
  quiets it; a row whose entry was never touched by a version bump never
  resurfaces, regardless of how it was answered
- And (#392 and #424, `quality-review-before-merge` now at meaning v4): a row
  answered with no marker reports "answered under meaning v1, now v4", a
  row re-confirmed at `(meaning v2)` or `(meaning v3)` reports "answered
  under meaning v2, now v4" / "answered under meaning v3, now v4" in the
  "meaning has changed" block (not in the never-answered list), and only a
  `(meaning v4)` row is quiet; the `process-model-choice` equivalent is S239

### S142 — changes_meaning_version's field extraction, edge cases
**Covers:** F3
- Given: synthetic `CHANGES.md` fixtures with the field on its own line,
  on a continuation line, with non-canonical spacing (extra space after
  the dash, a leading space before it), absent entirely, malformed
  (non-numeric content), or a continuation line whose prose happens to
  contain an unrelated digit (an issue number)
- When: `changes_meaning_version <id> <file>` runs
- Then: each resolves to the correct version; absent resolves to 1;
  malformed resolves to empty (distinct from absent, so a caller can
  detect it), not silently defaulted to 1; an issue number in a
  continuation line's prose is never misread as the version

### S143 — A narrowed predicate re-surfaces a row for a project it no longer applies to
**Covers:** F9
- Given: a project's `WORKFLOW-ADOPTION.md` answers a row `yes` with no
  `(meaning v<N>)` marker, `CHANGES.md`'s own `**Meaning version:**` for
  that row is now higher than 1, and the row's `Applies if` predicate no
  longer holds for this project (e.g. `ci-convention`/`has-check-command`
  for a project with no executable `check`, mirroring #248's real
  narrowing of the CI-adoption rows from `has-package-json`)
- When: `pending-changes.sh <project_dir>` runs
- Then: the row is reported separately, both from "never answered" and
  from the "meaning has changed" (still-applies) report, naming the old
  and new version and stating the predicate no longer matches; the same
  version bump for a project the predicate *still* holds for reports
  through the existing "meaning has changed" path instead, not this one;
  re-confirming with the current version marker quiets it, same as S141

### S144 — hooks/pre-commit runs the declared check-commit within a budget, and never ./check
**Covers:** F17
- Given: an adopted project on a feature branch, whose `./check` (when
  present) exits 1 and writes a marker, so any run of it at commit time
  is visible (issue #378, A21-A23; originally #263)
- When: a commit is attempted
- Then: with an executable `check-commit` that exits 0, the commit goes
  through and the full `./check` did not run; with one that exits 1
  within the budget (also after a delay), the commit is blocked, the
  block names `check-commit` and shows its own output, and the full
  `./check` did not run
- And: with only `./check` (no executable `check-commit`, including a
  `check-commit` that is not executable), the commit goes through, exactly
  one line says the full `./check` runs in CI and names `ci-commit-check`,
  and `./check` was not invoked
- And: with neither file, the existing warning about no executable
  `./check` appears and no CI line does
- And: the `CLAUDE_WORKFLOW_GUARDRAILS_OFF` escape hatch also covers this
  guard, and `check-commit` is then not run
- And: with `COMMIT_CHECK_BUDGET=2` and a `check-commit` that sleeps (with
  a child and a grandchild process), the commit goes through within a few
  seconds with a warning that mentions the budget and CI, the full
  `./check` did not run, and no process of `check-commit` survives
- And: `check-commit` receives no arguments, runs at the project root and
  sees none of git's repo-local environment variables

### S145 — hooks/pre-push runs gitleaks, blocking on a real finding
**Covers:** F17
- Given: an adopted project pushing to a real remote, with `gitleaks` on
  `PATH`
- When: `git push` runs
- Then: a clean scan doesn't block; a finding blocks the push and shows
  gitleaks' own output; no `gitleaks` on `PATH` at all fails open, with a
  loud warning that the push-time scan was skipped; the existing
  `CLAUDE_WORKFLOW_GUARDRAILS_OFF` escape hatch also covers this guard —
  unconditional on repo visibility throughout, no network lookup involved

### S146 — A gitleaks scan runs in CI too, independent of hooks/pre-push
**Covers:** F17
- Given: this repo's own `.github/workflows/ci.yml` and the
  `templates/ci.yml` adopted projects copy
- When: read
- Then: both include an unconditional "Secret scan (gitleaks)" step
  calling `gitleaks git`, and a `fetch-depth: 0` checkout so the scan
  sees full history, not just the shallow-clone tip — a backstop for the
  pre-push hook, which is bypassable with `--no-verify`

### S147 — check-scenario-file-sync.sh enforces the 1:1 file-to-heading correspondence
**Covers:** F32
- Given: `test/cases/*.sh` files (each with a header comment naming the
  ID(s) it covers, ranges with `-`, discrete lists with `,`) and
  `TEST-SCENARIOS.md`'s `### <ID>` headings
- When: `check-scenario-file-sync.sh` runs
- Then: a file claiming an ID with no matching heading is reported; a
  heading with no file claiming it is reported (unless on the curated
  `pending_excluded` list); the same ID claimed by more than one file is
  reported; the same heading appearing more than once is reported; a
  range header expands to every ID in between, not just its two named
  endpoints

### S148 — check-traceability.sh's no-ID-headings warning doesn't mask other checks
**Covers:** F13
- Given: a `PRD.md` with no ID headings (a warning, not an error — one
  real adopted project is exactly this case) and a `TEST-SCENARIOS.md`
  with a leftover `**Dekt:**` field
- When: `check-traceability.sh` runs
- Then: the Dekt: leftover is still reported and the exit status is
  non-zero, and the "PRD.md has no ID headings" warning still appears
  unchanged; `PRD.md`'s own `Covers:` token resolution against
  `TEST-SCENARIOS.md`'s IDs still runs (doesn't depend on PRD IDs); a
  scenario's own `Covers:` token pointing at a PRD functionality is not
  wrongly checked against an empty PRD-ID set — that direction alone
  stays skipped, since it's genuinely inapplicable without PRD IDs

### S149 — wait-for-ci.sh enforces the 5min-then-1min CI-polling cadence
**Covers:** F33
- Given: a PR whose CI run is initially pending
- When: `wait-for-ci.sh <pr-number>` runs
- Then: it doesn't query CI status before the initial wait elapses; it
  polls repeatedly while any check is still pending, and stops once
  every check reaches a terminal state; it exits 0 and reports "all
  checks passed" when every terminal state is a passing one (SUCCESS,
  SKIPPED, NEUTRAL); it exits non-zero and prints each check's name and
  state when any terminal state isn't; with no `gh` on `PATH`, or a
  failed lookup, it exits non-zero rather than silently reporting
  success; a PR with zero checks at all is reported as inconclusive
  (non-zero), not as "all checks passed" — there's nothing to have
  passed

### S150 — The compliance-evidence collector reports what the artifacts actually show
**Covers:** F34
- Given: a `fake_gh_bin` recording of PR #279's real `gh pr view` / `gh pr
  checks` / `gh issue view` answers as of 2026-09-26, and variants of it
  per subcase
- When: `compliance-evidence.sh <pr-number>` runs with that fake `gh`
  ahead of `PATH`
- Then: it prints the six decided gates as a three-column Markdown table,
  in the fixed order, one row per gate, always six rows and never fewer;
  every Status cell is exactly one of `evidenced`, `not-evidenced`,
  `unverifiable-from-artifacts`, `indeterminate`; every Evidence cell
  names an artifact; the two model rows read "Per-stage model recorded (...)"
  and "Review at least as capable as Implementation (same model: the floor is
  met on the model alone; ...)" and a same-model gate 2 is `evidenced` on the
  model alone whatever legacy efforts the markers carry, its basis named as
  the model-only floor on self-reported model strings (#424; S237); the merge-confirmation row is
  `unverifiable-from-artifacts` whether the PR is merged or open; a red,
  pending, unknown-bucket or absent CI check is never `evidenced`; a
  stale review marker is `not-evidenced` while an unparseable one is
  `indeterminate`; a failed checks or issue-comments lookup degrades its
  own row to `indeterminate` and exits 0, while a failed PR lookup exits
  4 with no table; with no `gh` on `PATH` it exits 3 with nothing on
  stdout; the run makes no `gh` write call and the script's source
  contains none

### S151 — Marker-shaped text that is quoted, or isn't a real HTML comment, is not evidence
**Covers:** F34
- Given: a `fake_gh_bin` recording where marker-shaped text appears
  inside a fenced code block, an inline code span or a `>` blockquote, or
  as bare prose with no `<!--`/`-->` delimiters, in the PR body, a PR
  comment or a closing issue's comments
- When: `compliance-evidence.sh <pr-number>` runs with that fake `gh`
  ahead of `PATH`
- Then: no gate counts such an occurrence as live evidence; a gate whose
  only matches were quoted reports `not-evidenced` and says in words that
  quoted occurrences were seen and ignored; bare marker-shaped prose
  reports `not-evidenced` rather than `indeterminate`, while a malformed
  marker inside real delimiters still reports `indeterminate`; a real
  marker posted inline on a line that also carries prose, backticked
  text, table pipes or a stray unmatched backtick keeps evidencing;
  fence state never crosses a body boundary; the collector's own
  rendered table pasted into the PR changes no status; and the six-row
  shape, the four-status vocabulary and the absence of any write path
  are unchanged

### S152 — role-label-staleness.sh detects role:<name> label staleness for one issue
**Covers:** F35
- Given: a `fake_gh_bin` recording of REST-only `gh api` answers — the
  issue's own body/labels, the issue's comments, the issue's timeline
  (candidate PRs via `cross-referenced` events), each candidate PR's
  current title AND body (for the closing-keyword filter — this repo's
  own release-branch PRs carry the keyword only in the title, never the
  body), and each kept PR's comments AND reviews (a PR review's own
  body, not just a plain comment, is where this pipeline's Review-stage
  marker actually gets posted); no `gh api graphql`, `gh issue view` or
  `gh pr view` call anywhere (both GraphQL-backed and blocked in Claude
  Code sessions, and `closedByPullRequestsReferences`/
  `closingIssuesReferences` are empty for any PR targeting a non-default
  branch, silently missing every epic #295 work-item PR — the redesign
  this scenario now covers, issue #315's Architect comment of
  2026-09-28, with two round-2 review corrections: matching the PR
  title as well as the body, and reading PR reviews)
- When: `role-label-staleness.sh <issue-number>` runs with that fake
  `gh` ahead of `PATH`
- Then: it prints exactly one verdict line,
  `role-label-staleness: issue #<n> — <status> (<detail>)`, with
  `<status>` one of `not-started`, `in-sync`, `stale`, `indeterminate`; a
  label matching the latest evidenced stage, or one with zero markers
  evidenced anywhere, is `in-sync`; a label naming an earlier stage than
  the latest evidence is `stale`, naming both the label present and the
  label the evidenced stage implies; no label and no marker anywhere is
  `not-started`, distinctly from no label with at least one marker
  (`stale`); a timeline that succeeds with zero candidate PRs computes a
  normal verdict from issue-only evidence, never `indeterminate` on its
  own — distinct from the timeline call itself failing, which must never
  be read as "zero linked PRs"; a PR that cross-references the issue
  without a real closing keyword in either its LIVE title or body
  (`close(s|d)`/`fix(es|ed)`/`resolve(s|d)`, an optional `:`, then
  whitespace, then `#<issue>`, case-insensitive) is excluded and never
  even gets a comments or reviews call — including a prose near-miss
  that merely mentions the issue number later in a sentence, which the
  keyword's own grammar rejects, and including a title/body that only
  quotes the keyword shape inside a fenced block, inline code span, or
  blockquote (issue #317 F-7: the filter runs against `live_text()`-
  stripped title+body, not the raw text, so a merely-illustrative quote
  never counts as a real closing reference); a cross-referenced timeline
  event whose own source PR belongs to a different repository — even
  one that happens to share a same-numbered PR in this repo — is
  excluded from PR discovery entirely (issue #317 F-8, verified against
  the real `gh api .../timeline`-shaped JSON, since a mocked `gh` can't
  exercise jq's own server-side filtering); two-or-more `role:<name>`
  labels at once is `indeterminate`, naming every one found, and an
  unrelated label alongside a single one is never counted as multiple; a
  live marker matched by the anchor but with no recognized `stage=`
  value, on the issue or any kept PR, forces `indeterminate` for the
  whole run even when another kept PR's marker is well-formed, including
  one closed with no whitespace before its own `-->` delimiter (issue
  #317 F-5: `stage=Review-->` must still parse as `Review`, not as a
  malformed `Review--` token); markers split across multiple kept PRs
  combine by union/max, order-independent of which PR the timeline names
  first; a marker merely quoted in a fenced block, code span or
  blockquote is not counted as live evidence; a failed lookup — the
  issue's own comments, the timeline itself, or a candidate/kept PR's
  title/body, comments, or reviews — degrades the verdict to
  `indeterminate` only when the evidence read so far doesn't already
  rule out what the failed lookup could reveal (a verdict already
  `stale`, or already `in-sync` at the last stage, from what WAS read,
  is never degraded — including specifically when the issue's own
  comments fail but a kept PR's reviews call still succeeds and supplies
  evidence all the way to the ceiling stage, issue #317 F-10, closing a
  mutation-testing gap an earlier review round found unpinned); a failed
  issue-body lookup exits 4 with nothing on stdout, while every other
  failed lookup only sets its own flag and never changes the exit code;
  a non-numeric issue-number argument is a usage error (exit 2), not an
  internal error (exit 4, issue #317 F-4 — matching the empty-argument
  case, not the issue-unreadable case, and making no `gh` call at all);
  with no `gh` on `PATH` it exits 3; the run makes no `gh` write call and
  the script's source contains none — verified as a conjunction with a
  `fake_gh_bin` fallthrough witness that is actually reachable (proved
  by a positive control that calls the fake `gh` directly with an
  unanswered argv and confirms the witness fires), not merely a source
  grep alone

### S153 — live_text() has one definition, and its fence detection is portable: the golden cases give the same answer under mawk and under /usr/bin/awk
**Covers:** F34, F35
- Given: the repository after #423 (V2 of #411), where `live_text()` and
  `md_strip_fences()` live in `lib/markdown.sh` and nowhere else, and the
  three callers (`compliance-evidence.sh`, `role-label-staleness.sh`,
  `skills/pre-merge-review/model-record-gate.sh`) get them through
  `lib/model-record.sh`; mawk installed (the macOS leg installs it for this
  scenario only) and `/usr/bin/awk` (BWK awk on macOS) present
- When: a search over every text file outside `.git`, `test/`, `wip/` and the
  `.md` documents looks for a definition of either function; `lib/model-record.sh`
  is sourced alone in a bash with `extdebug`; then the golden fence cases
  G1-G9 run through the sourced `lib/markdown.sh` `live_text`, once with
  `awk` resolving to mawk and once with `awk` resolving to `/usr/bin/awk`
  named explicitly
- Then: the only definition is `lib/markdown.sh` (which defines both; a
  fourth copy in `review-rounds.sh`, added by #410 after #423 was written, is
  also gone), and after sourcing `lib/model-record.sh` both functions are
  defined from `markdown.sh`; the "copies are byte-identical" arm of the old
  S153 is retired with the copies. G1-G6 are the old cases, unchanged: a
  simple fence; a 5-tilde wrapper around an inner line that holds three
  backticks; a shorter closing run that must not close a longer opener; a
  marker after a closed fence stays live; a one-backtick run starting a line
  opens nothing; a backtick fence line inside an open tilde fence is content.
  G7-G9 are new and put the new awk code through both awks: a fence opened
  on a list-item line closes at its own indented closing line; a backtick in
  a backtick fence's info string makes the line a non-opener; a CRLF fence
  and a lone CR are line endings. Every case gives the answer gawk gives. A
  static guard keeps brace-interval syntax (`{n,m}`) out of the fence regex
  (mawk 1.3.4 20200120 does not parse it, #319). Fails loudly, naming why, if
  mawk or `/usr/bin/awk` is missing. Retires: the identical-copies arm.
  Mutations (A35a): a second `live_text` definition in a script (copy back),
  `{0,3}` back in the fence regex, the list-item prefix written with a brace
  interval, CR splitting removed

### S154 — classify-review-depth.sh classifies a PR quick/thorough by Reviewer's six trigger categories
**Covers:** F36
- Given: `fake_gh_bin` recordings of REST-only `gh api` answers — a PR's changed-file path
  list and its description/body text — captured by actually running a draft/prototype of
  `classify-review-depth.sh` against a recording fake `gh` (this repo's own fixture-hygiene
  convention, same technique S150-S153 already use), never hand-retyped; no `gh api graphql`,
  `gh pr view` or `gh issue view` call anywhere, matching `role-label-staleness.sh`'s own
  REST-only precedent and the defect history (#318/#320/#323/#341) that motivates it; variants
  of this recording per subcase below
- When: `classify-review-depth.sh <pr-number>` runs with each fake `gh` ahead of `PATH`, with
  and without `--force-thorough`
- Then:
  1. **Quick, no trigger match:** a PR whose changed-file paths and description touch none of
     the six categories (Auth/session, Secrets/credentials, Deploy/CI configuration,
     Infrastructure as Code, Sensitive/personal data, Untrusted input) — e.g. a
     `docs/README.md`-only change with no category-shaped language in the description —
     classifies `quick`, and the printed evidence names zero matched categories explicitly
     (not merely omits them).
  2. **Real trigger match, Secrets/credentials:** a PR whose changed-file paths include a
     file plausibly carrying a credential shape (e.g. `.github/workflows/deploy.yml` adding a
     new `secrets.`-referencing step, or a path containing `credentials`/`.env`) classifies
     `thorough`, and the printed evidence names `Secrets/credentials` as a matched category.
  3. **Real trigger match, Untrusted input:** a PR whose description text describes handling
     external/webhook/API input (independent of file path shape, to prove the classifier
     reads description text and not only paths) classifies `thorough`, naming
     `Untrusted input` as the matched category.
  4. **Multiple categories matched, evidence lists all of them:** a PR shaped to match both
     Secrets/credentials and Deploy/CI configuration classifies `thorough` and the evidence
     names both categories, not just the first one found — proves category matching doesn't
     short-circuit after the first hit (needed for scenario 6 below to be meaningful).
  5. **`--force-thorough` overrides a zero-match PR:** the same zero-trigger PR from scenario 1,
     run with `--force-thorough`, classifies `thorough`; the printed evidence states the
     override was the reason (zero categories matched, override forced the mode) rather than
     falsely implying a category match — a caller reading the evidence later must be able to
     tell "forced" apart from "actually matched," since #307 will eventually want to use real
     trigger-match data, not override noise, as its ceremony-cost evidence.
  6. **`--force-thorough` is a strict superset, never a substitute:** the same multi-category
     PR from scenario 4, run with `--force-thorough`, still classifies `thorough` and still
     names the real matched categories (not just "forced") — the override adds, it doesn't
     paper over/replace genuine evidence.
  7. **Evidence surface stays match-only, never emits a dispatch count:** across every
     `thorough` case above (1, 3, or however many of the six categories matched), the
     classifier's stdout never prints or implies a number of lens-Adapters, a fork count, or
     any per-category multiplier — only the category name(s). This is the one piece of the
     fixed-N=2-not-category-derived property (A13) that is actually this script's own
     contract to hold: `classify-review-depth.sh` supplies evidence, never a count, so nothing
     in its own interface can regress toward "N grows with match count" even before dispatch
     wiring exists. (The dispatch side of that property — that `pre-merge-review`'s inline
     branching always forks exactly Reviewer+2 lens-Adapters regardless of how many categories
     this script's evidence names — is flagged as a separate, harder-to-mechanically-test gap
     in QA's issue comment; A13 deliberately keeps that branching as prose in
     `pre-merge-review/SKILL.md` rather than its own script, which is exactly what makes it
     not unit-testable the way this scenario tests the classifier itself.)
  8. **REST lookup failure fails open toward `thorough`, not `quick`:** `gh` present on
     `PATH` but the changed-files or description lookup itself fails (non-zero exit from the
     underlying `gh api` call, simulated via the fake `gh`) still prints a verdict —
     `thorough` — rather than erroring out or defaulting to `quick`; the evidence states the
     lookup failed and that the mode was chosen conservatively, not that a category actually
     matched. (See QA's issue comment for why `thorough`, not `quick`, is the right fail-open
     direction — a real call, not obvious either way, made explicit here rather than left to
     Fullstack Developer to guess at implementation time.)
  9. **No `gh` on `PATH` is a harder failure than a lookup failure:** with `gh` entirely
     absent from `PATH`, the script exits non-zero (matching `role-label-staleness.sh`'s own
     "no `gh` on `PATH`" exit-3 precedent) with nothing on stdout — distinct from scenario 8's
     "gh present, one call failed" case, which still produces a verdict. A caller (the
     `pre-merge-review` dispatch instructions) must be able to tell "no usable answer at all"
     apart from "got an answer, chose thorough out of caution" — collapsing the two into the
     same behavior would hide a broken environment behind a plausible-looking verdict.
  10. **No write path:** the run makes no `gh` write call (no label, no comment, no edit,
      no merge) under any subcase above, and the script's own source contains none — same
      read-only conjunction S150/S152 already verify for their own scripts, checked here with
      a `fake_gh_bin` fallthrough witness that is actually reachable (a positive control
      confirms the witness fires on an unanswered argv), not a source grep alone.
  11. **`--lens-adapter-count` prints `LENS_ADAPTER_COUNT`:** `classify-review-depth.sh
      --lens-adapter-count` (no `gh` on `PATH` required — the flag short-circuits before any
      `gh` lookup) prints `2` and exits 0. Added post-review (PR #353, Reviewer's F1): the
      seam existed and was manually verified but had zero automated coverage, directly
      contradicting the PR's own stated rationale ("a future drift shows up as a test
      failure, not a silent mismatch") — a typo'd constant or a broken flag check would have
      stayed CI-green.
  12. **Real trigger match, Auth/session (file-path signal):** a PR whose changed-file paths
      include a path segment naming `auth` (with no other category-shaped language in its
      description) classifies `thorough`, naming `Auth/session` as the matched category.
  13. **Real trigger match, Infrastructure as Code (file-path signal):** a PR whose
      changed-file paths include a `.tf` file (with no other category-shaped language in its
      description) classifies `thorough`, naming `Infrastructure as Code` as the matched
      category.
  14. **Real trigger match, Sensitive/personal data (description-text signal):** a PR whose
      description text names GDPR/personal-data handling (independent of file path shape)
      classifies `thorough`, naming `Sensitive/personal data` as the matched category.
      Scenarios 12-14 added post-review (PR #353, Reviewer's F2): only 3 of the six categories
      (Secrets/credentials, Deploy/CI configuration, Untrusted input) had a real-match fixture
      before; a future regex edit breaking Auth/session, Infrastructure as Code, or
      Sensitive/personal data would have gone uncaught.

### S155 — adopt.sh installs role-contracts as a skill, with no wip/ file needed
**Covers:** F37
- Given: a guardrails clone with its `wip/` directory removed, and a fresh
  git project (issue #369, AC1)
- When: `adopt.sh` runs on the project from that clone
- Then: `.claude/skills/role-contracts` is a symlink to the clone's
  `skills/role-contracts`, and the `SKILL.md` it resolves to is readable
  and declares `name: role-contracts`

### S156 — process-multi-agent-roles is asked, never seeded
**Covers:** F37
- Given: a fresh project right after adoption, and a copy of a frozen,
  already-adopted project (`tennis-invoicing` baseline) with no row for
  `process-multi-agent-roles` (issue #369, AC2)
- When: `adopt.sh` seeds the fresh project and `pending-changes.sh` runs
  against both
- Then: `adopt.sh` seeds no row for it (`Default: question`), and
  `pending-changes.sh` lists it as pending for both projects

### S157 — The process-multi-agent-roles CHANGES.md entry is well-formed
**Covers:** F37
- Given: `CHANGES.md` (issue #369, AC3 and the `CHANGES.md` half of AC7)
- When: the shared parser (`lib/changes.sh`'s `iterate_entries`) and
  `./check`'s PR-linkback validation (`pr_links_missing`) read it
- Then: exactly one `## process-multi-agent-roles` entry exists; the
  parser reads `Default: question` and `Applies if: always` with no
  warning; the PR-linkback validation does not flag it; its Question is a
  single line ending in `?` that opens with a yes/no auxiliary verb; its
  `PR` field is a full `https://github.com/<owner>/<repo>/pull/<n>` URL
- And: its "Yes means" names `$SPEC_DRIVEN_GUARDRAILS_DIR/` and all three
  evidence scripts (`compliance-evidence.sh`, `role-label-staleness.sh`,
  `classify-review-depth.sh`), and the `role:` labels the project creates
- Not checked offline: that the PR number is the PR that actually
  delivers #369. Reviewer verifies that by REST at review time.

### S158 — Every pointer in the installed role-contracts skill resolves from an adopted project
**Covers:** F37
- Given: a fresh project adopted from a sandbox clone, and its installed
  `.claude/skills/role-contracts/SKILL.md` (issue #369, AC4; Architect
  decision A14(a))
- When: the skill's file references are checked against what exists in
  that project
- Then: no `vendor/` path remains; any paragraph naming a document that
  exists only in the clone (`PRD-MULTI-AGENT-WIP.md`,
  `ARCHITECTURE-MULTI-AGENT-WIP.md`, `MULTI-AGENT-WORKFLOW.md`,
  `wip/multi-agent-development`) says it lives in the clone
  `SPEC_DRIVEN_GUARDRAILS_DIR` points at; every other backticked `.md` or
  `.sh` path resolves in the adopted project (at its root, under
  `.claude/`, or as a file of an installed skill), placeholders like
  `<slug>` excepted; and no bare `#<n>` issue reference remains, since
  GitHub would link it to the adopting project's own issue with that number

### S159 — The installed role-contracts skill names the decision-maker by role, not by person
**Covers:** F37
- Given: the installed `role-contracts` skill in an adopted project
  (issue #369, AC5)
- When: its words are checked
- Then: the repo owner's first name appears nowhere (checked by SHA-256,
  so the name itself is never written into this public repo); the
  owner's GitHub handle appears only as a repository qualifier
  (`<handle>/<repo>`); no gendered personal pronoun stands in for a
  specific person; and the skill names "the project's human
  decision-maker" (or a phrase with `decision-maker`) as who receives
  decisions and escalations

### S160 — The installed role-contracts skill says how to run the pipeline without the WIP docs
**Covers:** F37
- Given: the installed `role-contracts` skill in an adopted project, and
  the stage order and `role:<name>` labels as `role-label-staleness.sh`
  defines them (issue #369, AC6; Architect decision A14(b)/(c))
- When: the skill's tables and text are read (the stage table in the
  skill's `ORCHESTRATOR.md`, its single home since #371 A16, which
  `SKILL.md` must point to)
- Then: one table row per stage, in pipeline order (Discovery, Planning,
  Test, Implementation, Review), names the stage as its own cell together
  with that stage's label (`role:product`, `role:architect`, `role:qa`,
  `role:dev`, `role:reviewer`), so the skill agrees with what the script
  checks; the `model-record` marker is named and `model-choice` is
  pointed to for its format, with no literal `<!-- model-record` copy in
  the skill; the `gh label create` command for the project's own repo is
  given and `role-label-staleness.sh` is named as what reads the labels;
  and one paragraph states that every role takes part in every change

### S161 — The evidence scripts, run by path from the clone, address the adopted project's repo
**Covers:** F37
- Given: a clone whose own `origin` is spec-driven-guardrails, a project
  adopted from it whose `origin` is a different repository, and a
  recording fake `gh` (issue #369, AC7; Architect decision A15)
- When: `"$SPEC_DRIVEN_GUARDRAILS_DIR/compliance-evidence.sh" 7`,
  `role-label-staleness.sh 7` and `classify-review-depth.sh 7` each run
  with the adopted project's checkout as working directory
- Then: each script makes at least one `gh` call; every call runs from
  the adopted project's checkout, with no `GH_REPO` override, no `-R` /
  `--repo` flag and no argument naming spec-driven-guardrails; and every
  REST path is either `repos/{owner}/{repo}/...` (resolved by `gh` from
  the working directory's remote) or the adopted project's own
  `owner/repo`
- Not checked by this test: that the real `gh` resolves `{owner}/{repo}`
  from the working directory's remote. QA verified that by hand for #369
  against a real adopted project (recorded in QA's issue comment)

### S162 — Every script an installed skill tells the agent to run exists where the skill says
**Covers:** F37
- Given: a fresh project adopted from a sandbox clone, and every
  installed skill's `SKILL.md` (issue #369: the human decision that
  `pre-merge-review`'s `./classify-review-depth.sh` path is fixed here,
  Architect finding V4)
- When: each `./<name>.sh` and `$SPEC_DRIVEN_GUARDRAILS_DIR/<path>.sh`
  invocation in those skills is resolved
- Then: every `./<name>.sh` exists, executable, at the adopted project's
  root; every `$SPEC_DRIVEN_GUARDRAILS_DIR/<path>.sh` exists, executable,
  in the clone; and `pre-merge-review` still runs the classifier, as
  `$SPEC_DRIVEN_GUARDRAILS_DIR/classify-review-depth.sh`

### S163 — The README says the multi-agent workflow is adoptable, and what adopting it takes
**Covers:** F37
- Given: `README.md` (issue #369, AC8 and the README half of AC7)
- When: it is read
- Then: none of v0.2.0's three "not adoptable yet" sentences remain; it
  names the `role-contracts` skill and the opt-in
  `process-multi-agent-roles` question; it says what an adopter does not
  get (an orchestrator, the release-branch tier, and, in the same
  paragraph as the evidence scripts, that they are not installed); it
  states the prerequisites (`gh`, `SPEC_DRIVEN_GUARDRAILS_DIR`, and
  creating the `role:` labels) and the `gh repo set-default` caveat for
  several remotes; it does not claim the skill points "only" at installed
  skills (it also names built-in ones); it shows
  `$SPEC_DRIVEN_GUARDRAILS_DIR/compliance-evidence.sh` run from an
  adopted project
- And: no orphan fragment remains: no line starts lower-case right after
  a line that ended a sentence

### S164 — No live reference to role-contracts' old wip/ location remains in this repo
**Covers:** F37
- Given: a copy of this repo's working tree (issue #369, AC9)
- When: every file except the historical records (`CHANGELOG.md`,
  `CHANGES-ARCHIEF.md`) is searched
- Then: none names the old `wip/` location of `role-contracts`; every
  relative path to `role-contracts/SKILL.md` (`../...`) resolves from the
  file containing it; and `skills/role-contracts/SKILL.md` exists
- And: AC9's "`./check` passes" is what S5, S39, S40, S92, S93, S112,
  S121 and S124 already assert

### S165 — test/lib.sh isolates fixture git commands from an inherited git repo environment
**Covers:** F1
- Given: a decoy git repo inside the test's own sandbox, and every
  variable `git rev-parse --local-env-vars` prints exported to point at
  it, the way a hook, `git rebase --exec` or a git alias exports them for
  the launching repo (issue #377, AC4; never pointed at the real repo or
  `TEST_REPO_ROOT`)
- When: a child process sources `test/lib.sh` and runs `sandbox_create`,
  `fresh_project`, a fixture commit, `git tag`, `git init --bare`,
  `git remote add` and `git push -u` (the command shapes of S57, S84 and
  S144)
- Then: none of those variables is still set after sourcing; the decoy's
  refs, `HEAD`, worktree list, config, index and stash are unchanged; the
  fixture commit lands in the fixture itself
- And: `sandbox_guard` refuses, naming the variable, when any one of them
  is exported again after sourcing (the same loud refusal as for `HOME`,
  S3)
- And: the git identity, `GIT_CONFIG_GLOBAL`, `GIT_CONFIG_NOSYSTEM`,
  `GIT_TERMINAL_PROMPT`, `GIT_EDITOR` and `CLAUDE_WORKFLOW_GUARDRAILS_OFF`
  survive sourcing unchanged

### S166 — hooks/pre-commit runs check-commit without git's repo-local variables, from any worktree and commit form
**Covers:** F17
- Given: a sandbox project with the real `hooks/pre-commit` installed as a
  symlink, a linked worktree, and a `check-commit` that records its
  environment and working directory and then does fixture git work
  (`init`, `commit`, `tag`, `init --bare`) in a temp directory (issue
  #377, AC1, AC2, AC5)
- When: a commit is made from the linked worktree and from the main
  worktree, each as a plain commit, a partial commit
  (`git commit -- <path>`) and `git commit -a`
- Then: every commit succeeds; `check-commit` sees none of the variables
  `git rev-parse --local-env-vars` prints; the `check-commit` that ran is the
  committing worktree's own, run at that worktree's root; the git
  identity, `GIT_CONFIG_NOSYSTEM` and `GIT_TERMINAL_PROMPT` still reach it
- And: the project's refs (other than the committing branch), worktree
  list, shared config, stash and the other worktree's `HEAD` and index are
  unchanged; the new commit holds exactly the intended paths; after a
  partial commit the other staged path is still staged

### S167 — hooks/pre-commit warns and skips check-commit when lib/git-env.sh is missing
**Covers:** F17
- Given: a copy of this repo without `lib/git-env.sh`, its
  `hooks/pre-commit` installed as a symlink in a sandbox project, and a
  `check-commit` that leaves a marker when it runs (issue #377, human decision
  on the Architect report)
- When: a commit is made on a feature branch
- Then: the commit proceeds; a warning names `git-env.sh`; `check-commit` did
  not run
- And: a commit on `main` is still blocked (the branch guard does not
  depend on the library)

### S168 — lib/git-env.sh clears git's own repo-local list plus a fixed floor, and nothing else
**Covers:** F1
- Given: `lib/git-env.sh` (issue #377, Architect decision A19)
- When: `git_local_env_vars`, `git_local_env_clear` and
  `git_local_env_assert_clear` are called, with the real `git`, with a
  `git` that fails, with one that lists fewer names, and with one that
  lists a name newer than today's git
- Then: the list always contains every name today's
  `git rev-parse --local-env-vars` prints, plus any newer name `git`
  reports; it never contains the git identity, `GIT_CONFIG_GLOBAL`,
  `GIT_CONFIG_NOSYSTEM`, `GIT_CONFIG_SYSTEM`, `GIT_EXEC_PATH`, `GIT_SSH*`,
  `GIT_TERMINAL_PROMPT`, `GIT_TRACE`, `GIT_EDITOR`, `GIT_ALLOW_PROTOCOL`,
  `CLAUDE_WORKFLOW_GUARDRAILS_OFF`, `HOME` or `PATH`
- And: `git_local_env_clear` unsets every listed variable and keeps the
  identity and the guardrails override; `git_local_env_assert_clear`
  passes after a clear, and fails naming `GIT_INDEX_FILE` when it is set
- And: no hook, `lib/` file, `test/lib.sh`, `test/run.sh` or `check`
  other than `lib/git-env.sh` holds a second copy of the list

### S169 — ci-commit-check is pending only for projects with a check, and is never auto-seeded
**Covers:** F2, F17
- Given: `CHANGES.md` with the `ci-commit-check` entry (Default `question`,
  Applies if `has-check-command`), and two adopted projects, one with an
  executable `check` and one without (issue #378, AC11)
- When: `pending-changes.sh` runs for each, and `adopt.sh` has run
- Then: the entry is pending for the project with a `check` and not for
  the one without; `adopt.sh` did not seed it; the entry names
  `check-commit`
- And: once the project answers the row, the entry is no longer pending

### S170 — this repo's check-commit lets a red test commit through and blocks on a static failure
**Covers:** F17
- Given: a throwaway copy of this repo, made a git project with the real
  `hooks/pre-commit` installed, and a `test/run.sh` stub that leaves a
  marker (issue #378, AC1, AC2)
- When: a new failing test case with its `TEST-SCENARIOS.md` heading is
  committed on a `feature/` branch
- Then: the commit succeeds and the suite did not run
- And: a commit that adds a script with a syntax error is refused and
  names the script; a commit that adds a scenario heading without a test
  file is refused and names the heading; neither ran the suite

### S171 — hooks/pre-push runs no check, and still refuses a push to main
**Covers:** F17
- Given: an adopted project whose `./check` and `check-commit` are both
  red and leave a marker when they run, and a feature branch with a
  commit on it (issue #378, AC7, R3)
- When: the branch is pushed to a bare remote, and then `HEAD:main` is
  pushed
- Then: the branch push succeeds and neither `./check` nor `check-commit`
  ran; the push to `main` is refused

### S172 — the docs describe the commit-time split and no longer say pre-commit runs the suite
**Covers:** F17
- Given: this repo's README, PRD, CHANGELOG, `check-convention` skill,
  `TEST-SCENARIOS.md` and root `check-commit` (issue #378, AC10, R6)
- When: they are read
- Then: the README no longer says a bad commit is caught before it
  reaches a branch and mentions `check-commit`; the PRD no longer lists
  the untimed `./check` call as debt and mentions `check-commit`; the
  CHANGELOG Unreleased section has a #378 line naming `check-commit` and
  `ci-commit-check`; `check-commit` is defined by `check-convention`; S144
  describes `check-commit`; the root `check-commit` is executable and runs
  the static part of `check`

### S173 — a check-commit that ignores TERM cannot hang the commit: the watchdog escalates to KILL
**Covers:** F17
- Given: an adopted project on a feature branch whose `check-commit`
  runs for 25 s while ignoring TERM, in one fixture itself and in the
  other through a grandchild that ignores TERM (issue #378, review
  finding 1 and 2)
- When: a commit is attempted with `COMMIT_CHECK_BUDGET=2`
- Then: after the budget the watchdog sends TERM, then after a short
  grace period KILL, to the process group; the commit goes through well
  before the 25 s are over, with a warning that mentions the budget
- And: no process of `check-commit` survives, including the grandchild
  that ignored TERM

### S174 — COMMIT_CHECK_BUDGET must be a positive integer; a bad value is rejected, never read as a timeout
**Covers:** F17
- Given: an adopted project on a feature branch whose `check-commit`
  really fails (exit 1 after one second, printing a marker line) (issue
  #378, review finding 3)
- When: a commit is attempted with `COMMIT_CHECK_BUDGET` set to `abc`,
  empty, `0`, `-3`, `1.5` or `10s`
- Then: the value is rejected with a message that names
  `COMMIT_CHECK_BUDGET`; the real failure is not waved through, so no
  commit lands, and nothing says the check "exceeded" a budget

### S175 — PRD and ARCHITECTURE no longer say the pre-commit hook runs ./check
**Covers:** F17
- Given: the PRD paragraph that starts "As of issue #377, the `pre-commit`
  hook" and the ARCHITECTURE A19 section (issue #378, review finding 4, AC10)
- When: they are read
- Then: the PRD paragraph and A19's first caller (`hooks/pre-commit`)
  name `check-commit` and no longer say the hook runs, clears for or
  skips `./check`; A19's "Violated when" no longer speaks of the
  `./check` child

### S176 — answered_yes is one shared rule for "this row is answered yes"
**Covers:** F38
- Given: projects whose WORKFLOW-ADOPTION.md (or the pre-migration
  WORKFLOW-ADOPTIE.md) holds a row for an id with answer yes, ja, no, nee,
  a yes only in the Notes column, a similar-looking id, a renamed id, or no
  file at all (issue #371, A16, AC3)
- When: `answered_yes <project> <id>` in `lib/changes.sh` is asked
- Then: it succeeds only for yes/ja in the Answer column of the exact id
  (new file before old; pre-rename ids honoured) and fails otherwise;
  `adopt.sh` no longer carries its own hard-coded copy of the rule

### S177 — session-context.sh prints a session-context file only for a yes row
**Covers:** F38
- Given: a clone whose entries declare `session-context: <path>` values
  (alone or in a comma list with a gate value), and projects with mixed
  yes/no/unanswered rows, `ja` in the old file, similar ids, a declared
  file that does not exist, no adoption file, and a nonexistent project
  (issue #371, A16, AC1, AC3)
- When: `session-context.sh <project>` runs
- Then: it prints exactly the files of the entries answered yes, each once;
  nothing for no/unanswered/gate-only/none entries; it exits 0 in every case,
  and a missing declared file only warns on stderr, and a later version of a
  file is what the next run prints; for a project whose `CLAUDE.md` is
  missing, a regular file or linked elsewhere it also prints a warning that
  names `CLAUDE.md` and `adopt.sh` (silent when linked to the clone's
  `WORKFLOW.md`)

### S178 — the SessionStart chain delivers the rules, reaches the project without re-adoption, and warns on a broken CLAUDE.md link
**Covers:** F38
- Given: a real adoption from a copy of this clone, with the row answered
  yes, no, and never (issue #371, A16, AC1, AC3, AC11)
- When: every SessionStart command from the project's `.claude/settings.json`
  runs the way Claude Code runs it
- Then: only the yes project's output carries `ORCHESTRATOR.md`, and a
  later `ORCHESTRATOR.md` in the clone shows up on the next run with no
  `adopt.sh` and no new answer; the unanswered row is still reported by
  pending-changes; a missing, regular-file or wrongly linked `CLAUDE.md`
  yields a warning that names it and says to run `adopt.sh`, a correct link
  none, and the rules are delivered regardless; the session-context command
  finds the clone by `readlink`, hard-coding no path, and carries no
  `CLAUDE.md` warning logic itself (that lives in `session-context.sh`)

### S179 — this repo answers its own row yes and gets the rules at session start
**Covers:** F38
- Given: this repo's own WORKFLOW-ADOPTION.md and tree (issue #371, AC2)
- When: `answered_yes` is asked for `process-multi-agent-roles`, and
  `session-context.sh` runs on this repo, and on a project answering no
- Then: the row is a reasoned yes (not the provisional stamp); the repo's
  run prints all of `ORCHESTRATOR.md`; the no project's run prints none of
  it; no repo-specific special case

### S180 — ORCHESTRATOR.md states the run rules once, short, with the recursion guard first
**Covers:** F38
- Given: `skills/role-contracts/ORCHESTRATOR.md` (issue #371, A16/A18, AC1,
  AC4-AC8; the mechanical proxy for model behaviour that cannot be asserted)
- When: it is read
- Then: a `ROLE SESSION:` guard is within its first five non-blank lines;
  it says roles are fresh agents, never forks; it names the announce step,
  `role:product` first, all five labels paired with their stage values; it
  separates work items from questions, research, co-thinking and adoption;
  it defines the `pipeline-override` record with decided-by, scope and
  reason and says shortcuts are never self-granted, trivial included; it
  says to stop and ask when dispatch is unavailable; it says how to resume
  (with `role-label-staleness.sh`); `SKILL.md` points to it; it stays short

### S181 — ./check rejects a CHANGES.md entry with no declared session path
**Covers:** F38
- Given: a copy of this repo whose `process-multi-agent-roles` entry has the
  Reaches session field missing, only in prose, empty, outside the
  vocabulary, pointing at a missing file, pointing at a file no test names,
  or in a list with one bad value (issue #371, A17, AC10)
- When: `check --no-tests` runs on it
- Then: it fails and names the entry, the field and the culprit; it passes
  for the unmodified repo, for `none`, for a valid comma list, for
  `always-loaded: WORKFLOW.md`, and for a hook path once a test case names it

### S182 — every CHANGES.md entry declares how it reaches a session
**Covers:** F38
- Given: this repo's CHANGES.md (issue #371, AC10, human decision 4)
- When: its entries are read
- Then: every entry has a non-empty Reaches session value; the preamble
  documents the field and its five keywords; `process-multi-agent-roles`
  declares `session-context: skills/role-contracts/ORCHESTRATOR.md` and
  `gate: skills/pre-merge-review/model-record-gate.sh`, and carries no
  Meaning version

### S183 — the model-record gate flags a role-played run in opted-in projects only
**Covers:** F38
- Given: PR and issue data from a data-driven fake `gh`: a dispatched run
  (one marker per comment), all five markers in one comment, two stages in
  the PR body, two in one review body, one stage twice in one text,
  markers quoted in a fence or blockquote, a missing stage, valid and
  invalid or quoted override records, and gh failing; projects that
  answer the row yes, ja (old file), no, never, or have no adoption file
  (issue #371, A18, AC3, AC6, AC9)
- When: `model-record-gate.sh <pr>` runs with the project as cwd
- Then: a run with live markers of two different stages in one text, or
  with a stage missing, gets a finding line starting `role-played: ` in
  opted-in projects only; a dispatched run, a repeated single stage and
  quoted markers get none; a valid override (decided-by, reason, and a scope of
  `single-session` or `skip=<Stage>`; not quoted) removes the finding, an
  empty-reason, who-less, unknown-scope or quoted one does not; with gh failing or absent it exits 0 and invents no finding; the
  gate exits 0 whenever it runs

### S184 — no installed or always-loaded text says one session doing every stage is the norm
**Covers:** F38
- Given: `model-choice`, the gate header, the README and the
  `process-multi-agent-roles` entry (issue #371, AC12, Reviewer note on
  PR #385)
- When: they are read
- Then: the "No behavior change" section and the single-session licence are
  gone, `model-choice` points to `process-multi-agent-roles` and
  `role-contracts`; the README and the entry no longer say nothing starts
  the pipeline or that automatic activation is a separate work item, and
  name `ORCHESTRATOR.md` and session start

### S185 — the pre-merge-review skill says a role-played run blocks the merge (the block itself is S186)
**Covers:** F38
- Given: `skills/pre-merge-review/SKILL.md` (issue #371, AC9, human
  decision 3)
- When: the paragraph about a role-played run is read
- Then: it says the finding blocks (not non-blocking), mentions the
  `pipeline-override` record and that without `gh` the check passes

### S186 — the merge guard refuses `gh pr merge` on a role-played run, in opted-in projects only
**Covers:** F38
- Given: a fake `gh` that passes the existing review-marker check, PR data
  for a dispatched run, for all five markers in one comment, and for the
  same with a valid override; projects that answer `process-multi-agent-roles`
  yes, no, never, or an opted-in project with the REST calls failing or no
  `gh` (issue #371, AC9, A18 amendment)
- When: `hooks/git-guardrails` receives `gh pr merge 246`
- Then: the opted-in role-played run is refused (exit 2) with a message that
  says role-played; the dispatched run and the validly overridden run go
  through; no/never projects are unaffected; failing or absent gh fails open;
  a missing review marker still blocks as before; the explicit
  `CLAUDE_WORKFLOW_MERGE_GUARD_OFF=1` hatch still lets the merge through

### S187 — ORCHESTRATOR.md tells the orchestrator to assess each stage's floor and choose the model per stage, without effort
**Covers:** F39
- Given: `skills/role-contracts/ORCHESTRATOR.md` (issue #392, R5/AC8, group 1;
  what the session then actually chooses is model behaviour, checked by a
  human dry run on the scratch repo, not here; issue #424: effort is neither
  chosen nor recorded)
- When: it is read, paragraph by paragraph
- Then: one paragraph points at `model-choice`, has the orchestrator assess
  each stage's floor and choose the model separately per stage (never one
  model for the whole run), requires Review to be at least as capable as
  Implementation on the model alone (no longer "model and effort together"),
  says that the dispatch tool takes no effort so effort is neither chosen nor
  recorded in markers, and has the chosen model named in the dispatch prompt
  for the role's `model-record` marker; no command in the file carries
  `--effort`; the file names no model or tier and carries no different-model
  rule (the phrase may only appear in a sentence saying it is not required);
  that no text tells anyone to pass `--effort` or ask the human about an
  unknown effort is S238

### S188 — lib/model-record.sh: normalize_model and marker_attr (effort_rank is gone)
**Covers:** F39
- Given: the sourced `lib/model-record.sh` (issue #392, A25; issue #424 deleted
  `effort_rank`), shared by the model-record gate and the compliance collector
- When: `normalize_model` and `marker_attr` are called
- Then: `normalize_model` behaves as before (label styles, case and an
  8-digit snapshot date fold together; different models and a short alias
  vs its full id stay different); `marker_attr <line> <name>` prints the
  quoted value of exactly that attribute, never one whose name merely ends in
  `model` or `effort` (in either attribute order), and nothing for an absent,
  unquoted or differently-prefixed attribute; it stays generic, so a legacy
  `effort` attribute is still readable though nothing interprets it; the lib
  defines no `effort_rank` and does not mention it
- Moved to S246 (issue #425, R5): the attribute-hijack arms (review of PR #397:
  attribute text inside a value, `floor-basis="beats model="`, `>`, `<`, `--`,
  `-->`), now asserted on `rec_field` against strict lines; `marker_attr` keeps
  its word-boundary arms here until its last caller moves

### S189 — the model-record gate checks the Review floor it can check, on the model alone
**Covers:** F39
- Given: PR 246 closing issue 239 against a data-driven fake `gh`, with
  Implementation and Review markers varied per case (issue #392, AC3/AC4/
  AC5/AC9, A24/A25; reduced to the model by #424, AC2); a plain project and an
  opted-in one
- When: `model-record-gate.sh 246` runs
- Then: for any pair of models, same after normalization or different (a
  short alias vs its full id is a known false pass), and for any legacy
  `effort` values on the markers (lower, higher, equal, different case,
  `unknown`, `session-default`, out of scale, missing, empty or unquoted, or
  no effort attribute at all, which is what the emitter prints now) the gate
  gives no finding and no line that mentions effort; a missing or empty
  `model` is still one finding naming the model; the latest marker per stage
  wins; every Review marker needs a non-empty quoted `floor-basis` (a missing,
  empty or unquoted one is a finding, a present one is never verified, and
  the other stages need none); a legacy `same-model-exception` is ignored
  completely, so it neither waives anything nor stands in for `floor-basis`;
  findings never start with `role-played:` and the exit status stays 0;
  attribute extraction is word-anchored; a missing stage stays its existing
  line; the gate works when run through a symlinked `skills/` directory

### S190 — compliance gate 2 reports the Review floor honestly, on the model alone
**Covers:** F39
- Given: a recording fake `gh` for PR 279 with Implementation and Review
  markers on the PR, on one or two closing issues, or unreadable (issue
  #392, AC4/AC5/AC6, A24/A25; the effort branch removed by #424, AC2/AC6)
- When: `compliance-evidence.sh 279` runs
- Then: for the same model, whatever legacy efforts the markers carry (lower,
  higher, equal, `unknown`, missing, unquoted, or no effort attribute),
  gate 2 is `evidenced`, its basis naming the model-only floor on
  self-reported model strings and quoting no effort; different models are
  `unverifiable-from-artifacts`, the evidence saying the models differ and
  their capability ordering is not machine-checked, quoting the `floor-basis`
  or saying none was recorded, and a short alias vs its full id counts as
  different; a legacy `same-model-exception` changes no verdict and is not
  printed; two closing issues disagreeing on the normalized model are a
  conflict (`indeterminate`, naming the models and no effort), while agreeing
  ones, ones differing only in legacy effort, and ones differing only in a
  legacy exception are not (the conflict key is the model alone); the
  #302/#336 lookup-failure guard still degrades a same-model verdict that
  depends on a possibly unread marker to `indeterminate`, and leaves sound
  verdicts alone

### S191 — quality-review-before-merge is at meaning v4 (the floor is on the model alone) and the specs follow
**Covers:** F9, F39
- Given: `CHANGES.md`, this repo's `WORKFLOW-ADOPTION.md`, `ARCHITECTURE.md`,
  `PRD.md` (issue #392, AC7/AC10; issue #424, AC4/AC7)
- When: the `quality-review-before-merge` entry and the documents are read
- Then: the entry is at Meaning version 4 and cites #392 (kept as history),
  #413 and #424; "Yes means" states the floor (at least as capable as
  Implementation, judged on the model, `floor-basis`, a different model not
  required, what the gate cannot rank), says that effort is neither chosen nor
  checked and that the same model at a lower effort therefore meets the floor
  (an accepted risk), with the revisit trigger "when the dispatch tool gains
  an effort parameter", no longer pairs the model with effort and no longer
  says a lower same-model effort is a finding; it keeps the unchanged parts
  (fresh context, complexity, dependencies, `spec-*` NFRs, findings in the PR),
  and Reaches session names the gate script; this repo's own row ends with
  `(meaning v4)` and cites #424; `ARCHITECTURE.md` has A24 (floor-basis), A25
  (`lib/model-record.sh`, `low < medium < high`, marked superseded) and A33
  (the limit and the revisit trigger); `PRD.md`'s Technical debt register has
  a row on short model aliases; the adopter-facing re-surfacing is S141, the
  `process-model-choice` equivalent is S239 and the snapshot sync is S90

### S192 — no live text demands a different Review model, and the old exception attribute is legacy only
**Covers:** F39
- Given: every markdown file except history (`wip/`, `CHANGES-ARCHIEF.md`,
  `CHANGELOG.md`, tests), the frozen `CHANGES.md` snapshot, and the two
  verification scripts and the lib (issue #392, R1/R6, AC2/AC5)
- When: they are scanned
- Then (unchanged by #424, which only removes effort; green throughout and the
  guard that the retiring texts keep their history notes): no paragraph, list item or table row states the old requirement
  ("a different model from/than", "genuinely different", "must use a
  different model") or mentions `same-model-exception` without saying it is
  history or legacy; the scripts mention `same-model-exception` only in
  comments (they do not parse or print it) and call it legacy or ignored;
  the old gate-2 row label is gone

### S193 — model-choice and pre-merge-review state the Review floor once and document floor-basis, without effort
**Covers:** F39
- Given: `skills/model-choice/SKILL.md` and `skills/pre-merge-review/SKILL.md`
  (issue #392, R1/AC1/AC9, human decisions 1-4; issue #424: the floor is on
  the model alone)
- When: their Review-stage text is read, paragraph by paragraph
- Then: the Review row and the pre-merge-review "Model choice" paragraph say
  at least as capable as Implementation, on the model, no longer "model and
  effort together", with no different-model requirement; the "Resolved
  contradiction (#244)" paragraph survives as history saying #392 reversed it;
  the Review marker format shows `floor-basis` (one sentence, required on
  every Review marker, present-checked but never verified), carries no
  `effort` in any template and no longer offers `same-model-exception`; both
  skills say the gate flags a missing `floor-basis` and neither says it flags a
  same-model Review at lower effort; model-choice says two different models
  have no ordering a script can check, documents no effort values, the full
  model id as the platform reports it, and that a short alias and its full id
  count as different models (without an effort comparison being skipped); the
  correlated-blind-spots caveat stays; the accepted limit and its revisit
  trigger are S238

### S194 — free text in a Review marker never hides the marker from either script
**Covers:** F39
- Given: Review markers whose `floor-basis` value contains `>`, `<`, `--`,
  `-->`, `<!--` or a newline, or whose other attributes contain `>`, on a fake
  `gh` for the gate and for the collector (issue #392, review of PR #397:
  the first `>` used to end the marker and hide it; human decision: fix the
  parser, so such values are tolerated, quotes remain the only forbidden
  character)
- When: `model-record-gate.sh` and `compliance-evidence.sh` run
- Then: since #424 "the marker was seen" is proved without effort: the gate
  prints nothing for a same-model Review (lower legacy effort included) with
  such a `floor-basis` (an unseen marker would give "no record found for stage
  Review"), the latest round still wins (a later Review without `floor-basis`
  is the one reported, and the other way round), a marker with `>` in another
  attribute and no `floor-basis` gives exactly the `floor-basis` finding; gate
  2 is `evidenced` for the same model (quoting no effort), different models
  `unverifiable-from-artifacts`, and its evidence never claims a quoted
  illustration or an absent marker for a marker it read; under a lookup
  failure the verdict is `indeterminate` for the guard's reason

### S195 — the collector shares the anchored extraction, ignores an effort-only difference, and names its lib
**Covers:** F39
- Given: markers with a lookalike attribute (`xmodel=`, text ending in
  ` model=`) before the real `model=`; two closing issues whose Review markers
  differ only in legacy effort; the collector run without
  `lib/model-record.sh` (issue #392, review of PR #397, low findings that
  contradict A25; the effort-only conflict retired by #424)
- When: `compliance-evidence.sh` runs
- Then: gate 1 reads the real model (never the lookalike) and treats a marker
  with no real `model=` as malformed; an effort-only difference between the
  issues is no conflict (gate 2 `evidenced`, no conflict text), a model
  conflict still shows both models and no effort; the header's exit-code-3
  entry and the runtime message name `lib/model-record.sh`

### S196 — the marker parser works under a UTF-8 locale and never fails silently
**Covers:** F39
- Given: comment text with non-ASCII right after `stage=` (the placeholder
  prose `stage=…`, bare or backticked, in its own comment or in the marker's
  comment) and inside or outside the quotes of a real marker; a UTF-8 locale
  found with `locale -a` (en_US.UTF-8, nl_NL.UTF-8, C.UTF-8) exported by the
  test, as well as `LC_ALL=C`; a fake `awk` that fails only the parser's
  programs (issue #392, round 3 of the PR #397 review, high finding). Only
  macOS (BWK) awk aborts on a multibyte fragment, so the UTF-8 half proves the
  fix on macOS and the fake awk proves the failure path everywhere; with no
  UTF-8 locale installed the test says so and checks that the parser pins
  `LC_ALL=C`
- When: `model-record-gate.sh` and `compliance-evidence.sh` run
- Then: in both locales a same-model Review (at a lower legacy effort) after
  the placeholder is read (the gate prints nothing, no "no record found"; gate
  2 is `evidenced`, #424), and gate 1 still sees all four stages; when the parser's
  awk fails the gate prints a `model-record:` finding (or exits non-zero) and
  gate 2 is `indeterminate` (or the run non-zero), never "no findings" or a
  definite verdict

### S197 — a malformed marker never swallows a later well-formed one
**Covers:** F39
- Given: Review markers with an odd number of quotes, with no closing `-->`
  (also with another model) or with a nested `<!--`, followed by a
  well-formed marker in the same comment, in a later comment, or before
  further text with a stray quote and `-->`; and a malformed marker AFTER a
  good one (issue #392, round 3 of the PR #397 review, medium finding)
- When: `model-record-gate.sh` and `compliance-evidence.sh` run
- Then: the later well-formed marker is found with its own values (#424: it
  is the one WITHOUT a `floor-basis`, so exactly one `floor-basis` finding
  appears, the malformed ones all carrying one; gate 2 is `evidenced` naming
  the well-formed marker's model, the malformed ones claiming another); a
  malformed marker may produce a finding or be ignored but never wins and
  never gives a verdict from its own attributes

### S198 — role-label-staleness.sh detects a marker whose value contains `>`
**Covers:** F35, F39
- Given: a stale `role:architect` label and a Review marker on the linked PR
  whose `floor-basis` contains `>`, `-->`, `<!--` or `<` (issue #392, round 3
  of the PR #397 review, low finding)
- When: `role-label-staleness.sh` runs against a fake `gh` (S152's recording)
- Then: the verdict is `stale` (the marker's stage is detected, not
  malformed), and a label at the evidenced stage is `in-sync`

### S199 — an unclosed quote stays in its own comment
**Covers:** F39
- Given: a marker whose quote is never closed (Review, Implementation or Test,
  also inside a code fence, with prose around it, several in a row, or in the
  last comment) in comment N, and a well-formed Review or Implementation
  marker in another comment whose first quoted value starts with a space,
  with `-->`, or with a letter (issue #392, round 4 of the PR #397 review and
  the human decision to contain a malformed marker to its own comment)
- When: `model-record-gate.sh`, `compliance-evidence.sh` and
  `role-label-staleness.sh` run against fake `gh`
- Then: the well-formed marker is found with its own values (#424: the gate's
  one `floor-basis` finding, the well-formed marker having none and its first
  quoted value being a `note`; gate 2 `evidenced` naming its model, the
  unclosed marker claiming another; a stale or indeterminate label verdict,
  never in-sync); a malformed marker is a
  visible finding or ignored and never wins, also when it is the latest
  Review marker

### S200 — the comment-boundary byte in a comment body cannot forge a boundary
**Covers:** F39
- Given: comment bodies containing the boundary byte U+001E themselves, next to
  an unclosed marker or inside a marker, and one comment carrying all five
  stage markers separated by that byte, in an opted-in project (issue #392,
  round 4 of the PR #397 review)
- When: `model-record-gate.sh` and `compliance-evidence.sh` run
- Then: safe outcome: the byte inside a body is removed or ignored, so a
  well-formed marker in the NEXT comment is still found with its own values
  (the `floor-basis` finding for the gate, `evidenced` for gate 2, as in S199)
  and one comment stays one comment (five markers in one comment are still
  reported as role-played; five separate comments are not)

### S201 — quoted marker-shaped text is not evidence in the model-record gate either
**Covers:** F39
- Given: a real Implementation marker and a real Review marker (same model,
  no `floor-basis`) in separate comments, and another comment that
  quotes an example Implementation or Review marker in a fenced block (backtick
  or tilde), inline backticks or a blockquote, before, after or in the same
  comment as the real markers; the same inputs through the collector and
  `role-label-staleness.sh`; an indented code block (issue #392, round 5 of the
  PR #397 review: the gate read raw bodies, so a quoted example hid a real
  lower-effort Review; out of scope: five markers inside one fence, issue #400)
- When: `model-record-gate.sh`, `compliance-evidence.sh` and
  `role-label-staleness.sh` run against fake `gh`
- Then: the gate still gives exactly the one `floor-basis` finding of the real
  Review (#424: a quoted Implementation example with an unquoted model would
  add a second finding if counted); a quoted Review example never replaces the
  real latest Review, and a Review marker that exists only in a fence is a
  missing stage, as for the collector; gate 2 stays `evidenced` (the quoted
  examples claim another model) and the label verdict `in-sync`; for
  an indented code block (not stripped by `live_text`, accepted debt) the
  gate and the collector must give the same outcome

### S202 — the gate reports a latest marker whose model cannot be read, for every stage; an unreadable effort is no finding
**Covers:** F40
- Given: PR 246 and its closing issue on a data-driven fake `gh`, with the
  latest marker of one of the five stages having an unquoted, empty or missing
  `model` (the dry-run shape `model=claude-haiku-4-5 effort=low` included), or
  an unquoted, empty or missing `effort`, or a placeholder, a quoted example in
  a fence, a code span or a blockquote, a missing marker, an earlier bad marker
  superseded by a later good one; plain, opted-in and not-opted-in projects
  (issue #402, R3/R4, AC3-AC6, A26 and the human decisions of 2026-10-03;
  the effort arms reversed by #424, A33)
- When: `model-record-gate.sh 246` runs, and `compliance-evidence.sh` on the
  same input
- Then: the gate prints one `model-record:` finding per stage for an unreadable
  `model`, naming the stage and the model and not effort, exit 0, never a
  `role-played:` line, in every kind of project; Implementation and Review
  unreadable together are two lines; only the latest marker of a stage counts;
  an unquoted, empty or missing `effort` gives no finding at all (the per-field
  check is reduced to `model`), also beside an unreadable model (still one
  line); a quoted marker (also a legacy `effort="unknown"`), an unrelated
  unquoted attribute, a placeholder, a quoted example and a missing marker (its
  existing "no record found" line only) give no new finding; the collector
  stays `indeterminate` for the unreadable model (gate 1 for the four earlier
  stages, gate 2 for Implementation) and `evidenced` for a well-formed run; a
  hand-typed `stage="Planning"` marker is reported as malformed next to the
  stage's "no record found" line (A26 amended)

### S203 — the orchestrator hands each role its marker line from the one template
**Covers:** F40
- Given: `skills/role-contracts/ORCHESTRATOR.md`, `skills/role-contracts/SKILL.md`,
  `model-choice` and `pre-merge-review` (issue #402, R1/R2, AC1/AC2, A26;
  whether the orchestrator really pastes the line and the role posts it
  unchanged is model behaviour, shown by the scratch-repo re-run)
- When: they are read, paragraph by paragraph
- Then: one paragraph of `ORCHESTRATOR.md` (A26 amended: nobody types a
  marker) gives each role the `model-record-emit.sh` command in its dispatch
  prompt, found through `SPEC_DRIVEN_GUARDRAILS_DIR` or the installed skill, with
  `--stage` filled in and no `--effort` (#424: nothing says to pass it or to
  fill it with `unknown`), names the requested model, has the role add `--model` with its own
  exact id (the Reviewer also `--floor-basis`) and paste the output unchanged
  as the first line of its report; `ORCHESTRATOR.md` restates no grammar (no quoted-attribute
  example, no spelled-out marker line, no effort values, no quoting rule);
  `model-choice` keeps the two templates (without effort) as the single copy and no skill shows a
  quoted stage and no second template exists outside `model-choice` and
  `pre-merge-review`; `model-choice` and `pre-merge-review` say the line is
  produced with the wrapper and never typed; `role-contracts` says a report's
  first line is the wrapper's output, never typed, and that a role whose prompt
  has no command runs the wrapper itself and says so

### S204 — model-record-emit.sh prints the one valid marker line, which rec_scan and rec_field read back field by field (and today's parser reads too), or prints nothing (E1 and E2)
**Covers:** F40
- Given: `skills/pre-merge-review/model-record-emit.sh --stage <Stage> --model
  <id> [--floor-basis <sentence>]` and `marker_emit <Stage> <model>
  [<floor-basis>]` in `lib/model-record.sh` (issue #402, A26; no effort since
  #424; rewritten on E1 and E2 by issue #425, slice V4 of #411, AC4, A33 as
  amended by A33a); a matrix of valid inputs (all five stages; model ids with
  dots, dashes, colons, slashes, digits, a leading dash, 200 bytes; a Review
  floor-basis with `'`, `--`, `=`, ` model=` and ` floor-basis=` at its end,
  `$`, a backtick, `*`, a leading `--`, non-ASCII; the code points the deny-list
  lets through: NBSP, zero-width characters, U+200E, U+2027, U+202F, U+2065,
  U+206A, U+FFFD, an emoji; invalid and truncated UTF-8; 500 bytes of ASCII,
  166 em dashes, 498 ASCII bytes plus one two-byte letter, 250 two-byte
  letters); a matrix of refused ones; three environments (`LC_ALL=C`, a UTF-8
  `LC_ALL`, and `LC_ALL` unset with `LANG` UTF-8); the real path and a symlinked
  `.claude/skills` (an adopted project)
- When: the wrapper runs
- Then (E1): every valid input prints exactly the LITERAL line `<!--
  model-record: stage=<S> model="<M>"[ floor-basis="<F>"] -->` (bare stage, no
  effort attribute, nothing on stderr), which `rec_scan` reads as one ok row
  for the stage holding the line verbatim, `rec_field` returns `model` and
  `floor-basis` byte for byte (and nothing for effort), and today's
  `marker_find`, `marker_scan` and `marker_attr` read too; `marker_emit` agrees
  with the wrapper; a stale `--effort high` still gives the literal line; five
  emitted lines give the gate no finding
- Then (E2): every refused input prints nothing on stdout, a reason on stderr
  and exits 2: a quoted, lower-case, empty or unknown stage; an empty, over-
  long (201 bytes), non-ASCII or quote/space/newline/tab/`=`/`<`/`>`/`-->`/
  `$(...)` model; a Review floor-basis that is missing, blank, over 500 BYTES
  (501 ASCII bytes, 167 em dashes, 251 em dashes = 753 bytes, 499 ASCII bytes
  plus a two-byte letter, 251 two-byte letters) or holds `"`, `<`, `>`, `-->`,
  `<!--`, any of the 31 C0 controls (LF, CR and tab included), U+001E, DEL, any
  of the 32 C1 controls U+0080 to U+009F as UTF-8 bytes, U+2028, U+2029,
  U+202A to U+202E or U+2066 to U+2069; a floor-basis on another stage;
  unknown, missing, repeated or value-less flags, a positional argument, and
  a flag value equal to a flag name (`--model --floor-basis`, `--floor-basis
  --stage`, ...) while a floor-basis that merely begins with `--` is accepted;
  without the lib the exit status is 3 with empty stdout. Threat model:
  accidental defects (characters versus bytes, a deny-list entry left out, a
  locale-dependent control-class test); a typed strict line is byte-identical
  to emitter output (stated limit). The emitter's own round trip is defence in
  depth with no red-only test. Retired from the old S204: the old-parser-only
  judgement and the arms that accepted `>`, `<`, `-->` or `<!--` (refusals now).
  Red today on the red commit: the `<`, `>`, C1, separator, bidirectional,
  byte-limit and flag-name refusals, and every `rec_scan` and `rec_field`
  judgement (stubs). Kill table: drop `<` or `>`, count characters, drop one C1
  or bidi or separator entry, a locale-dependent control test, drop or widen
  the flag-name rule, change the literal line

### S205 — the role-play check's "stages missing" test ignores quoted text
**Covers:** F38
- Given: an opted-in project, a PR whose Planning, Test and Implementation
  markers are real and whose Review stage is only named in quoted text: a
  code span, a backtick or tilde fence, a blockquote, report prose quoting the
  gate's finding and the marker form, the PR description (issue #369, holistic
  review finding B2); a real Review marker as the control; three stages in one
  comment plus a quoted Review mention
- When: `model-record-gate.sh 246` runs on a fake `gh`
- Then: `role-played: stages missing: Review` is printed for every quoted
  form (a quoted mention is not a present stage), a real Review marker gives a
  clean run, the one-comment run is still reported, and a project that did not
  opt in sees no `role-played:` line and the existing "no record found" line.
  Five markers inside one fence (issue #400) is not asserted: it is reported as
  stages missing by the same one-line change, whichever way #400 is decided

### S206 — the script paths named in finding B5 resolve from an adopted project
**Covers:** F37, F40
- Given: a freshly adopted project (`adopt.sh`), and `pre-merge-review`,
  `model-choice` and `ORCHESTRATOR.md` read through its `.claude/skills/`
  symlinks (issue #369, holistic review finding B5; scope narrowed by the
  maintainer's orchestrating session to the paths B5 names: the gate-script
  paths in `pre-merge-review` stay with the open issue #387)
- When: the paths in their run instructions are resolved from the project root
  and the emit wrapper is executed
- Then: the emit wrapper path as written in `pre-merge-review` and
  `model-choice` exits 0 (not 127, no `--effort` needed, #424) and prints the
  effort-free line, a stale `--effort` still works from the project with its
  one stderr warning, and neither names the bare
  `skills/pre-merge-review/model-record-emit.sh`, every "Run `<path>`" command
  path in ORCHESTRATOR.md resolves (`.claude/skills/...`,
  `$SPEC_DRIVEN_GUARDRAILS_DIR/...` or `./name.sh`), and
  ORCHESTRATOR.md names `role-label-staleness.sh` by
  `$SPEC_DRIVEN_GUARDRAILS_DIR/role-label-staleness.sh` and says to run it with
  the project's checkout as the working directory, not "from the guardrails
  clone"

### S207 — merging is human-only only for main, and the text says so once
**Covers:** F38
- Given: `ORCHESTRATOR.md` and `role-contracts/SKILL.md`, loaded into the same
  session as `WORKFLOW.md` and `release-branch-workflow` (issue #369, holistic
  review finding B3)
- When: every unit that states the human-only merge rule is read
- Then: each also names `main` and the release-branch exception
  (`release-branch-workflow`); `ORCHESTRATOR.md` states the rule once (roles
  never merge, merges into `main` wait for the human, a work-item PR into a
  release branch follows the skill); `WORKFLOW.md` and the skill keep their
  side (controls)

### S208 — the README says the release-branch tier is adoptable, and model-choice says the recorded model is self-reported
**Covers:** F37, F39
- Given: `README.md`, `model-choice`, and the registry facts (`adopt.sh`
  installs `release-branch-workflow`, `pending-changes.sh` asks its question)
  (issue #369, holistic review finding B4; the honesty note moved from effort
  to the model by #424: A33a words the same-model floor as "by the model-only
  floor, on self-reported model strings")
- When: they are read
- Then: the README no longer says the tier is not adoptable, no longer lists
  it under what an adopted project does not get and no longer contrasts it as
  "unlike" the five-role pipeline; it says an adopted project is asked about it
  and gets the skill; `model-choice` says in one sentence that the model in a
  marker is self-reported and unverified, and no longer has the sentence that
  the effort is self-reported unless the platform set it

### S209 — every Review round is a fresh Reviewer dispatch, and the orchestrator may not continue one
**Covers:** F41
- Given: `skills/role-contracts/SKILL.md` (Reviewer section),
  `skills/role-contracts/ORCHESTRATOR.md` and `skills/pre-merge-review/SKILL.md`
  (issue #414, AC1, AC2)
- When: each is read for the rule on repeat Review rounds
- Then: each states that every Review round is a new dispatch of a fresh agent
  and that a Reviewer is never continued or resumed; `ORCHESTRATOR.md` forbids
  it for the Reviewer explicitly, in one sentence naming both `SendMessage`
  and the dispatch tool's `fork` type (also in the Reviewer contract and
  `pre-merge-review`), says roles are started as a new agent never by that
  `fork` type, imposes no `SendMessage` ban on other roles, and leaves
  continuing another role for a later step to #412

### S210 — a later round's brief is built from artifacts, and carried-forward findings are inputs
**Covers:** F41
- Given: `ORCHESTRATOR.md` and the carry-forward text of `pre-merge-review`
  (issue #414, AC3, AC4)
- When: the brief for a later Review round is read
- Then: it names the PR head SHA and diff, the work-item issue, and the previous
  round's findings as inputs, and says it never includes the earlier
  Reviewer's conversation, a summary of it, or recollection; `pre-merge-review`
  says the previous round's findings are inputs the new Reviewer re-checks
  against the new head, not memory

### S211 — the limit on proving a fresh agent is stated, with the pipeline-log and self-check fallback
**Covers:** F41
- Given: `ORCHESTRATOR.md` (issue #414, AC5 case b)
- When: the pipeline log and the pre-merge self-check are read
- Then: the pipeline log has one line per dispatch with the agent id, is never a
  `model-record` marker, and the mandatory "Before asking for a merge"
  self-check (its result recorded as a line in the issue's Pipeline log) has a
  line that every Review round has its own agent id and no message went to an
  earlier Reviewer; the text states plainly that GitHub artifacts cannot show
  whether two rounds came from different agent instances, so the line is a
  recorded self-check, not a pass

### S212 — in pre-merge-review a bare "fork" means only `context: fork`
**Covers:** F41
- Given: `skills/pre-merge-review/SKILL.md` after the fresh-Reviewer rule
  (issue #414, A27, round 1 finding 7)
- When: it is read for the word "fork"
- Then: apart from `context: fork` and "the dispatch tool's `fork` type", no
  "fork" remains, so no reader can take the single-Reviewer or lens-Adapter
  runs for the dispatch type the rule bans; they are named as runs

### S213 — a finding names its class and a falsifying check, and a Reviewer never gives a fix
**Covers:** F42
- Given: `skills/role-contracts/SKILL.md` (finding structure) and
  `skills/pre-merge-review/SKILL.md` (issue #410, AC1, A28)
- When: the finding structure and the Reviewer rules are read
- Then: the structure has a Class field with the four values `design`, `code`,
  `test` and `spec`, and a Falsifying check field (the observable condition a
  correct fix must meet); a finding names the defect, its class and a
  falsifying check and never a fix, patch or code, the same for QA and the
  Developer; there is no exception for a typo-level or trivial finding

### S214 — each class is routed to the role that owns the fix, from any stage
**Covers:** F42
- Given: `skills/role-contracts/SKILL.md` and `ORCHESTRATOR.md` (issue #410,
  AC2, A28; the fresh Reviewer is #414)
- When: the loop-back route is read
- Then: both give the route per class (`design`: Architect, QA, Developer,
  fresh Reviewer; `code` and `test`: QA, Developer, fresh Reviewer; `spec`:
  Product, then QA, Developer, fresh Reviewer); `ORCHESTRATOR.md` says the
  orchestrator never relays a Reviewer's suggested fix as a decision, never
  downgrades a class (role-contracts says so too, and neither file says
  "nobody downgrades": the Architect may record that a finding is not a design
  defect and route it as code) and dispatches the Architect when a design class
  is in doubt or a finding has no class, and says a Developer or QA that finds a
  design defect stops the change, saves the attempted patch and reports
  class `design`

### S215 — two consecutive rounds with a medium-or-worse finding force an Architect step, and the count resets
**Covers:** F42
- Given: `ORCHESTRATOR.md` (issue #410, AC3, A28)
- When: the two-round trigger is read
- Then: a round counts when it has at least one open medium-or-higher finding,
  new or carried over; two consecutive counting rounds on one PR send the
  orchestrator to the Architect before any Developer fix; the Architect posts a
  PR comment with a Planning marker and may conclude no design change is
  needed; the count starts again after that recorded step

### S216 — review-rounds.sh counts Review rounds and reports Planning markers after each
**Covers:** F42
- Given: a PR (and its issue) whose comments and reviews carry `model-record`
  markers, behind a fake `gh` (issue #410, AC4, A28)
- When: `review-rounds.sh <pr> [<issue>]` runs
- Then: it prints one `review-round: <n> at=<timestamp>` line per body (a PR
  comment or PR review) whose first live marker is a Review marker (a
  malformed one still counts; two Review markers in one body are one round; a
  body that only has a `pre-merge-review:done` marker counts; a body whose
  first marker is another stage does not), in time order (A37), a
  `planning-after: <n>` line for each round a Planning marker on the PR or the
  issue follows (the latest round before it), the summary
  `review-rounds: <N>` and a line saying severity is not machine-readable;
  a body that only mentions `pre-merge-review:done` in prose is not a legacy
  round (only the marker form `<!-- pre-merge-review:done sha=<40 hex> -->`
  is); on equal timestamps the order is issue comments, PR comments, PR reviews,
  visible through where a Planning marker lands;
  bodies without such a first marker and quoted example markers count for
  nothing; zero rounds gives `review-rounds: 0`; it always exits 0

### S217 — review-rounds.sh is read-only, REST-only, never blocks, and a failed fetch is a visible warning
**Covers:** F42
- Given: `review-rounds.sh` behind a recording fake `gh` (issue #410, AC4,
  A28, A37)
- When: it runs, with a failing `gh`, a failing endpoint, no `gh`, no
  argument or a malformed PR number
- Then: every `gh` call is a plain `api` GET (no write verb, no GraphQL);
  a failed fetch prints a warning on stderr, no `review-rounds:` summary, and
  exits 0; a missing argument or malformed number prints usage and calls
  nothing; markers are read only through `lib/model-record.sh`; the script uses
  no bash 4 feature or GNU-only tool, runs under macOS `/bin/bash` 3.2, keeps
  the round definition in one function (`rr_rounds`, A37) and is wired into no
  hook, check or gate

### S218 — the self-check lines, the stated limit and the override pointer to #415
**Covers:** F42
- Given: `ORCHESTRATOR.md`, its "Before asking for a merge" self-check (issue
  #410, AC5, AC6, A28)
- When: the self-check and the override text are read
- Then: the self-check list says no design-class finding was fixed without an
  Architect step and the two-round trigger either did not fire or its Architect
  step is on the PR, and names `review-rounds.sh` and says it runs with the
  project's checkout as the working directory (it reads that repository); the text states the limit
  (class and severity are judgments, a script can only check that the route
  left evidence); overriding the route is a numbered human decision on the
  issue that names the rule overridden and follows the pushback and risk-note
  flow of #415 (A29) without defining a format of its own

### S219 — `.github/workflows/macos.yml` is pinned whole: a closed byte alphabet, comments only in the header, the rest exactly the expected block
**Covers:** F43
- Given: `.github/workflows/macos.yml`, the macOS leg's own workflow file (issue
  #422, AC1, A35c D1/D2, hardened by A35d D1/D2, which replaced A35b D3's
  reader of `ci.yml`)
- When: two rules are applied in order. D1, byte alphabet, on the raw file
  first: `LC_ALL=C grep -an '[^ -~]'` must find nothing, i.e. the file holds
  only LF and printable ASCII (0x20-0x7E). D2, header-only comments: only the
  leading run of blank and full-line-comment lines before `name:` is stripped,
  with `LC_ALL=C awk 'started || !/^[[:space:]]*(#|$)/ { started = 1; print }'`,
  and from `name: CI macOS` to the end the file is compared byte for byte with
  the block written inline in the case (triggers `pull_request` and `push` to
  `main`; one job `macos` on `macos-latest` with `permissions: contents:
  read`, `env` `LANG` and `LC_ALL` both `en_US.UTF-8`, and the four steps
  checkout, platform tools first on PATH, `brew install mawk`, and the suite
  step `run: /bin/bash test/run.sh`)
- Then: the file exists, passes D1, and the D2 comparison is identical; any
  other content is red. A D1 failure prints the first three offending lines
  through `LC_ALL=C sed -n l` (so a `\r`, `\357\273\277` or `\303\251` is
  visible); a D2 failure prints the diff through the same `sed -n l` (POSIX,
  so it shows the bytes on BSD and GNU alike; `cat -A` is not used). No YAML
  is parsed and no list of bad spellings is kept. Red: a skipped or swallowed
  suite (a `|| true` or `; exit 0` continuation, quoted or `?` keys,
  `if`/`continue-on-error`, a top-level `defaults`, a decoy job in a block
  scalar, an under-indented scalar), a deleted or duplicated job, a step that
  rewrites `test/run.sh` or writes `BASH_ENV`/PATH, a job `env:` that sets
  `S229_INNER` or `PLATFORM_IDENTITY_UNDER_TEST`, a changed trigger, trailing
  whitespace, tab indentation; every byte outside the alphabet (a lone CR
  inside a header or body "comment" that hides a key such as `if: false`,
  `continue-on-error: true`, `defaults:` or `env: BASH_ENV`; NEL and LS in the
  same place; whole-file CRLF; a BOM; a tab; `é`; a form feed; a NUL); any
  comment or blank line after `name:` (a comment as the first line of the
  `run: |` block, an indent-8 comment between its two `echo` lines, a trailing
  comment or blank line at the end of the file). Green: the unchanged file;
  adding, editing or removing ASCII comment lines and blank lines in the
  header; a missing final newline. Changing the pinned block is a deliberate
  spec change that also edits this scenario. The case reads
  `CI_MACOS_YML_UNDER_TEST` when set (mutation proofs). The tools and the
  locale are not judged here; S229 judges them at run time
- File kind (A35d-2, finding 25): the candidate must be a regular file, and
  `-L` is tested before `-f` because `-f` follows links. In the working tree,
  on every run including through the seam: `[ -L "$macos_yml" ]` is red, then
  `[ ! -f "$macos_yml" ]` is red, both with the message "not a regular file".
  Permanent arms, run through the seam in a child process, each red with that
  message: a symlink to a byte-identical pinned copy (it passes D1 and D2, so
  only the kind check kills it), a dangling symlink, a directory, a FIFO (the
  arm is skipped, with a note, where `mkfifo` is unavailable); the unchanged
  regular file stays green. Committed state, only when the seam is unset:
  `git ls-files -s -- .github/workflows/macos.yml` must report mode `100644`;
  `120000` (symlink), `160000` (gitlink), `100755` (executable) and empty
  output (untracked, or not a git checkout) are red. That half has no
  permanent arm; it was proven once in a throwaway clone and reported in the
  PR. A hardlink needs no check (git has no hardlink mode; the blob is pinned
  by content)

### S222 — regression: the Linux job is unchanged and ci.yml has no macOS mention
**Covers:** F43
- Given: `ci.yml` (A35c D1: the macOS job moved out, `ci.yml` is back to its
  content on `main`)
- When: the `ubuntu-latest` job is read and the non-comment lines of `ci.yml`
  are searched case-insensitively for `macos`
- Then: exactly one such job still runs `./check`, the gitleaks step, the link-3
  and main-via-PR steps, `fetch-depth: 0` and its issues/pull-requests read
  permissions, and no non-comment line of `ci.yml` contains `macos` (a runs-on,
  a matrix entry, a block-list label such as `macOS`, or a step name all turn
  it red; a full-line comment that mentions it does not; a step that
  legitimately names macOS later changes this one check). It is a regression
  scenario that claims no closed world, so a new non-macOS job or a new step
  in the Linux job does not turn it red
- Limits: line-based; a CR or encoded spelling can hide a job (#442)

### S224 — a non-BWK awk or non-BSD grep fails `test/platform-identity.sh`, naming the tool
**Covers:** F43
- Given: `bash test/platform-identity.sh` (no arguments) run on a macOS host
  with a PATH shim that reports GNU awk (or GNU grep) and records its
  invocation
- When: the script runs
- Then: it exits non-zero, its `FAIL:` line names the mismatched tool, and the
  shim was invoked; a control run on the real macOS tools exits 0 and prints
  one identity line each for awk, grep and bash plus a line starting with
  `locale charmap:` (not merely the word `locale`, which the `locale:` line
  already satisfies) (macOS host only)

### S225 — a bash that is not 3.2 fails `test/platform-identity.sh`, naming bash
**Covers:** F43
- Given: the script run on a macOS host with a PATH shim reporting bash 5, and
  with the running `$BASH_VERSION` not 3.2 (a startup-file override, and a real
  bash 4 or later where one is installed)
- When: the script runs
- Then: it exits non-zero and its `FAIL:` line names bash (macOS host only; the
  real bash 4 arm prints a note and is skipped where none is installed)

### S226 — a locale that is not installed fails `test/platform-identity.sh` and is never skipped
**Covers:** F43
- Given: the script run on a macOS host with the real tools, `LANG` naming a
  locale that is not installed (`xx_XX.UTF-8`) and `LC_ALL` unset; no
  `locale` shim
- When: the script runs
- Then: it exits non-zero and its `FAIL:` line names the locale; it never exits
  0 (macOS host only). A missing locale is covered by the `locale charmap`
  check alone: a locale that is not installed does not give a UTF-8 charmap.
  Limit: AC3 (the macOS job red and the Linux job green on a real
  locale-class defect, a throwaway-branch run linked from the PR) is a
  human-visible hosted-runner result and cannot be a unit test

### S227 — a locale that is installed but not in effect fails `test/platform-identity.sh`
**Covers:** F43
- Given: the script run on a macOS host with the real tools and the effective
  locale C: `LANG=en_US.UTF-8` with `LC_ALL=C`, with `LC_CTYPE=C`, and with
  `LANG` empty
- When: the script runs
- Then: each run exits non-zero and its `FAIL:` line names the locale (macOS
  host only; the runner image's `LC_ALL` could otherwise drift to C unnoticed)

### S228 — regression: the marker parser reads a body with an invalid UTF-8 byte inside a marker under a UTF-8 LANG
**Covers:** F43
- Given: `lib/model-record.sh`, `LC_ALL` unset, `LANG=en_US.UTF-8`, a marker
  whose value holds the byte `\377` (issue #422, AC3's precondition)
- When: `marker_scan` and `marker_find` read it
- Then: both exit 0, `marker_scan`'s output reports the stage `Test`, and
  `marker_find`'s output is non-empty and contains the value carrying `\377`
  (an empty result is red); green today because each awk call carries the
  `LC_ALL=C` prefix, red on BWK awk (macOS) when the prefix is removed from the
  `marker_scan` or the `marker_find` call (gawk may not abort, so the macOS leg
  is where it bites). The case guards `marker_scan` and `marker_find` only;
  `marker_attr` and `marker_emit` are not guarded, because removing their
  `LC_ALL=C` does not abort on BWK awk (equivalent mutants)

### S229 — on the macOS CI leg the suite runs the platform identity check in its own environment
**Covers:** F43
- Given: the suite case `test/cases/s229_platform_identity_in_suite.sh` (issue
  #422, AC1, AC2, A35b D1); the gate is `GITHUB_ACTIONS=true` and
  `RUNNER_OS=macOS`, both set by the runner
- When: the case runs under the suite's own PATH, bash and locale
- Then: with the gate open it runs `bash test/platform-identity.sh`, puts the
  identity lines in its log, and is red naming the tool or locale on a
  mismatch; otherwise it prints `note: platform identity not asserted (not the
  macOS CI leg)` and passes. Arms, run in a child with a controlled
  environment: (a) a GNU awk shim first on PATH with both CI variables set is
  red and names awk; (b) `RUNNER_OS=Linux` with the same shim is green and
  prints the note; (c) on a macOS host only (`uname -s` is Darwin, otherwise
  the arm is skipped with a note), both CI variables set, the real tools and no
  shim is green and its output has lines starting `awk:`, `grep:`, `bash` and
  `locale charmap:`; (d) `RUNNER_OS=macOS` with `GITHUB_ACTIONS` unset and the
  GNU awk shim is green, prints the note and never calls the shim; (e) both
  variables unset with the same shim is the same. Limits: the gate cannot
  prove from inside the suite that it fired in CI (the green macOS log showing
  the identity lines, not the note, and a throwaway red run are the evidence);
  subversion through `macos.yml` (`BASH_ENV`, an overridden `RUNNER_OS`, a job
  `env:` setting `S229_INNER`, changed triggers) is red under S219, while the
  suite's own files and settings outside the repository are trusted

### S230 — live_text reads a body with an invalid or truncated UTF-8 sequence the same under a UTF-8 LANG as under LC_ALL=C, in the lib and in all three callers
**Covers:** F34, F35, F39
- Given: `LC_ALL` unset (by the case itself) and `LANG=en_US.UTF-8`; three
  bodies, one holding `\377` (an invalid UTF-8 byte), one a truncated
  `\342\200`, one a valid multibyte character (the green control, `\342\200\224`);
  each placed in a live marker value, in a fenced line, in a code span and in a
  blockquote (lib arms), in the Review record's `floor-basis` (gate main
  path), in a body holding two stage records (the gate's role-play path), in a
  PR comment's Test record (collector), and in a Review record of a linked PR
  (staleness script); the callers run against fake `gh`, the bytes reach the
  gate through a placeholder swapped after `jq` (jq itself would turn the
  byte into U+FFFD)
- When: `md_strip_fences` and `live_text` of `lib/markdown.sh`; the gate (main
  path, and role-play path in an opted-in project); the collector; and the
  staleness script each read the body, once under `LC_ALL=C` and once under
  the case's UTF-8 environment
- Then: no reader aborts, and each result equals the `LC_ALL=C` result, which
  is itself asserted non-trivial so a vacuous pass is red: the lib keeps the
  marker line and blanks the fenced one; the gate main path prints no
  `model-record:` finding for a complete run (and names the missing stage
  when the Review record is removed); the role-play path prints `role-played:
  stages in one text: Implementation, Review`; the collector's rows 1-3 are
  `evidenced`; the staleness verdict is `stale`. The body bytes must also
  survive the callers' own decoding of `\001` (their `tr`), not only
  `live_text`. Red today on a macOS host (BWK awk, BSD tools): the role-play
  arm, the collector arm and the staleness arm; regression arms (green on
  arrival): the gate main path, the valid-multibyte control, every C-locale
  baseline. Mutations (A35a K3): remove the `LC_ALL=C` prefix from the awk
  call in `lib/markdown.sh`; remove it from the gate's role-play read; drop
  the `LC_ALL=C` in a caller's `tr '\001' '\n'`. On a non-macOS runner the
  awk-abort mutants can pass (gawk and mawk do not abort), so the macOS leg is
  where this scenario bites
- Round 1 of PR #443 adds the bytes BEFORE the marker on the same line
  (`x\377y <marker>`; also the truncated sequence; valid multibyte as the
  green control). BSD grep in a UTF-8 locale finds no match after such a byte,
  so every caller `grep` that reads the live text, and every caller `tr`, must
  carry its own `LC_ALL=C`: the gate's main path (all five stages after the
  bytes: no finding), its role-play path (two stages in one body, on separate
  lines and on one line: `stages in one text`), its override reader (a
  single-session override after the bytes, and bytes before each of its three
  attribute greps); the collector (one record per body source, each after the
  bytes: the closing keyword in the PR title, Planning and the done marker in
  the PR body, Test and Review in PR comments, Implementation in a PR review,
  Discovery in the closing issue's comment, rows 1-3 `evidenced`; a malformed
  done marker after the bytes still reads "not in the recognized shape"; a done
  marker only in a code span after the bytes still says "only inside a code
  span"); the staleness script (the Review marker after the bytes in the issue
  body, an issue comment, the PR body, a PR comment, a PR review, and the
  closing keyword after the bytes in the PR title and in the PR body: verdict
  `stale`). Each result, rows with their evidence text included, equals the
  `LC_ALL=C` result, which is itself asserted non-trivial. `normalize_model`
  of `lib/model-record.sh` (finding lib-normalize-locale): a model value
  holding `\377` or `\342\200` normalizes to `opus 5` under both locales with
  nothing on stderr (BSD `tr` aborts with "Illegal byte sequence" otherwise).
  Mutations, each killed on a macOS host (BSD grep, BSD tr, BWK awk): remove
  `LC_ALL=C` from any one of the gate's greps (stage check, role-play
  stage_ere, the three override attribute greps, the override reader, the
  stages-missing check), the collector's quoted-suffix, closing-keyword, stage,
  done-marker and loose-marker greps and its four `tr` sites, the staleness
  script's closing-keyword grep and its six `tr` sites, and the `tr` and the
  second and third `sed` of `normalize_model`. Not killable, equivalent
  (the input is the `-o` output of a C-locale grep, or has already lost the
  invalid byte, so it is ASCII): the collector's `[0-9]+` and `sha=` greps on
  a `-o` result, the gate's `grep -qx` on stage names, the `sed` after a
  `grep -o`, the first and the last `sed` of `normalize_model` (BSD sed
  only reads past the start of an anchored match once a match is found)
- Round 3 of PR #443 (A32c; findings c-locale-grep-callers round 2,
  lib-normalize-locale round 2, normalize-sed1-untested, collector-cell-locale):
  the four scripts export `LC_ALL=C` as their first statement, so these arms
  go red when that export is removed from their script. Gate: a PR description
  (and a PR title) of `x<bytes>y Closes #239` finds #239 (Discovery recorded
  only there) and prints nothing, as under `LC_ALL=C` (the raw-title and
  description closing-keyword grep, line 161); a Review record with a legacy effort
  `low<bytes>` on the same model as Implementation `high` gives no finding at
  all and the same output in both locales (#424: no effort is read; the old
  lower-effort arm is retired). Collector: the FULL output, evidence column and stderr
  included, is byte-identical in both locales for the Test record at
  `model="claude-sonnet-5<bytes>"` (no status-only workaround), and for two
  closing issues whose legacy Review efforts are `low<bytes>` against `low` or
  `high` (no conflict since #424: gate 2 `evidenced` and the full output
  byte-identical in both locales). Lib: `effort_rank` and its arm are retired
  with the function; `normalize_model` of values
  that do NOT start with `claude` (`opus-5<bytes>`, `<bytes>claude-opus-5`,
  `claude<bytes>-opus`, `x<bytes>`) is identical in both locales with an empty
  stderr (BSD `sed` aborts on input whose anchored match fails before the
  byte; QA's earlier "equivalent" call for the first `sed` was wrong). Red
  today on a macOS host: the gate arms and the collector arms; the `normalize_model` arm is green on arrival and kills
  the scratch mutant that drops the first `sed` prefix (via `MR_LIB`). Not
  behaviourally reachable, so guarded by S235 alone: the staleness script's
  and `review-rounds.sh`'s export (their remaining unprefixed commands read
  numbers and label names); removing either export leaves S230 and S234 green
  and S235 red. Mutations killed (scratch tree with the A32c fix applied): gate
  export removed (4 failing assertions), collector export removed (12),
  first `sed` prefix removed (16); (the `effort_rank` prefix mutant, 4, is
  retired with the function)

### S231 — a live_text failure is visible: a model-record: finding in the gate, indeterminate in the collector and the staleness script
**Covers:** F34, F35, F39
- Given: a PATH shim named `awk` that counts its own invocations in a file and
  exits 2 for the calls selected by the case (all calls, or exactly call k),
  and otherwise runs the real awk; the gate in an opted-in project with all
  five stages recorded, the collector with one record per reading site (the
  PR body holds Planning and the done marker, a PR comment Test and Review, a
  PR review Implementation, the closing issue's comment Discovery), and the
  staleness script with `role:architect` behind a Review record that sits, in
  turn, in the issue body, an issue comment, the PR description, a PR comment,
  a PR review, and a PR comment of a PR whose closing keyword is only in its
  title (as in release-branch PRs), each against fake `gh`
- When: each script runs once with the shim passing everything through (the
  baseline, which also gives the number T of awk calls it makes), once with
  every awk call failing, and T more times with exactly one call k failing
- Then: the baseline call count is above zero (a script that never reaches
  awk makes the arms vacuous) and the verdict is the clean one (no
  `model-record:` finding, rows 1-3 `evidenced`, `stale`); with every call
  failing the gate prints a line starting `model-record:`, rows 1-3 of the
  collector are all `indeterminate`, and the staleness verdict is
  `indeterminate`; with call k failing alone the gate prints a
  `model-record:` finding for every k, the collector's rows 1-3 are each
  `evidenced` or `indeterminate` and never `not-evidenced` or
  `unverifiable-from-artifacts`, and the staleness verdict is `stale` or
  `indeterminate`, never `in-sync` or `not-started`; the shim's count is above
  zero in every failing run. A failure is never read as "no record". The
  sweep reaches the gate's role-play read (its last awk calls), which today
  ignores a `live_text` failure, and each of the collector's and the staleness
  script's several call sites without naming them. Closes the PRD debt row at
  `PRD.md:1712`. Not asserted: the wording of a finding or evidence line.
  Mutations (A35a R6, D10): the gate's role-play `check_text` ignores a
  failure; the failure flag removed from any one of the collector's call
  sites, or from any one of the staleness script's call sites (each site is
  made decisive by the spread above, so each removal turns a row or the
  verdict into an absence claim)
- Round 1 of PR #443 (finding gate-frame-failure-test): in the gate's
  single-failure sweep, the run with call k failing never prints a
  `role-played:` line either: with all five stages recorded, a "stages
  missing" line can only come from a body read as empty. Mutation: the gate's
  `live_frame` stops returning a failure (it prints the misleading "no record
  found" AND a blocking "stages missing" line; the first alone is still a
  `model-record:` line, which is why the existing assertion missed it). A gate
  copied without `lib/model-record.sh` prints a `model-record:` finding
  (regression arm; the gate's "lib not readable" branch is redundant with the
  127 of the first `live_text` call, so dropping its `live_failed=1` is an
  equivalent mutant, not a gap)

### S232 — a fence opened on a list-item line is recognized, and a backtick fence whose info string holds a backtick is not an opener
**Covers:** F34
- Given: `lib/markdown.sh` under `LC_ALL=C`; a marker INSIDE (indented as list
  content) and a marker AFTER (column 0, after the closing line); bodies with
  a fence opened on a list-item line (`-`, `*`, `+` with a tilde fence, `1.`;
  with an info string; a longer closing run; a second item; two list-item
  fences in a row; a shorter run inside a longer fence), and bodies with a
  backtick fence line whose info string holds a backtick (also indented 3
  spaces, also four backticks)
- When: `live_text` and `md_strip_fences` read each
- Then: the output is exactly the body with the fenced lines (opener, content,
  closing) blanked and the line count kept: INSIDE is quoted, the column-0
  AFTER marker is live (as GitHub renders it: the closing line cannot open a
  false fence that hides the later marker); a line `` ``` not `a fence ``
  opens nothing, so the marker after it is live, and a later bare run opens
  its own fence that runs to the end of the body (the INSIDE marker before it
  is live, the AFTER marker after it is quoted); a tilde fence whose info
  string holds a backtick still opens, a backtick fence whose info string
  holds a tilde still opens, and a bullet line that merely mentions three
  backticks opens nothing (regression arms). The PR records the
  `gh api markdown` output for these shapes once, as evidence and not as a CI
  oracle. Mutations: do not recognize the list-item prefix; treat a backtick
  in the info string as an opener; require the closing line at column 0;
  close on a shorter run
- Round 1 of PR #443 (A32b, finding list-fence-container-end): where a
  list-item fence ENDS. A list item ends at the first non-blank line indented
  less than its content column, and that ends its fence; the ending line is
  then read as an ordinary top-level line (live, or the opener of a top-level
  fence). Arms, each checked against `gh api markdown` on the day it was
  written: (la) `- ```` closed at column 0: the column-0 line after it is
  quoted; (lb) a column-0 line inside is live, and the one after a later
  column-0 run is quoted; (lc) an unclosed list fence ends at the column-0
  line, which is live; (ld) a blank line inside keeps the fence open, and so
  (ld2) does a whitespace-only line below the content column; (le) an ordered
  item (content column 3) closed by a run indented 2 ends the item and opens a
  top-level fence; (lf) a tab-indented line inside keeps the fence open; (lg)
  a closing run indented content column + 3 closes it and the item's next line
  is live; (lh) one indented content column + 4 does not close it; (lr,
  regression) a top-level fence is not ended by an indented line. Failing
  direction that matters: a fence ended EARLIER than GitHub ends it reads a
  quoted marker as live. Mutations: drop the item-end rule (la, lb, lc, le,
  lh red); consume the ending line instead of handling it again (la, lb);
  let a blank line end the item (ld); a whitespace-only line (ld2); a tab
  line (lf); end it at an indent equal to the content column (every list
  arm); the closing bound becomes 3 instead of content column + 3 (lg). Not
  tested (A32b accepted limits): nested list prefixes, list items inside a
  blockquote, tab expansion beyond the tab rule
- Round 3 of PR #443 (A32d, finding ordered-start-unsafe-direction; replaces
  A32c's arms). The ordered-start rule is reverted, so the round-2 shape
  (`text` / `2. ```` / indent-3 run / marker, accepted limit
  ordered-item-after-paragraph, follow-up #446) is NOT pinned here: base reads
  it in the bad direction and pinning that would be tautological; #446 owns
  its acceptance test. Arms, each checked against `gh api markdown -f
  mode=gfm` on 2026-10-06 (the oracle): a marker inside the fence of `2. ````
  is quoted and the column-0 marker after it is live when the previous line is
  (d2) a wrapped item line, (d3) a lazy continuation line, (d4) a blockquote,
  (d5) an item holding a closed fence (also checked at marker level, d5b);
  (d6) `text` / `2. ```` / a column-0 marker / an indent-3 run / a late marker:
  the column-0 marker is live and the late one is quoted (the item ends at the
  column-0 line, the indent-3 run opens a top-level fence). Regression arms,
  green on arrival: (R-d3) after a blank line `2. ```` is an opener, (R-d4)
  after a list-item line it is an opener, (R-d5) the number 1 after a
  paragraph is an opener, (R-d6) a bullet after a paragraph is an opener. Red
  at 4bcc497: d2 (live_text and md_strip_fences), d3, d4, d5, d5b; green with
  the rule reverted (the `_MD_AWK` block identical to 5ea3a5b's). Mutations
  (scratch lib): re-introduce the ordered-start rule (d2-d5 red); the prevpara
  typo variant, the rule firing after a fence (d5, d5b red on top of d2-d4);
  the rule applied after any line (d2-d5, R-d3, R-d4 red); drop the item-end
  rule (la, lb, lc, le, lh, d6 red)

### S233 — CRLF and a lone CR are line endings: the CRLF body reads as the same body with LF, and a lone CR is a line break
**Covers:** F34
- Given: `lib/markdown.sh` under `LC_ALL=C`; a body with CRLF line endings
  around a fence and a marker, the same body with LF, a body with a lone CR
  between two markers, a fence made of lone-CR lines, mixed endings with a CR at
  the very end, a CR inside a marker value, a CRLF blockquote line
- When: `live_text` and `md_strip_fences` read each
- Then: the CRLF body gives exactly the LF body's output (the fence closes,
  the marker after it is live) and the output holds no CR byte; the lone CR
  between two markers gives two lines (never one glued line); the lone-CR
  fence is a fence; mixed endings give one line per ending; a CR inside a
  value splits the line (the later record reader names it a near-miss, never a
  silently cleaned value); a body without any CR is unchanged (regression
  arm). A31a: this replaces "remove every CR byte". Mutations: leave the CR
  in; delete CR bytes instead of splitting; read only CRLF and not a lone CR;
  strip CR after the fence logic instead of before

### S234 — review-rounds.sh prints no count when a read fails, and reads a marker after an invalid byte on its line the same under a UTF-8 LANG as under LC_ALL=C
**Covers:** F34, F42
- Given: `review-rounds.sh` (it takes `live_text` from `lib/markdown.sh` since
  #423; it was outside AC3) against a recording fake gh with three rounds (a
  Review marker, a done-only body, a Review marker) and a Planning marker
  after them; a PATH shim named `awk` that counts its calls and exits 2 for
  the call(s) selected; a second fixture where every body line starts with
  `x\377y ` (and the truncated `x\342\200y `), the bytes reaching the script
  through a placeholder swapped after jq
- When: the script runs once with every awk call passing (the baseline, which
  gives the number of awk calls), once with every call failing, once per call
  k failing alone; and with the byte-bearing bodies under `LC_ALL=C` and under
  `LC_ALL` unset with `LANG=en_US.UTF-8`
- Then: the baseline prints `review-rounds: 3` and the shim's count is above
  zero; with every call failing, and with call k failing alone for every k,
  the exit status is 0 (fail-open) and no `review-round` or `review-rounds:`
  line is printed (a body read as empty is never counted as "no round"); the
  byte-bearing bodies give the same lines under LANG as under `LC_ALL=C`
  (three rounds, `planning-after: 3`). Red today: the byte-bearing arm (the
  done-marker `grep` of `rr_rounds` runs in the ambient locale); the failure
  sweep is green on arrival and guards its mutation. Mutations: the
  `live_text ... || return 1` of `rr_rounds` removed (the sweep); the
  `marker_scan` failure return removed (the sweep); `LC_ALL=C` removed from the
  `tr '\001' '\n'` or from the done-marker `grep` (the byte arm). Not
  asserted: the wording of the warning

### S235 — the locale guard is structural: every script that reads GitHub text exports LC_ALL=C first, and every external text command in the two text-reading libs carries the LC_ALL=C prefix; the lint is itself mutation-checked
**Covers:** F34, F42
- Given: the four scripts `skills/pre-merge-review/model-record-gate.sh`,
  `compliance-evidence.sh`, `role-label-staleness.sh`, `review-rounds.sh` and
  the two libs `lib/markdown.sh`, `lib/model-record.sh`; the static lint in
  `test/fixtures/locale-lint.sh`
- When: the lint reads them (no network, no locale needed)
- Then: (L1) each script has `export LC_ALL=C` as its first statement after
  the shebang, comments, blank lines and `set` lines, and nowhere assigns
  LC_ALL to anything but C or unsets it; (L2) every command-position awk,
  grep, sed, tr, cut, sort and uniq in the two libs is directly preceded by
  `LC_ALL=C `, grep is always `grep -a`, unless the line carries
  `# locale-exempt: <reason>` (a non-empty reason; the allow-list is empty
  today); the number of sites checked is printed and must be above zero (and at
  least 10, the count after #424; it was 11 at head 5ea3a5b). (L3) the lint is red on a scratch copy
  with the export removed from each script in turn, with a non-C export, with
  an unset, and with one lib prefix removed (`normalize_model`'s first `sed` and `tr`, both `markdown.sh` awks, both
  parser awks); and on a synthetic tree and snippets, each of the seven
  commands bare in every command position (line start, after a pipe, `$(`,
  `"$(`, `;`, `&&`, `||`, a subshell, `then`, `if`, a backtick, another env
  assignment, a case arm) is a violation, while the same text prefixed, named
  only as an argument, in a string, in single quotes, in a comment, or exempt
  with a reason is not (an exemption with no reason is). The real-tree L3
  mutants need a green real baseline and are reported once as not run while
  L1/L2 are red. Red today: five L1/L2 violations (the four missing exports and
  `effort_rank`'s `tr`, a site that #424 deleted with the function, so the
  site floor is 10 now). Accepted limits of the lint: `${...}` skipped to its
  first `}`, a grep continued on a backslash line is not checked for `-a`,
  heredoc bodies read as code

### S236 — model-record-emit.sh no longer writes effort, and still accepts `--effort` for one release, ignoring it with one stderr line
**Covers:** F39, F40
- Given: `skills/pre-merge-review/model-record-emit.sh` (issue #424, V3 of the
  #411 redesign, AC1; A33 as amended by A33a), called by a stale prompt in an
  adopted project with `--effort <anything>` (`high`, `low`, `unknown`, an
  out-of-scale or empty value), before, between or after the other flags, and
  without it; macOS `/bin/bash` 3.2 under `LC_ALL=C` and a UTF-8 locale
- When: the wrapper runs
- Then: with `--effort`, stdout is exactly `<!-- model-record: stage=<S>
  model="<M>"[ floor-basis="<F>"] -->` with no effort attribute, the exit
  status is 0, and stderr is exactly one line, `effort is no longer recorded
  (#413); drop --effort from your prompt`; without `--effort` stderr is empty;
  a call refused for another reason (a bad stage) is still exit 2 with empty
  stdout whatever `--effort` says; the gate reads an emitted line next to a
  legacy-effort one without a finding; the usage text no longer advertises the
  flag (S238). Mutations the Developer's emitter must not survive (the QA
  kill table on the red commit): printing the effort, a different stderr text
  or two lines, exit 2 for the flag, a warning on every call. Review round 1
  of PR #447: `--effort` in every slot among `--stage`, `--model` and
  `--floor-basis` (six orders x four slots) leaves the Review line and its
  floor-basis intact, and does not excuse a floor-basis on Implementation or
  a Review without one (kills a mutant that resets the floor-basis on
  `--effort`)

### S237 — the gate and the collector judge the Review floor on the model alone: no effort finding, gate 2 is model-only, the conflict key is the model, gate 1 reads presence and model
**Covers:** F39, F40
- Given: one PR read by `model-record-gate.sh` (data-driven fake `gh`) and
  `compliance-evidence.sh` (recording fake `gh`), with legacy `effort`
  attributes in the markers (issue #424, AC2/AC3/AC6; this repo's own pipeline
  still emits `effort="unknown"`): the same model with efforts low (Review)
  and high (Implementation), also unknown, out of scale, missing, empty and
  unquoted; different models with a `floor-basis`; two closing issues whose
  Implementation or Review markers name the same model with different efforts,
  or different models; stage markers with an odd, empty or missing effort
- When: the gate and the collector run
- Then: AC2 the gate prints no line at all (so none that mentions effort) and
  collector gate 2 is `evidenced`, its evidence naming the model, saying the
  model strings are self-reported and the floor is on the model alone, quoting
  no effort; the lookup-failure guard (#302/#336) still gives `indeterminate`;
  AC3 different models are `unverifiable-from-artifacts`, naming both models
  and quoting the `floor-basis`, with or without effort attributes; AC6 two
  issues with the same model and different (or no) efforts are no conflict
  (`evidenced`), while different models are a conflict naming the models only,
  and gate 1 is `evidenced` whatever the effort attributes of the four stage
  markers say (presence and model only); the two model rows read exactly
  "Per-stage model recorded (Discovery, Planning, Test, Implementation)" and
  "Review at least as capable as Implementation (same model: the floor is met
  on the model alone; different models: recorded judgment, not
  machine-checked)"

### S238 — no text tells anyone to pass --effort or ask the human about an unknown effort; the same-model-lower-effort limit and its revisit trigger are stated; the flag's removal is a debt row
**Covers:** F39, F40
- Given: the skills, `ORCHESTRATOR.md`, `README.md` and `WORKFLOW-ADOPTION.md`,
  `model-choice`, the emitter's usage text, and `PRD.md`'s Technical debt
  register (issue #424, AC5/AC7 and the item's documentation list; history and
  decision documents are excluded from the scan)
- When: they are read, paragraph by paragraph
- Then: AC5 no paragraph tells anyone to pass `--effort`, to fill it with
  `unknown`, to ask the human about an effort or to find out the effort a role
  runs at, unless it says the flag is gone (no longer, removed, retired,
  legacy, ignored, #413); the two sentences of `ORCHESTRATOR.md` that did are
  deleted; `pre-merge-review`, `model-choice`, `role-contracts` and
  `ORCHESTRATOR.md` still name `model-record-emit.sh` and none shows
  `--effort`; the emitter's usage line and no-argument message do not advertise
  it; the README no longer says the skill picks a "model/reasoning effort";
  AC7 `model-choice` says the same model at a lower effort meets the floor
  because effort is neither chosen nor checked (an accepted risk, A33a), with
  the revisit trigger "when the dispatch tool gains an effort parameter", that
  the floor rests on self-reported model strings, and shows no effort attribute
  or scale; PRD.md's Technical debt register has a row that the next release
  removes `--effort` from `model-record-emit.sh` (#413 or #424) and no longer
  carries the rows on the same-model effort check or on a self-reported
  effort

### S239 — process-model-choice moves to meaning v2 and quality-review-before-merge to v4, each once; process-multi-agent-roles does not move; this repo's own rows re-confirm; adopters answered under the old version are re-surfaced
**Covers:** F9, F26, F39
- Given: `CHANGES.md`, this repo's `WORKFLOW-ADOPTION.md`, and fixture projects
  run through `pending-changes.sh` (issue #424, AC4; A33a, the adoption-registry
  rule of #254 that a removed obligation is material)
- When: the entries and rows are read, and `pending-changes.sh <project>` runs
- Then: `quality-review-before-merge` is at Meaning version 4 (its text is
  S191), `process-model-choice` at 2 and `process-multi-agent-roles` still at
  1 (its v2 belongs to the guard slice); the `process-model-choice` entry cites
  #424 and #413, says in its Meaning version note that effort is no longer
  recorded, and its "Yes means" says the floor is judged on the model and
  effort is neither chosen nor checked, that the same model at a lower effort
  meets the floor (an accepted risk), carries the revisit trigger "when the
  dispatch tool gains an effort parameter", no longer asks for a "model/effort"
  per stage, still says every stage records which model was used, keeps its
  unchanged parts and its gate in Reaches session; this repo's own
  `process-model-choice` row ends with `(meaning v2)` citing #424 and the
  `quality-review-before-merge` row with `(meaning v4)`; a project that
  answered `process-model-choice` at v1 (no marker, or `(meaning v1)`) is
  reported in the "meaning has changed" block as "answered under meaning v1,
  now v2", not in the never-answered list, and a `(meaning v2)` row is quiet

### S240 — the live design and spec text and the orchestrator's text state no effort rule as current behaviour, and the Pipeline log keeps its after-the-fact effort note
**Covers:** F39, F40
- Given: `ARCHITECTURE.md` sections A24 and A26, `PRD.md` sections F39 and F40,
  and `skills/role-contracts/ORCHESTRATOR.md` (issue #424, review round 1 of
  PR #447: findings `pr447-live-docs-still-state-effort-rules` and
  `pr447-pipeline-log-observed-effort-dropped`; A27, A33, A33a). A25, A27, A33,
  the debt register, `CHANGES*.md`, `wip/` and `test/` are out of scope
- When: each document is cut into units (a list item with its continuation
  lines and nested items, or a paragraph) and read
- Then: a unit that states an effort rule (it compares, passes, checks, sets,
  chooses or ranks an effort, or names an effort field or `--effort`) carries a
  supersession mark (superseded, amended, A33, #424, no longer, history,
  legacy, retired, removed, ignored, accepted risk, neither chosen nor, #413 or
  S238's other allow words), a nested item inheriting its parent's mark; a bare
  attribute name such as `effort=` in a code span and a passing word (the
  dispatch tool has no effort argument) are not rules; deleting, rewording in
  the past tense with a pointer to A33, or marking amended all pass; and the
  `Pipeline log.` paragraph of `ORCHESTRATOR.md` still has one sentence saying
  the orchestrator may note the effort the platform transcript shows, in
  prose, after the fact, which is not a marker attribute, flag or check, while
  A27 still lists the observed effort (the two documents agree). Red today:
  five A24/A26 items, seven F39/F40 units and the dropped Pipeline log
  sentence

### S241 — lib/ no longer mentions effort in any form, and no comment carries a doubled semicolon
**Covers:** F39, F40
- Given: every `lib/*.sh` (issue #424, review round 1 of PR #447, finding
  `pr447-lib-comment-typo-and-effort-word`; QA round 1 Developer note 2)
- When: they are read as text
- Then: none contains the word effort in any case (a comment included), and no
  pure comment line contains `;;` (a case arm's own `;;` is code and is not
  looked at). Red today: the `marker_emit` header comment in `lib/model-record.sh` (one effort word, one `;;`)

### S242 — rec_scan reads a well-formed whole line as one ok row with its exact fields, under three locale environments (R1)
**Covers:** F40
- Given: the sourced `lib/model-record.sh` (issue #425, slice V4 of #411, AC1/AC6;
  A31, A31a, A32a): a matrix of strict record lines built from named parts (every
  stage with and without a floor-basis; a model with spaces; legacy `effort` and
  `same-model-exception` attributes in either order; trailing blanks, tabs as
  separators, no blank after `<!--` or before `-->`; valid UTF-8, NEL/LS/PS,
  invalid and truncated UTF-8 and a lone continuation byte, shell and printf
  metacharacters, a value ending in ` model=`, an empty and a 600-byte
  floor-basis; the `pipeline-override` kind), each alone and inside a body of
  prose; the three locale environments C (`LC_ALL=C`), UTF8 (both set) and LANG
  (`LC_ALL` unset, `LANG` UTF-8: how production runs a sourced lib)
- When: `rec_scan <kind> <body>` reads the body and `rec_field <line> <name>`
  reads the returned line
- Then: exactly one row, `<index 1> TAB ok TAB <stage> TAB <the line verbatim>`
  (an override's stage is `?`); `rec_field` returns `model` and every attribute
  that was built in, byte for byte, and nothing for an absent attribute; a
  `model-record` line is no row for kind `pipeline-override` and the reverse;
  a body with no candidate, and the empty body, give status 0 and no rows.
  Threat model: accidental defects (a regex typo, a bash 3.2 `[[ =~ ]]` quirk, a
  locale that leaks into a child process, a value byte left out); no forger.
  Red today: the three functions are stubs that return 99, so every case fails
  on an assertion about rec_scan's status or rows. Kill table on the red
  commit: forbid bytes 0x80-0xFF in a value, drop the trailing-blank allowance,
  cut a value at `--`, `=`, a backtick or `$`, read a blank model, a sixth stage

### S243 — each #405 defect class is a near-miss and never hides a later or earlier record; the same through a bundle (R2)
**Covers:** F40
- Given: a hostile line (`>` or `<` in a value, an odd quote, an open quote, `-->`
  or `<!--` inside a value, a whole record nested in a value, invalid, truncated
  and valid multibyte text right after `stage=`, a quoted stage, an unquoted,
  empty, blank or missing model, a record split over two lines, an inline
  record, text after the closing arrow, no closing arrow, two records on one
  line, a tab, a C0 byte, DEL, a lone CR, CRLF and a newline inside a value, an
  upper-case or bare attribute, NBSP after the colon) with one valid record
  after it, before it, and on both sides, in one body; the same cases as one
  bundle; an open quote at the end of body 1 and records in bodies 2 and 3;
  U+001E inside a value (`rec_scan` only: the bundle removes the byte first);
  three locale environments including `LC_ALL` unset with `LANG` UTF-8 (AC2)
- When: `rec_scan` and `rec_scan_bundle` read them
- Then: the hostile line is exactly one `near-miss` row (stage field the bare
  `stage=` token when it is a valid stage name), every valid record is an `ok`
  row holding its line verbatim and readable with `rec_field`, the row count
  is the candidate count (a hostile line neither consumes its neighbour nor
  yields a second row), and the bundle gives the same classes per body index.
  Threat model: accidental defects of the #397/#405 rounds 1 to 4 and #402,
  plus the shapes a careless author produces by typing a marker; a typed strict
  line is byte-identical to emitter output and no artifact can show otherwise
  (stated limit). Red today: stubs. Kill table: allow `>` or `<` in a value,
  make the reader multi-line (a split record reads ok, an open quote runs on),
  let the near-miss branch swallow the next line, read an inline record or an
  unquoted model or a quoted stage as ok, abort on a multibyte byte

### S244 — quoted text is never a record: a record in a fence, code span, blockquote or indented block is `quoted`; not on a line of its own is a near-miss; a non-candidate prints nothing (R3)
**Covers:** F40
- Given: bodies with a record in backtick and tilde fences (longer closer, info
  string, three-space indent, a shorter inner run, a different closing character,
  a closer with an info string, unclosed, closed, list-item fences, a backtick
  info string, a four-space indented fence line, CRLF endings), in a code span, a
  blockquote, indented four spaces or a tab, with one to three leading spaces,
  inline, in a table or list-item line, and non-candidates (NBSP or a zero-width
  space after `<!--`, `model-record-gate`, no colon, a finding marker, bare
  prose); the same for `pipeline-override`; and every record shape wrapped in a
  fence one backtick longer than its longest run and in a tilde fence (AC1)
- When: `rec_scan` reads them under the three locale environments
- Then: the class sequence is the one the labelled oracle gives: fence shapes
  were labelled once against GitHub's renderer on 2026-10-06 (`gh api markdown`)
  and the comment above each says so; blockquote, indentation and the not-on-
  its-own-line near-miss are A31a policy and are labelled as policy; every
  wrapped row is `quoted`; an unclosed fence runs to the end of its body (a
  later record is `quoted`); a fence whose info string holds a backtick is
  not an opener; non-candidates give no row; an ok row always holds a line of
  the body verbatim. Threat model: accidental quoting defects (#308, #400, #405
  round 4); a strict line typed at column 0 outside any quoting is not stopped.
  Red today: stubs. Kill table: drop the fence strip, read a fenced or spanned
  record, treat 1-3 leading spaces as column 0, accept a four-space indent,
  treat a backtick-info line as an opener, close on a closer with an info
  string, close ``` on a `~~~` line

### S245 — rec_scan_bundle resets fence state per body and keeps body order and indices; every row has four non-empty fields; same-stage records, CRLF, a lone CR and an override with `>` read as the issue says (R4 + AC6)
**Covers:** F40
- Given: bundles of bodies joined by U+001E (U+001E removed from each body first)
  with an unclosed fence in body 2 and in the last body, empty and record-less
  bodies, two records of one stage in one body and in two bodies, CRLF and lone
  CR line endings (also around a fence and across a bundle), a `pipeline-override`
  whose `reason` holds `>`, a record-less line, a line with a tab and a 3000-
  byte hostile line
- When: `rec_scan_bundle` and `rec_scan` read them
- Then: a record after an unclosed fence is `quoted` and the fence does not
  leak into the next body (body 3 is ok); indices count from 1 and an empty or
  record-less body keeps its number; `rec_scan` of body i equals its bundle rows
  with index 1; both same-stage records are rows in body order and the last ok row of the
  stage is the later record with the later fields; CRLF and a lone CR are line
  ends, the line field never holds a CR; the override with `>` is a near-miss and a
  valid one is ok, both with stage `?`; every row is four tab-separated
  fields, none empty (`?` for an unknown stage), a near-miss or quoted row
  holds at most 400 bytes however long the line was. The design left the
  body-index base open: this test pins 1. Threat model: accidental state leaks
  and CR handling. Red today: stubs. Kill table: scan the concatenated bodies,
  drop the per-separator reset, renumber bodies, strip CR instead of splitting
  on it, drop the earlier same-stage record, print an empty stage, dump a 3000-
  byte line

### S246 — rec_field reads attributes by a left-to-right walk: first occurrence wins, a value ending in ` name=` is never an attribute, a name that merely ends in another is not that attribute (R5)
**Covers:** F40
- Given: strict lines such as `model="x" effort="see floor-basis=" floor-basis="the
  real one"` (AC3), a floor-basis ending in ` model=` or ` effort=`, a chain
  of values each ending in the next name, a model ending in ` floor-basis=`,
  `reviewer-model`, `peak-effort`, `same-model`, `max-effort`, `xmodel`,
  `old-floor-basis`, duplicate names, empty values, `=` and shell
  metacharacters in values, invalid and truncated UTF-8, tabs between attributes,
  an override reason ending in ` scope=`; and 120 deterministic generated lines
  (a linear congruential generator, seed 425, no `$RANDOM`) whose values end in
  other attribute names; the hijack arms of S188 move here
- When: `rec_field <line> <name>` reads each attribute under the three locale
  environments
- Then: the literal case gives `the real one`; every attribute gives exactly its own
  first value (expected from the construction, never from the reader); an
  absent, prefix, suffix, upper-case, regex-looking or empty name prints
  nothing; a value is data and is never evaluated. Threat model: accidental, plus a
  typed or legacy line whose value ends in an attribute name. Red today: stubs.
  Kill table: a first-match search over the whole line, an unanchored name match,
  the last occurrence instead of the first, a name read as a regex

### S247 — a reader failure is never "no record": a failing external tool gives a non-zero status with empty stdout; grep's exit 1 is not a failure; the failure shim must have run (R6)
**Covers:** F40
- Given: PATH shims (counting their own calls) for grep, awk, sed, tr, cut, wc,
  head, tail, sort and uniq, in modes pass-through, always fail (exit 2), fail
  from the Nth call (N = 1 to 4) and, for grep only, no-hit (exit 1); a body and
  a five-body bundle with records; a body without a record
- When: `rec_scan` and `rec_scan_bundle` run with the shim first on the PATH
  (and `rec_field` with every shim failing)
- Then: with pass-through shims the reader still reads the record and the grep
  and awk shims were called (a vacuous scenario is red); when grep or awk
  exits 2 the status is non-zero, stdout is empty and stderr says why; grep
  exit 1 on a record-less body is status 0, no rows, nothing on stderr; for every
  tool, whenever the shim actually failed the whole read failed with empty
  stdout (no rows of earlier bodies leak out of a failed bundle), and a tool
  that never failed leaves a clean read; `rec_field` never returns status 0
  with a wrong or empty value when a tool fails. A `[[ =~ ]]` result of 2 cannot
  be injected from outside: a stated limit. Threat model: accidental (a dropped
  `|| return`, a pipeline status from the last command, grep 2 read as no
  match); no forger. Red today: stubs. Kill table: drop a `|| return`, treat
  grep 2 as 1, treat grep 1 as a failure, print rows before returning the
  failure, a reader that never calls grep

### S248 — the frozen corpus: every row of test/fixtures/marker-corpus.jsonl gets its labelled class and fields from rec_scan, alone and wrapped in a fence; the counts match the fixture header; the fixture is self-consistent and clean (K1)
**Covers:** F40
- Given: `test/fixtures/marker-corpus.jsonl` (issue #425, AC1; A35a K1): a header
  (the oracle commit 411699d, the snapshot date, the counts, the Phase 1a
  floor, the intended-shifts list, the stated limits) and one JSON object per
  row: 1290 corpus rows (every line of this public repo's issue and PR bodies,
  comments and review bodies, 2026-10-06, that contains `model-record` or
  `pipeline-override`; one line withheld for a personal name) and 74 synthetic
  rows counted separately (one near-miss per A31a reason, `<` and `>` alone,
  `--` alone, a CR in a value, NBSP and zero-width after `<!--`, `<!--
  model-record-gate: x -->`, a value ending in ` floor-basis=`, invalid UTF-8);
  each row has an expected class (ok, near-miss, quoted, text), the stage and
  fields of an ok row, an oracle note, `v030` (what the v0.3.0 pipeline made of
  the line alone) and a label-reason; the oracle for ok `model-record` rows is
  the v0.3.0 parser (`marker_scan`, `marker_find`, `marker_attr` at 411699d), run
  once and never regenerated from the new code; every other row is hand-labelled
- When: the header and rows are checked, then `rec_scan_bundle` (one body per
  row), `rec_scan` (every eighth corpus row and every synthetic row) and
  `rec_field` read them, alone and with each line wrapped in a fence one
  backtick longer than its longest backtick run
- Then: the header counts equal the rows (corpus, synthetic, all, per class),
  are at least the Phase 1a floor (965 lines, 396 ok), the oracle commit is
  recorded, no ok model-record row's oracle disagrees, the intended-shifts list
  equals the set of rows whose v0.3.0 class differs from their v2 class, and
  the fixture holds no name the repo forbids (SHA-256 of the owner's first
  name, as S159), no secret shape, no email address (gitleaks too when it is
  installed); every row gets exactly its labelled class (a text row gives no
  row), every ok row its stage, its line and every labelled attribute through
  `rec_field` (and nothing for an absent one), every wrapped candidate row is
  `quoted`, and the reader's aggregate counts equal the header. Threat model:
  accidental regressions of a grammar change against everything this repo has
  written; a regression scenario in its fixture part (green on arrival), red on
  the stubs in its reader part. Kill table: any grammar change that shifts a
  class, a wrong model or floor-basis out of `rec_field` for a legacy model
  with spaces, a mislabelled indented or inline row

### S249 — the property arm: every hostile byte or token at every position of a record, every byte class, a seeded generator with a fence oracle, and a scale case; every inserted record reads back exactly and nothing else is read (K2)
**Covers:** F40
- Given: a valid Review record with each of about 95 tokens inserted at 12
  positions (the start, middle and end of the model, the floor-basis and a
  legacy effort value; before and after the stage name; inside an attribute
  name; between attributes; after the closing arrow): every C0 byte, DEL, `"`
  `<` `>` `-->` `<!--`, tab, LF, CR, CRLF, `'` `\` backtick `$` `*` `?` `[` `%`
  `=`, a value ending in ` name=`, a leading dash, NEL, LS, PS, NBSP, BOM,
  zero-width, bidirectional controls, U+FFFD, an emoji, invalid, truncated,
  overlong and surrogate UTF-8; every single byte 0x01 to 0xFF as a
  floor-basis character; 150 generated bodies (a linear congruential
  generator, seed 425, no `$RANDOM`) of valid records, hostile lines, noise
  full of delimiters and fence lines, with a fence-state oracle; 60 bodies with
  a 100 KB value and a 100 KB hostile line; `LC_ALL=C` and `LC_ALL` unset with
  `LANG` UTF-8
- When: `rec_scan_bundle`, `rec_scan` and `rec_field` read them, each
  injected record with a valid sentinel record before and after it
- Then: the expectation comes from a two-flag table of the grammar (value byte?
  blank? ends the line?), never from the reader: a hostile token is exactly one
  near-miss, a value byte is exactly one ok row holding the line verbatim
  whose attributes read back, and the sentinel is always ok verbatim; every
  byte but `"`, `<`, `>`, a C0 control and DEL is an ok floor-basis character;
  the generated bodies' rows are exactly the oracle's (valid records outside
  fences ok and in order, hostile lines near-miss, everything inside a fence
  quoted, noise nothing); the 100 KB value reads back whole, the 100 KB
  hostile line is a near-miss row of at most 400 bytes, the time is reported
  and not failed. Threat model: accidental defects and the deliberate
  injection shapes of #405 rounds 1 to 4; not a forger of a strict line (stated
  limit); NUL cannot be carried in a bash argument (stated limit); the framing
  layers of the gate (U+001E) and the collector (`\001`) get their own arm when
  those callers move (V6 to V8). Red today: stubs. Kill table: drop one
  injection arm (`<`, a control byte, DEL), forbid bytes 0x80 to 0xFF, let a
  record run over a newline, abort on invalid UTF-8 under `LANG` (no
  per-command `LC_ALL=C`), fail on a `~~~` or a longer closing fence, print the
  whole 100 KB line
