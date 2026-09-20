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
- Given: a project where a row with `production-gate: yes` still says
  "requires substantiation"
- When: `deploy` to production is called
- Then: the deploy stops with a message naming the row in question
- And: the same deploy to pre-production does go through

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
**Covers:** F9
- Given: a PR and the issue(s) it closes, each carrying zero or more
  `<!-- model-record: stage=... -->` markers across their comments
- When: `model-record-gate.sh <pr-number>` runs
- Then: a missing stage among Discovery/Planning/Test/Implementation/Review
  is reported, one line per stage; nothing is reported once all five are
  present; without `gh` the gate fails open with a warning, not a block
- And (#244 AC2): Review and Implementation recording the identical model
  with no `same-model-exception` field on Review's marker is reported;
  the identical pairing with that field present is not

### S131 — A review finding surfaces if it silently vanishes between fresh-context rounds
**Covers:** F9
- Given: a PR's previous `pre-merge-review:done` comment left a finding
  marked `<!-- finding:<slug> status=open -->`
- When: `finding-carryforward-gate.sh <pr-number>` runs after a new
  `pre-merge-review:done` comment is posted
- Then: the slug is reported if it's missing from the new comment, and
  not reported if the new comment re-flags it as still open or marks it
  `status=resolved`; with only one review round so far, or without `gh`,
  nothing is reported

### S132 — The 4th traceability link: an issue's own AC/Covers/work-item structure
**Covers:** F9
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
**Covers:** F9
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

### S144 — hooks/pre-commit runs ./check, blocking on a real failure
**Covers:** F17
- Given: an adopted project with an executable `check` at its root
- When: a commit is attempted (not on `main`)
- Then: a green `./check` doesn't block; a red `./check` blocks the
  commit and shows `./check`'s own output; no executable `check` at all
  fails open, with a loud warning that the commit-time check was
  skipped; the existing `CLAUDE_WORKFLOW_GUARDRAILS_OFF` escape hatch
  also covers this guard, not only the branch guard
