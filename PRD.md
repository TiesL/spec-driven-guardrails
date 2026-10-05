# PRD — claude-workflow, release "From prose to mechanism"

**Status:** As-built for epic #11 (closed, shipped 2026-09-06) and epic #52
(closed, shipped 2026-09-13) — see `CHANGELOG.md` for both, including the
W29 (#53) design-session decisions that steered epic #52.

---

## Context

`spec-driven-guardrails` (formerly `claude-workflow`, renamed in W32/#56 —
full reasoning in `CHANGELOG.md`, "Decided in W29 (#53)", decision 1) is the
shared source of truth for TiesL's personal Git/GitHub workflow, adopted by
four projects via local symlinks.

This document is the integrated plan for epic #11, which merged three
earlier, separately created epics after the quality review on PR #6 exposed
structural problems and a traceability gap — see `CHANGELOG.md` for the full
history and the ordering decisions that followed from it.

**The common thread**: this repo prescribes conventions it doesn't check itself.
The NFR list lives in two places and is kept in sync by hand. The predicate
logic exists twice, the predicate list even three times. "Never directly to
`main`" is an agreement with no lock. The substantiation requirement is prose
that no script can see. The traceability fields are free text nobody reads.

The measurable consequence, across four projects and 27 merged PRs: **zero**
PRs reference an issue, **zero** have a review, **zero** scenarios have a
coverage field, and `quality-review-before-merge` has never been answered by
any project. The conventions exist; compliance is nil.

This release moves those conventions from prose to mechanism.

---

## Architecture

Four layers, from hard to soft enforceability. **Where enforcement is possible, no prose.**

| Layer | Mechanism | Enforces? | What's there |
|---|---|---|---|
| 1 | **Hooks** (`settings/session-hooks.json`) | Yes, hard | Git guardrails (`PreToolUse`), merge guard, fetch/push, outstanding-changes notice |
| 2 | **Scripts + `check`** | Yes, in CI | Predicates, NFR consistency, traceability, regression tests |
| 3 | **Skills** (`skills/<name>/SKILL.md`) | No — loads on demand | Deploy, adoption protocol, review, TDD, bug diagnosis |
| 4 | **Prose** (`WORKFLOW.md` → `CLAUDE.md`) | No | Only what every session needs |

### Correction to the assumption in #9

#9 states: *"Prose policy erodes; an invoked skill doesn't."* That's half true,
and the distinction determines what this release can promise.

Verified in the documentation: **a hook cannot invoke a skill.** It can
reference one via `systemMessage`, but Claude may ignore that. Skills provide
**locality and lower token cost** — the text loads fresh at the moment it
matters — but **no enforcement**. The enforcement gain comes from layers 1 and 2.

### Two hard constraints

**Bash 3.2.** macOS ships `/bin/bash` 3.2.57, and hooks run non-interactively with
a minimal `PATH`. No `declare -A`, no `mapfile`, no `${var,,}`. Set
comparisons therefore go via sorted tempfiles and `diff`/`comm`, not
associative arrays.

**`settings/session-hooks.json` must not move.** The SessionStart hook
locates this repo via `dirname(dirname(readlink .claude/settings.json))`. Moving
that path silently breaks every adopted project — those symlinks are local,
untracked, and the chain ends in `|| true`.

From that follows a design rule that touches the whole release: **what's
symlinked is live in all four projects immediately after a `git pull`; what
`adopt.sh` installs is not.** So every change to `session-hooks.json` must be
safe in a project that hasn't re-run `adopt.sh` yet.

---

## Data source(s)

N/A, substantiated. This repo has no data layer; its "sources" are tracked
markdown files (`CHANGES.md`, soon `nfr/*.md`) parsed by bash scripts. Their
parseability is a functional requirement (F3), not a data source in the
sense this template means.

---

## Functionality

### F1 — Test harness and its own `check`

Pure bash, no framework. `./check` runs `bash -n` over all scripts,
validates `settings/session-hooks.json` as JSON (`jq empty`, otherwise
`python3 -m json.tool` — the file is symlinked, so a single typo is
instantly broken in four projects and `bash -n` won't see it), runs `shellcheck`
if present (warn, not require), then `test/run.sh`. Every test runs in a
`mktemp -d` sandbox with injected `HOME` and `CLAUDE_WORKFLOW_DIR`, with a
hard refusal to run if `HOME` is still the real home after sandbox setup.

Makes R1–R9 and T1–T5 executable instead of prose checkboxes in a PR body.
Also delivers the `check` command this repo itself prescribes but doesn't have.

As of issue #216/PR #217, `test/run.sh` runs its cases concurrently
(`xargs -P`, default `min(cores, 4)`, override via `TEST_JOBS`) instead of
one at a time — each case already ran in its own fully isolated sandbox, so
the only thing forcing serial execution had been the runner's own
bookkeeping (a single, reused HOME-leak sentinel, now one per test). Cuts
this repo's own CI wall-clock time roughly in half to two-thirds, depending
on the runner's core count.

**Do not add a `package.json`** just to reuse `templates/ci.yml`'s npm
steps — nothing here needs them. CI calls `./check` directly (#248: the
CI-adoption predicates key on that executable, not on `package.json`) —
exactly the "different stack" case the `check-convention` skill already
describes.

As of issue #377, `test/lib.sh` also clears git's repo-local variables
(`git rev-parse --local-env-vars` plus a fixed floor, from `lib/git-env.sh`)
when it is sourced, and `sandbox_guard` refuses if one is set again. A
hook, `git rebase --exec` or git alias exports them (`GIT_DIR`,
`GIT_INDEX_FILE`, ...), and without this a fixture `git -C <fixture> ...`
acted on the repo the suite was launched from (S165, S168).

### F2 — Recorded baseline as fixtures

The current outcome for all **four** adopters, frozen in
`test/fixtures/baseline/` as golden sets, before anything changes.

A manual dry run against copies isn't repeatable; freezing it as a fixture
makes R9 a permanent regression test. All four sources live locally —
`tennis-registration` and `tennis-invoicing` as full-fledged git repos (own
`.git`, own remote, own `WORKFLOW-ADOPTIE.md`) nested inside `tennis-admin/`.

`a2t-emails` is the fourth and has **no** `WORKFLOW-ADOPTIE.md` at all. Its
baseline is therefore "everything outstanding" — record it as found, don't fix
it first, or the fixture would capture the fix instead of the actual state.

**W28:** the question set has come from two sources since W5, `CHANGES.md` and
`nfr/`, and until W28 only the first was frozen (`CHANGES.md.snapshot`).
`nfr.snapshot/` (a verbatim copy of `nfr/`, a single `cp -r`) closes that
gap — see `test/fixtures/baseline/LEESMIJ.md`.

### F3 — Shared parser and predicates (`lib/changes.sh`)

It's not just the predicates that are duplicated — the entire `CHANGES.md`
parser is too (`## ` headings, `${line##*\*\* }`, the `case` skeletons). Both move.

```
predicate_true <predicate> <project_dir>   # the sole predicate logic
iterate_entries <source> <callback>        # callback <id> <default> <predicate>
```

The **deliberate asymmetry** (`adopt.sh` skips `Standaard: vraag`,
`pending-changes.sh` ignores `Standaard`) lives in the caller's callback, with a
comment on both sides pointing to the other. Better than a `--negeer-standaard`
flag, which would hide the difference inside the library and make it look
like an accident.

The prose list in `CHANGES.md` now refers to the library instead of listing
the predicates a third time.

### F4 — One source of truth for the NFRs: an `nfr/` registry

The NFRs currently live in **two canonical places** in this repo: as
`spec-*` entries in `CHANGES.md` (the adoption question) and as `###`
subsections in `templates/PRD.md` (the fill-in guidance). Neither is logically
the owner; they're two consumers of the same fifteen concepts. The right fix
is therefore not "link A to B," but **abstract into C and let A and B point
to it**.

```
nfr/spec-security.md
nfr/spec-data-integrity.md
…  (fifteen files)
```

Each file carries everything known about that one NFR:

```markdown
---
id: spec-security
heading: Security
default: yes
applies-if: always
production-gate: yes
status: active
---

## Question
Is Security relevant enough for this project to specify (access,
authorization, secrets)?

## Yes means
`PRD.md` answers the "Security" subsection — who is allowed to do what, what
permissions are minimally needed, where secrets live.

## Guidance
Who is allowed to do what? What permissions are minimally needed? Where do
secrets live, and how do they stay out of git?
```

What this eliminates:

- **The naming problem gets solved instead of managed.** `id` and `heading`
  live in the same file, so `spec-compliance` ↔ "Compliance and
  auditability" needs no normalization, no stopword rule, no alias table.
- **`CHANGES.md` shrinks from 27 to 12 entries.** The scripts iterate
  `CHANGES.md` and `nfr/*.md`. That serves the growing reading burden more
  directly than the archive alone: fifteen of the twenty-seven entries leave
  the file every project walks through every session.
- **Retirement becomes a field** (`status: retired`) instead of a file
  move, for these fifteen.

The `production-gate` field carries F6's second gate: which NFRs must be
substantiated before the first production rollout is now a recorded decision
instead of a list in a script.

**`templates/PRD.md` is generated** — only the NFR block, from `heading` +
`Guidance`, with the `id` as an HTML comment inside it. `check` fails if the
checked-in block doesn't match what the generator produces. The PRD becoming
a build artifact is the price; it's worth it because the generator also
plants the anchor F11 leans on.

**Only the fifteen NFRs move.** The remaining twelve entries (`proces-*`,
`test-*`, `ci-convention`, `deploy-guards`) have no second consumer and
therefore no duplication problem.

### F5 — Retirement with an archive (`CHANGES-ARCHIEF.md`)

For the twelve entries that stay in `CHANGES.md`. Retired entries move with
their ID and reason, so a project that once answered the entry can still
find it via `grep` across both files.

At the same time, **disambiguate the section separators**:
`## Proces en ontwerpdiepte` and `## Niet-functionele kenmerken (NFR's)`
become `###` or bold. Right now a section separator is indistinguishable
from a retired entry to the parser. After this, `## ` in `CHANGES.md`
unconditionally means "entry," and the shared parser can warn on an entry
without a `Van toepassing als`.

Both existing retirement forms get named explicitly:
remove-if-never-answered versus freeze-if-already-answered.

### F6 — The substantiation requirement becomes visible — without breaking R9

`beantwoord()` in `pending-changes.sh` currently only checks *whether a row
exists*, never what's in it. So a freshly adopted project reports nothing
outstanding while all seventeen seeded rows still carry "requires
substantiation."

**Don't change `beantwoord()`.** That would change the outstanding set and
thereby break R9 — the release's most important regression test. Instead, a
**second, separate notice**:

```
17 row(s) in WORKFLOW-ADOPTION.md are still waiting on substantiation.
Replace the provisional stamp with a reasoning grounded in this project,
or change the row to 'no' with a reason — while you're already on the topic.
```

Counted by grepping the answer file, not by changing what "answered" means.
R9-neutral by construction.

Also included here: the **outdated-adoption notice**. If the project is
missing skills that do exist in `$CLAUDE_WORKFLOW_DIR/skills`, the hook
reports that `adopt.sh` needs to run again. Without that, this release ships
and three of the four projects silently keep the old world.

**Decided: substantiate in phases, secured by three gates.** Clearing
seventeen rows at once is unrealistic homework; the signal alone would then
become chronic noise. So substantiate on first contact, with a deadline for
each row:

1. **Per PR** — if a PR touches a topic whose row still says "requires
   substantiation," that's a review finding in `pre-merge-review`, and the row
   gets answered before the merge (F11).
2. **Before the first production deploy** — the deploy guards require that no
   row with `production-gate: yes` still says "requires substantiation" (F4).
3. **Every session** — the signal above stays; phased doesn't mean invisible.

Touched → answered on that PR; never touched but critical → by the first
production rollout at the latest; the rest → visible until you get to it.

### F7 — Git guardrails as a `PreToolUse` hook

Blocks `reset --hard`, `clean -f[d]`, `branch -D`, `checkout .`/`restore .`,
`commit` **on `main`**, and `push` **to `main`**.

**Blocking `commit` on `main` is a deliberate extension**, added at TiesL's
request after it turned out that blocking only the push creates a bad moment:
you work through an entire session, commit everything on `main`, and only hit
the wall at the end. Worse — the `SessionEnd` hook skips its push on `main`,
so that work never reaches the remote at all, whereas before this guard you
could still have pushed it manually. The block moves that moment earlier;
F18 addresses the flip side of it.

The message must therefore name the way out (`git checkout -b`) and that the
changes come along. Without that, the work stays *uncommitted*, which is less
safe than the local commit it just blocked. Exception: a repo with no
commits — a new project's very first commit is on `main` by definition.

That last case is **two-fold**: explicit refspecs that touch `main`
(`git push origin main`, `git push origin HEAD:main` — from whichever branch)
and the state-dependent bare push (`git push origin HEAD` while `main` is
checked out, so `git rev-parse --abbrev-ref HEAD` needs consulting). Keying
only on the current branch misses the first category. `mattpocock`'s version
blocks *all* `git push` — adopting that here would break the mandatory
feature-branch pushes and the existing `SessionEnd` hook.

What this hook by definition *cannot* see is anything outside the agentic
loop: a command TiesL types himself in his terminal never passes through it.
That gap isn't an implementation detail but a property of `PreToolUse`, and
it's addressed separately in F17.

JSON parsing: `jq` if present (ships in `/usr/bin` on macOS 26), otherwise
`python3`; if both are missing, warn loudly and allow.

**No `sed` fallback.** An earlier version named that as a third layer. On
reflection, that's more harmful than useful: a `sed` approach to JSON
misreads strings with escapes, and a guard that misreads the command can
either block something harmless or let something destructive through —
exactly the two outcomes it's supposed to prevent. Being unable to read
anything and saying so loudly is more honest than a guess.

The hook rule must be `if [ -x … ]; then exec …; fi; exit 0`, **not**
`[ -x … ] && … || exit 0` — that second form swallows exit code 2 and
silently disables the guard while it appears to be installed.

### F8 — Merge guard: no merge without review evidence and green CI

Same `PreToolUse` mechanism, second case: `gh pr merge` gets blocked if the
PR carries no machine-recognizable review marker (see F11). The merge is the
workflow's real choke point, and the baseline (0 reviews on 27 PRs) proves
that a requirement with no lock doesn't work there — warning instead of
blocking would repeat that failure pattern.

**Extended with a CI check (issue #81).** Six CI runs in a row failed
unnoticed after PR #76 — PR #76, #78, and (initially) #80 were all merged
red, because nothing in the merge flow looked at it: this repo has no branch
protection (private, no paid plan) and `gh pr merge` doesn't itself warn on
failing checks. The same gate that checks the review marker now also checks
`gh pr checks` on the PR: any check that isn't `pass` or `skipping` (failing,
or still running) blocks the merge, naming that check in the message.

Preconditions, for both checks: **fail-open** without `gh` or network (warn
loudly, allow) — including when a project hasn't adopted CI (no reported
checks is not a red flag, CI is optional, see F6); a substantiated `no` row
for `quality-review-before-merge` in `WORKFLOW-ADOPTION.md` disables both
checks for that project (local grep, no network); and there's an explicit
override that loudly reports what's being skipped — the same philosophy as
the deploy guards.

### F9 — Skills infrastructure in `adopt.sh`

**Per-skill symlinks in a real `.claude/skills/` directory**, plus cleanup of
orphaned workflow-owned symlinks.

A single directory symlink (`.claude/skills -> $CLAUDE_WORKFLOW_DIR/skills`)
is tempting — one line, and new skills ride along on a `git pull`. Rejected
anyway: it would make the **project's entire skills namespace owned by
`claude-workflow`**. `tennis-admin` could then never have a skill of its own
without de-adopting. That's exactly the coupling this repo exists to avoid.
Moreover, only the per-skill form is documented.

The cleanup is the part that matters: skills get renamed, and an orphaned
`.claude/skills/old-name/` isn't inert — Claude Code reports a load error for
it every session, in four projects at once. Rule: only remove symlinks that
point at `$CLAUDE_WORKFLOW_DIR` and no longer exist. Never touch real
directories (a project's own skill).

`.gitignore` gets a **managed block** instead of loose lines: the list is
going to churn, and the current append-only function can't remove anything.
Migration must strip the two existing loose lines, or they'd end up duplicated.

### F10 — The skill register

Names in English, body and description in Dutch. The name is an identifier
that sits in the same flat namespace as `code-review` and `security-review`;
`quality-review-before-merge` next to those reads like an accident. Everything
TiesL reads and maintains stays Dutch.

| Skill | Invocation | What goes in it |
|---|---|---|
| `pre-merge-review` | model + user | "Quality review before the merge" (40 lines) + scoping + F13's PR gate |
| `deploy-guards` | model | Deploy conditions per environment (~52 lines) + F6's production gate |
| `check-convention` | model | `check`/`deploy` naming convention + CI (~22 lines) |
| `adoption-registry` | model | Adoption registry (35) + substantiation requirement (15) + the protocol from `USER-CLAUDE.md` |
| `write-spec` | model + user | Specifying work + `Covers:` convention + `CONTEXT.md` glossary |
| `refactoring-triggers` | model | Complexity/debt/refactoring (32 lines) |
| `tdd-seams` | model + user | New: seams, red-before-green, three anti-patterns |
| `diagnose-bug` | model | New: reproduction → hypotheses → regression test before fix |
| `model-choice` | model | New (F26): capability/cost-aware model selection at every pipeline stage, stated qualitatively, never a model name |
| `adopt-workflow` | **user-level** | Adoption question + setting up a new project |

**Three choices that deserve explanation:**

*The substantiation requirement goes to `adoption-registry`, not `write-spec`.*
It currently sits under "Specifying work," but it's actually about answering
`WORKFLOW-ADOPTION.md` rows — the same subject as the registry section, which
already restates it in summary, and `USER-CLAUDE.md` a third time. One skill
folds three copies into one.

*`adopt-workflow` is the only user-level skill.* `USER-CLAUDE.md` sits at
`~/.claude/CLAUDE.md` and loads in **not-yet-adopted** projects, where
`.claude/skills/` doesn't exist. So every skill `USER-CLAUDE.md` refers to must
live in `~/.claude/skills/`, installed by `adopt.sh --user`. That asymmetry is
easy to get wrong and produces a dead reference in exactly the projects where
you won't notice.

*`CONTEXT.md` gets no skill of its own.* It's a template plus a convention:
`templates/CONTEXT.md`, a `CHANGES.md` entry, and two sentences in
`write-spec`. Ten skills is already the limit of what stays coherent.

### F11 — `pre-merge-review` as an executable skill

The strongest post. `WORKFLOW.md` *asks in prose* for a review "with fresh
context and on a different model" (reversed by #392, F39: at least as
capable, not necessarily different). Frontmatter expresses part of that
literally: `context: fork` gives the fresh, isolated context;
`allowed-tools` keeps it read-only. The model itself is deliberately
*not* pinned in frontmatter — a stale prior description here said it was —
`model-choice`'s qualitative floor (#392, F39: model and effort at least as
capable as Implementation's, with a recorded `floor-basis`; #244's
different-model rule is reversed) governs the choice instead, so the
rule survives new model releases without editing this skill.

The skill reads `WORKFLOW-ADOPTION.md` → `yes`-answered `spec-*` → the anchor in
the project PRD → the review scope. Reading the diff itself is delegated to
the existing `code-review` skill; this skill owns the *scoping*, the
context/model requirement, and the "findings in the PR, then resolved or
filed under Technical debt" step.

Two additions from the merge-guard and substantiation decisions: the skill
places a **machine-recognizable marker** in its findings comment (which F8
keys on), and it treats a touched topic whose `WORKFLOW-ADOPTION.md` row still
says "requires substantiation" as a review finding — that row gets answered
before the merge (F6's first gate).

### F12 — The core: `WORKFLOW.md` + routing table

`WORKFLOW.md` shrinks from 250 to ~85 lines and keeps what every session
needs: branch strategy, session start, during the work, the four-step
wrap-up sequence, and the closing note.

New and load-bearing: a **routing table** — a situation → skill table. That's
the R7 evidence ("directly in the file, or via an explicit, directly
followable reference"). It must name every moved topic; R7's five terms
(branching, quality review, substantiation requirement, deploy-guards,
adoption registry) must each resolve in a single jump. Two of them land in
the same skill — so two rows, not silently merged into one.

### F13 — Traceability, redesigned around reality

The original design assumed `F<n>`/`S<n>` everywhere. Reality:

| Project | PRD ids | Scenario ids | Issues used? |
|---|---|---|---|
| tennis-admin (flagship) | F1–F26 | **R(44) / A(24) / B(22) / P(6)** | 1 ever, still open |
| a2t-emails | F1–F8 | S1–S20 (+ `S2b`) | 6, **all open** |
| tennis-registration | F1–F7 | S1–S16 | never |
| tennis-invoicing | **no `F<n>`** | S1–S29, **S26/S27/S28 duplicated** | never |

**Decided in W17 (#29)**, the design review with TiesL that replaces the "one
work item end-to-end first" blocker. All four decisions below are confirmed,
with one addition: decision c gets an explicit limitation, see there. The
substantiation was re-verified against the four projects before the decision —
two claims turned out incomplete and are corrected below.

Four design decisions that rescue the design from this reality. The letters
**a** through **d** below are prose labels, not IDs: only `F13` is a
functionality item. The collector from decision c therefore only gathers ID
tokens from **headings** — forms like "F13a" in running text, and other
projects' IDs like the `F1–F26` in the table above, don't count.

**a. `AC<n>` in `work-item.md`.** That template numbers its own acceptance
criteria `### S1:` — the same namespace as `TEST-SCENARIOS.md`, so any `grep`
on `S<n>` is guaranteed to hit the issue itself. Not `A<n>`, and that
collision is sharper than it looks at first glance: `templates/ARCHITECTURE.md`
uses `A1` for architecture requirements, and tennis-admin has 24 `A<n>`
scenarios. If tennis-admin scaffolded that template, `A1` would mean two
things within one project — not a collision between projects, but within one.
Verified: `AC` doesn't occur in any of the four projects.

**b. One field name, `**Covers:**`**, in both directions; the token's prefix
says which link it is. Strict: start of line, comma-separated tokens
matching `^[A-Z]{1,2}[0-9]+[a-z]?$`. Both quantifiers come from reality, not
taste. The `[a-z]?` is there for `a2t-emails`' `S2b`; the `{1,2}` for
tennis-admin's `OP<n>` — that project uses `OP` for open points in both
`PRD.md` and `ARCHITECTURE.md`, and `O<n>` for weighed architecture options.
A grammar that rejects either one is unusable on day one in one of the four
projects. Only the field counts; that prevents false positives by construction.

**c. Don't hardcode `F`/`S` — check link integrity instead.** Collect the ID
tokens from the headings of `PRD.md` and `TEST-SCENARIOS.md`, and check that
every `Covers:` token resolves in the other set. This makes tennis-admin's
`R/A/B/P` work unchanged (the B-series was overlooked in an earlier
inventory — exactly the kind of mistake a hardcoded prefix list runs into),
turns tennis-invoicing's duplicate IDs into a **reported error** (a real
latent bug the original design didn't see), and gives a PRD without `F<n>` a
**warning**, not a hard error. A check that fails on day one in one of the
four projects is off by day two.

*What this choice costs*: see "Known limitations" below (the OP5 case).

The scope is bounded by decision c itself: the collector only reads headings
from `PRD.md` and `TEST-SCENARIOS.md`. tennis-admin's `O1`–`O5` — weighed
architecture options, four of which were rejected — live exclusively in
`ARCHITECTURE.md` and therefore aren't collected. `Covers: O2` therefore
correctly fails to resolve and gets reported. This problem can only occur for
things that live in the two scanned files.

That's deliberately accepted in W17. A reference to a wrong-but-existing
target is a documentation error a human catches in review; a hardcoded
`F`/`S` list makes the check useless in two of the four projects. Three
alternatives were weighed and rejected, on the same ground each time — they
require per-project configuration that silently goes stale:

- **Per-prefix exclusion list.** Goes stale the moment a project starts using
  a new prefix.
- **Filter by file.** Excludes `ARCHITECTURE.md`, but decision c already does
  that; the `OP<n>` case lives in the PRD itself and remains.
- **Filter by section within the PRD**, e.g. only headings under
  `## Functionaliteit`. Attractive, and therefore checked: of the four
  projects, only tennis-admin uses a `## Open punten` section; the other
  three have no open-points section at all, and `templates/PRD.md` doesn't
  either — this repo itself uses `## Open questions`. So the section names
  already diverge before anything is built on them, and filtering on that
  would move the staleness from prefixes to heading text instead of removing it.

See *Known limitations*.

**d. Split by network dependency.** Link 1 (functionality → scenario) is
offline and lives in `templates/check-traceability.sh`, scaffolded like
`ci.yml`, invoked from the project's own `check`. Links 2 and 3 (scenario →
issue → PR) are **not an audit script**, but a **gate in `pre-merge-review`**:
that skill runs at exactly the moment before the merge, already has `gh` and
network, and already writes its findings into the PR. "Does *this* PR
reference an issue" is one `gh pr view --json closingIssuesReferences`.

Link 3 additionally gets a **hard block in CI**: a skill remains voluntary,
and the baseline proves what comes of that. On GitHub Actions,
`GITHUB_TOKEN` is available for free — the gh-auth argument that keeps links
2/3 out of the local `check` doesn't apply there — and the check only judges
the current PR, so it's just as retrofit-free as the gate.

That eliminates the retrofit problem: an audit over 27 issueless PRs would
fail forever; a gate applies from the next merge onward.

### F14 — Blocking edges in the issue templates

`**Blocked by:** #` / `**Blocks:** #` in `work-item.md` and `epic.md`.
Deliberately a plain field, since `gh issue view` already shows
`blocked-by`/`blocking`; native sub-issues would tie the convention to
GitHub Projects.

### F15 — Release mechanism

This repo has no tags, releases, `CHANGELOG.md`, or version field. This
release adds `CHANGELOG.md`, tags the merge point, and restores the stalled
`**PR:**` reference — which currently holds for 3 of 27 entries, since the
convention stalled right after being introduced. Plus a test that enforces
that permanently.

Adopted projects follow `main` live via symlink, so a tag is a human
reference point, not a pinnable version. *(Revised for consumers outside
TiesL's own use: W37 (#79) builds a pinnable consumer path on top of this tag
mechanism — see `CHANGELOG.md`, "Decided in W29 (#53)", decision 5. This —
following `main` live via symlink — remains TiesL's own model.)* The first CHANGELOG entry
documents the required action: **run `adopt.sh` again in every project on
every machine, and `adopt.sh --user` once per machine** — without that last
step, the user-level skill is missing and the updated `USER-CLAUDE.md` points
at something that isn't there (the same asymmetry described under F10).

### F16 — Deferred maintenance

- `a2t-emails`: no `WORKFLOW-ADOPTIE.md` (fill it in, don't freshly seed it
  with today's date — that would misrepresent when a choice was made).
- `a2t-emails`: an untracked `AGENTS.md`, a 15 KB **copy** of `WORKFLOW.md` —
  a second, drifting source of truth that will actively contradict the new,
  slim core. Remove it.
- `README.md`: "**five** non-functional questions" — there have been fifteen
  since `4821bac`.
- `tennis-registration`: a leftover branch `chore/sessionend-push-hook`.
- All four: refresh the anchors in the project PRDs (a companion task, not a
  blocker — `pre-merge-review` falls back to heading names and reports that
  the anchors are missing).

### F17 — Coverage outside the agentic loop

The guard from F7 is a `PreToolUse` hook, and it only ever sees what Claude
itself executes. The documentation describes the event as "before a tool
call executes" and names no other hook point; commands TiesL types himself in
his terminal are not a tool call and therefore never pass through it. That's
an inference from the documented scope, not a warning the documentation
itself gives — but it's conclusive: there simply is no mechanism by which
those commands would reach the hook. The same `git reset --hard` in TiesL's
own terminal window, in an IDE, or on a second machine without `adopt.sh`
goes through unchecked.

Server-side branch protection would be the right place for this, but that
door is closed: GitHub literally answers, on a private repo, *"Upgrade to
GitHub Pro or make this repository public."* As long as that's the case,
coverage has to come from three local-and-CI-based layers:

- **`templates/ci.yml` validates pull requests and `main`** (W24). The
  template used `on: push: branches-ignore: [main]` and therefore validated
  *neither* PRs *nor* `main` — just like this repo's own workflow, which had
  the same form. Every new project therefore starts weaker than
  `tennis-admin`, which has a hand-written `ci.yml` with `on: pull_request`
  and `push: branches: [main]`. The `pull_request` event is also needed to
  set up a check as a *required check* — the form that can actually block a
  merge. Fixing the template only helps new projects, so it comes with a
  `CHANGES.md` entry (`ci-on-pr-and-main`, `has-check-command`): existing
  projects would otherwise keep their weaker CI without anyone asking. That
  entry is separate from `ci-convention` — that answer covers *what* the
  workflow does, this one covers *when* it runs.
- **Git hooks in the project** (W26). A `pre-commit` and `pre-push` hook
  cover every tool on that machine. They reuse the decision logic from
  `hooks/git-guardrails`. Note what's actually reusable: a native
  `pre-commit` receives no command string, so the quote-aware tokenization
  from `read-command.py` is `PreToolUse`-specific by definition. What can be
  shared is the *rules* — which branch is protected, what the message says,
  which way out it names. That's narrower than "reuse the script," and W26
  must make that distinction explicit instead of assuming a simple reuse
  exercise. Limitation: git hooks are machine-local and don't travel with a
  clone, so a new machine only has them after `adopt.sh`. That's the same
  limitation as the existing hooks, and F6's outdated-adoption notice makes
  it visible. `pre-commit` does not run the full `./check` (#378): a project
  opts in by having an executable `check-commit` at its root, the fast static
  subset, which the hook runs under a 30 s budget (`COMMIT_CHECK_BUDGET`, a
  positive integer; anything else is rejected, never read as a timeout). A
  static failure blocks, a timeout (TERM, a short grace, then KILL to the
  whole process group) lets the commit through with a warning, red tests never block, and
  the full suite runs in CI (`CHANGES.md` `ci-commit-check`).
- **CI detects commits on `main` that don't come from a PR** (W27). This is
  detection rather than prevention — the command has already run by then —
  but it's the only mechanism that works on every machine with every tool.
  The check only judges the incoming push, not the history: a retrofit that's
  red from day one teaches you to ignore the message.

The three layers are deliberately not interchangeable. W24 and W26 prevent,
W27 catches what slips through.

As of issue #377, the `pre-commit` hook runs the declared `check-commit`
without git's repo-local variables (cleared for that child process only,
via `lib/git-env.sh`), so a check that makes fixture git repos can't act on
the committing repo; git's own commit flow keeps them. If `lib/git-env.sh`
is missing, the hook warns and skips `check-commit` rather than run it
unisolated (S166, S167).

### F18 — Securing work without relying on the session end

The `SessionEnd` hook is currently the only automatic push. All work since
the previous session depends on it. Claude Code's documentation only says
that `SessionEnd` fires "when a session terminates," with a shared time
budget of 1.5 seconds, and names `clear`, `resume`, `logout`,
`prompt_input_exit`, and `other` as reasons. About a crash, a closed
terminal window, or a power outage it says **nothing** — so there's no
guarantee the hook runs then, and the budget also doesn't care how much
there still is to push. That silence isn't proof it goes wrong, but it is
reason not to make it the only safety net.

The commit block from F7 sharpens that further: block the commit on `main`
and ignore that message, and the work stays *uncommitted* — `SessionEnd`
then has nothing to push. Two additions close that gap on both sides:

- **Session start reports that `main` is checked out** (W23). The commit
  block only engages once work already exists; a notice at session start
  engages before that, while branching is still free. The guard blocks the
  commit, but not editing files — Edit, Write, `git add`, and `git stash`
  proceed normally. Purely informational: the hook mutates nothing and
  blocks nothing, and follows the same rule as the substantiation signal
  (exit 0, nothing on stderr).
- **Push as soon as something is committed** (W25). A `PostToolUse` hook
  pushes the current branch after a successful `git commit`. It's the same
  action `SessionEnd` already does, just earlier and more often — no new
  branch names, no mutation nobody asked for. `WORKFLOW.md` already
  prescribes "push regularly"; this makes that mechanical instead of
  something that has to be remembered. Without network or `origin`, it
  reports that and doesn't hold anything up.

### F19 — Issue-first branching (issue #212)

Link 3 (`check-pr-issue-link.sh`, W19b) already hard-blocks a PR that
references no issue — but only at PR time, which is after the branch,
after the commits, sometimes after CI has already failed once with
nothing to report against (the concrete case that triggered this: a
session opened a PR with no issue behind it at all). The same gap F17
already named for destructive commands applies here too: catching a
problem late doesn't stop the work that happened before it.

**Decision:** the branch name itself carries the issue number —
`feature/<issue-number>-<short-desc>` / `fix/<issue-number>-<short-desc>`,
replacing the previous `feature/<short-desc>` convention. Requiring the
number forces the issue to exist before the branch can even be named;
there's no way to "forget" it the way a free-text branch name allows.

Enforcement follows F17's three-layer shape, adapted to what's actually
checkable at each layer (branch names don't survive a squash-merge, so
CI can't be the third layer here the way it is for F17):

- **`hooks/git-guardrails` (PreToolUse)** blocks `git checkout -b`/
  `git switch -c` for a `feature/`/`fix/` branch whose name doesn't match
  `^(feature|fix)/[0-9]+-[a-z0-9-]+$`. When it does match, one `gh issue
  view <n> --json state` call (fail-open: no `gh`/no network → warn and
  allow, exactly the merge guard's `check_merge_guard`/`check_ci_guard`
  pattern from F8) blocks branch creation against a closed or
  nonexistent issue.
- **The native `pre-commit` hook** re-checks the same pattern, syntax
  only, on every commit on a non-main branch — no network call, so this
  hook keeps its existing offline character, and it's the layer that
  covers branch/commit activity outside Claude Code (plain terminal, an
  IDE), the same coverage argument as F17.
- No CI layer: unlike F17's destructive-command case, a branch name is
  local metadata that doesn't reach a PR's merged history, so there's
  nothing for CI to detect after the fact. The two hook layers above are
  the whole mechanism.

Both hooks share the pattern and message text via `hooks/rules.sh`
(`BRANCH_ISSUE_PATTERN`, `REASON_BRANCH_NO_ISSUE`) — the same
one-source-of-truth arrangement F17 already established for
`MAIN_BRANCH`. Same escape hatch as every guard here:
`CLAUDE_WORKFLOW_GUARDRAILS_OFF=1`.

Not retroactive: only *creation* of a new branch is judged, so branches
that already exist (on another machine, from before this change) are
never blocked mid-work — the same "when in doubt, allow" ground rule
`git-guardrails` follows throughout.

### F20 — Epic auto-close (issue #219)

An epic (`templates/ISSUE_TEMPLATE/epic.md`) stays open until every work
item under it is done, then someone has to remember to close it by hand —
found concretely with issue #211: both its work items (#212, #213) closed
via PR #214, but the epic itself sat open until TiesL noticed. The same
"don't rely on memory, build the mechanism" reasoning as F19.

**Mechanism**: `.github/workflows/epic-auto-close.yml` triggers on
`issues: closed` and calls `epic-auto-close.sh` with the closed issue's
number. That script extracts `**Epic:** #<n>` from the closed issue's body
(the field `templates/ISSUE_TEMPLATE/work-item.md` already asks every work
item to fill in), and — if the named epic is still open — lists every
issue in the repo whose body names that same epic (`gh issue list --json
number,state,body`, filtered locally). If none of them are open anymore,
the epic closes, with a comment naming which issues were checked.

**Deliberately not the epic's own "Work items" checklist.** That section
is for human readability and can drift — #211's checklist was never filled
in at all, yet the mechanism still needs to work from #211's own history.
The work item's `**Epic:** #` field is the one signal guaranteed to exist
by the template; same "only the field counts, not prose" rule
`check-traceability.sh` already applies to `**Covers:**`.

No fail-open the way the merge guard (F8) has one: this runs after the
fact, on its own event, and a missed close is recoverable by hand (as #211
was) — nothing here blocks other work if it errors. Repo-local for now;
scaffolding this to adopted projects (`templates/` + a `CHANGES.md` entry)
is a deliberately separate, later decision (#219's own "Out of scope").

### F21 — Merge guard: block a stray commit-level Closes (issue #223)

**Detects, deliberately, rather than preventing at the source** by forcing
an explicit `gh pr merge --body`/`--subject` on every merge. Controlling
the squash message only closes the *default-concatenation* path — someone
still has to remember to pass `--body`, and a hand-written `--body` can
just as easily carry a stray keyword by mistake (this repo's own PR #224,
which built this check, did exactly that in its *description*, not a
commit — see the Technical debt row below). Detection over the PR's
`closingIssuesReferences` versus its commits catches every source at once,
regardless of how the merge is invoked, instead of relying on a
convention that only covers one specific path and still needs the same
detection logic behind it to be worth anything.

`gh pr merge --squash` composes the squash commit's message from *every*
constituent commit by default, not from the PR's own title/body — a fact
that bit this repo concretely: PR #217 had an intermediate commit reading
"Closes #218" (a note-to-self about separate, still-unfinished follow-up
work), the PR's own title/body never mentioned #218, but the squash-merge
commit carried the concatenated commit list onto `main` anyway, and GitHub
closed #218 for real. Only caught by chance and had to be reopened by
hand.

This is the flip side of a fact `WORKFLOW.md` already documents (F8's
context, "Wrapping up" step 1): `closingIssuesReferences` — what link 3
checks — comes only from the PR's title/body while the PR is open. Once
merged, a commit-level closing keyword becomes real regardless of what the
PR itself intended.

**Mechanism:** a new, third check in `hooks/git-guardrails`,
`check_stray_closes_guard`, run from `check_merge_guard` after the
existing review-marker and CI checks (F8). Fetches the PR's own
`closingIssuesReferences` and every constituent commit's message (`gh pr
view --json closingIssuesReferences,commits`), scans the commits for
GitHub's own closing-keyword grammar (`close(s/d)`, `fix(es/ed)`,
`resolve(s/d)`, case-insensitive, followed by `#<n>`), and blocks the merge
if any referenced issue isn't also in the PR's own `closingIssuesReferences`
— naming the issue and the offending commit.

**Same gate, not an independent switch.** First implemented as a
separate, top-level check with its own escape-hatch logic — reverted
after it broke S18: `CHANGES.md`'s `quality-review-before-merge` entry
already establishes that a substantiated `no` disables *every* check in
this gate at once ("this isn't an independent on/off switch, since it's
the same gate" — written for `ci-gate-on-merge`, equally true here), and
S18 asserts, as a hard requirement, that `no` means **zero** `gh` calls
from the merge guard at all. `check_stray_closes_guard` therefore lives
inside `check_merge_guard`, inheriting both that early return and the
`merge_guard_off` escape hatch (AC6) from the caller — no separate check
of its own. Same fail-open rule as every other check in this guard: no
`gh`/network, or an unreadable response, means a loud warning and the
merge proceeds.

### F22 — No SIGPIPE/pipefail race, as an ongoing check (issue #218)

`printf '%s' "$var" | grep -q ...` under `set -o pipefail` races: `grep -q`
exits as soon as it matches, which can `SIGPIPE` the still-writing `printf`
before it finishes, and `pipefail` then reports that `SIGPIPE` exit as the
pipeline's failure instead of `grep`'s real, successful one — a value that
genuinely matches gets wrongly reported as not found. Found while
parallelizing the test suite (#216/#217): rare at low concurrency (the
write is tiny, usually finishes before `grep` even starts reading), much
likelier under the CPU contention parallel workers create. Ten instances
remained after the three that broke CI were fixed directly in #216/#217
— two in production scripts (`pending-changes.sh`, `scenario-gate.sh`),
eight in test cases.

**Fixed at all ten, plus two more** (`hooks/git-guardrails`,
`hooks/pre-commit`) that `check-no-sigpipe-race.sh` — the new check itself
— found on its very first run: added by F19 (issue-first branching, #212)
*after* #218 was filed, direct proof of the "easy to reintroduce by habit"
risk #218's own description named.

**Any producer, not just printf/echo — found the same way, one review
round later.** The check's own pre-merge-review (PR #226) found a live,
undetected thirteenth instance the PR itself was supposed to eradicate:
`pending_ids "$project" | grep -qx "..."` in
`test/cases/r8_retirement_stays_grepable.sh`, where `pending_ids` ends in
`sort` — a producer, just not `printf`/`echo`. The race is structural to
*anything* piped into an early-exiting `grep -q` under `pipefail`, not
specific to those two commands. Generalizing the check's own pattern
surfaced two more gaps in its first version: a combined flag cluster
(`-qx`, `-qF`, ...) wasn't matched (only a bare `-q`, or `q` as the last
character), and a pipe split across a backslash-continued line wasn't
either. Fixed, with `||` (boolean or between two independent, file-reading
greps — no producer, no pipe at all) explicitly not a false positive,
verified against real instances already in `adopt.sh` and
`s85_migration_reported_per_row.sh`.

**Ongoing check, not a one-time cleanup** (#218's AC3): this repo prefers
a mechanism over relying on a habit not slipping, the same reasoning
behind every other guard here. `check-no-sigpipe-race.sh` scans every
`*.sh` file plus extensionless bash/sh-shebanged scripts for the pattern,
excluding comment lines (a line documenting the anti-pattern, as several
fixed files now do, must not itself trip the check) and its own source.
Wired into `check` as a hard error, gated on the script's own presence —
same pattern as `check-no-dutch.sh` (S88) and `check-traceability.sh`
(link 1).

### F23 — The pre-merge-review marker is pinned to a commit SHA (issue #225)

Two related problems, one fix. **Problem 1** (existed regardless of
timing): the merge guard's marker check only checked whether the literal
string `<!-- pre-merge-review:done -->` appeared anywhere in the PR's
comments, not whether it was posted for the PR's *current* HEAD commit —
a commit landing after the marker (a last-minute fix, or a fixup after a
red CI) still got a stale marker accepted. **Problem 2**: `WORKFLOW.md`
had the review wait for CI to go green specifically to avoid problem 1 —
running earlier, in parallel with CI, risked exactly that staleness if CI
then failed and a fix commit followed. That serialization cost real time
on every PR: CI (5.5-8min this repo, F22) then review (2-5min) in full
series.

**Mechanism**: the marker becomes `<!-- pre-merge-review:done
sha=<commit-sha> -->` (`pre-merge-review`'s own `gh pr view --json
headRefOid` at review time). The merge guard (`check_merge_guard`) now
fetches `comments,headRefOid` in one call, parses the marker's `sha=` via
python3 (not a substring match — needs a real comparison), and blocks
unless some comment carries a marker whose sha equals the PR's *current*
`headRefOid`. stdout/stderr kept separate before parsing — the same
stream-contamination hardening as `check_ci_guard` (issue #81) and
`check_stray_closes_guard` (PR #224's own review), now needed here too
since this check moved from a substring case match to real JSON parsing.

**Fixing problem 1 removes problem 2's reason to wait.** Once a stale
marker is structurally rejected, running the review immediately —
alongside CI, not gated on it — is safe: whichever finishes first, a
commit landing afterward (whether the review or CI ran first) simply
requires a fresh review before merge, by construction. `WORKFLOW.md`'s
"Wrapping up" and the `pre-merge-review` skill both changed: review starts
as soon as the PR is open; the CI-watch cadence from issue #215 (5min then
1min) moved to where it now actually applies — knowing when it's safe to
ask for merge confirmation, not when to start the review.

### F24 — No apostrophe closing a `python3 -c '...'` block early (issue #228)

A bash *single-quoted* string has no escape mechanism at all — a literal
apostrophe anywhere inside a `python3 -c '...'` block (ordinary English
prose, e.g. a comment reading "PR #227's own pre-merge-review") ends the
string right there. Everything after is reparsed as bash code, with no
error until a syntax mismatch surfaces somewhere later in the file, often
at a completely unrelated line — exactly what happened building F23 (issue
#225): the resulting break in `hooks/git-guardrails` blocked every `Bash`
tool call in the session, since this repo adopts itself and that file is
also the session's own `PreToolUse` hook. Recovered only by reading the
file blind and manually counting quotes until the apostrophe surfaced.
Recorded as Technical debt at the time, with this issue as the trigger.

**Mechanism**: `check-no-quote-break.sh`, wired into `check` the same way
as `check-no-sigpipe-race.sh` (F22) — gated on presence, a visible skip
line (not a silent one) without `python3`. Doesn't need a real bash/python
parser: every `python3 -c '...'` block in this codebase closes on a line
whose *first* non-blank character is the closing `'` — checked across
every existing instance (`hooks/git-guardrails` ×3, `epic-auto-close.sh`,
two different closer shapes) before relying on it. Bash itself closes a
single-quoted string at the first `'` it finds after the opener, no
exceptions, so scanning forward from the opener for the first line
containing a `'` and checking whether that quote sits at the line's very
start tells us whether bash's real close point matches the block's
visually-obvious intended one. An apostrophe in ordinary prose is never
the first character of its line, since it always follows a word character
("it's", "#227's") — that's what distinguishes an accidental break from
the real, intended closer.

**Found live during its own development**: an early test fixture used
`print('hi')` — a single-quoted Python string literal, itself invalid
inside this exact bash construct for the same underlying reason — and the
new checker correctly flagged its own test fixture before the test was
even finished, one more direct demonstration of the class of bug it
exists to catch.

### F25 — `check-traceability.sh` stays in sync with `templates/` (issue #230)

`check-traceability.sh` (this repo's own root copy) and
`templates/check-traceability.sh` (scaffolded into adopted projects) are
meant to be identical — nothing enforced that, and they drifted silently
twice: #147 wired the root copy into this repo's own `check` at all
(until then it was unused, so drift went unnoticed by construction), and
#167 found and fixed one real drift the disconnection allowed (the root
copy had gone untranslated — Dutch identifiers and prose — while the
template had already been translated). Recorded as Technical debt.

**Mechanism**: a plain `diff -u` between the two files, inline in `check`
(not a separate `check-no-...sh` script — small enough that delegating it
would add indirection without adding anything), gated on both existing so
a project without `templates/` (fully adopted, no longer carries the
scaffold source) isn't affected.

### F26 — `model-choice`: capability/cost-aware model selection at every stage (issue #196)

`pre-merge-review`'s "Model choice" section already established one
instance of a principle: the reviewer must use a model different from,
and at least as capable as, the model that wrote the reviewed change
(#244 — same model only with an explicit, recorded exception), and,
within that floor, the most cost-effective choice. That principle applied
at exactly one point in a work item's life. This generalizes it to every
artifact-producing stage anticipated by the multi-agent epic (#65) —
Discovery, Planning, Test authoring, Implementation, Review — before #65
moves from exploration into concrete work items.

**The rule stays relative, never a hardcoded name.** A floor is stated as
what a stage's output has to survive ("can write a test that actually
falsifies a wrong implementation"), never as a model name or tier
("mid-tier", a specific model ID). Tiers shift as models are introduced;
a name written into a skill today is stale the moment a new one ships.
Every later stage anchors its floor to the stage before it, the same way
Review already anchored to Implementation. The one stage with no
predecessor — Discovery — floors directly on the task's own demands
instead, described the same qualitative way.

**Visibility tightens.** Every stage records which model and reasoning
effort handled it, always — not only when it deviates from what's
obvious, which was `pre-merge-review`'s old bar. `pre-merge-review`'s own
"Model choice" section is replaced with a cross-reference to the new
`model-choice` skill, so there's one canonical statement instead of two
that could drift apart.

No behavior change to existing single-agent-per-stage practice — this
documents the principle so #65's future orchestration has it ready-made.

### F27 — Machine-readable model-record markers (issue #241 AC1)

`process-model-choice` was unenforceable in practice: only the Review
stage ever recorded a model in `portfolio-mgt-agents` (#238);
Discovery/Planning/Test/Implementation never did, and the skill's prose
instruction had no mechanical check behind it. Each stage now carries a
`<!-- model-record: stage=<Stage> model="..." effort="..." -->` marker.
`model-record-gate.sh <pr-number>` checks a PR's own comments/description
and the comments of every issue it closes for all five stages, reporting
whichever are missing. Fails open (a warning, not a block) without `gh`.
Same mechanism also catches a same-model Review recorded at lower
effort than Implementation, and a Review marker without `floor-basis`
(#392 replaced #244 AC2's different-model finding; see F39) — see the
Technical debt entries on this gate's own known gaps (spelling-mismatch
false negatives, comment-ordering heuristic).

### F28 — Machine-readable finding-carryforward markers (issue #241 AC2)

A review finding could silently vanish between fresh-context rounds with
nothing to catch it — `portfolio-mgt-agents` PR #4: round 1 flagged a
missing entry, round 2 never carried it forward, merged 17 seconds later.
Every finding now carries its own
`<!-- finding:<slug> status=open|resolved -->` marker.
`finding-carryforward-gate.sh <pr-number>` compares the two most recent
`pre-merge-review:done` comments and reports any slug the previous round
left open that doesn't reappear (as still-open or resolved) in the new
one. With only one review round so far, or without `gh`, it fails open.

### F29 — The 4th traceability link: issue structure (issue #242)

Links 1-3 (F13) check PRD↔scenario, scenario↔issue, and PR↔issue — none
of them look at the issue's own shape. `portfolio-mgt-agents` had issues
with no epic/work-item structure at all: no `AC<n>` heading, no
`**Covers:**` field, no linked work items. `issue-structure-gate.sh
<pr-number>` closes that gap, run from `pre-merge-review` like links 2/3:
for every issue a PR closes, a work item missing its `AC<n>` heading or
`Covers:`/pre-migration `Dekt:` field is a finding (one per missing
piece); an epic whose Work items list has no real `#<n>` entry (only the
unfilled template placeholder) is a finding. A well-formed issue produces
none. Fails open without `gh`.

### F30 — `adopt.sh` untracks a managed path already tracked before adoption (issue #243 AC2)

`CLAUDE.md` committed as a real, tracked file before `adopt.sh` ever ran
made `write_gitignore_block`'s entry a no-op retroactively — git doesn't
stop tracking a path just because it later appears in `.gitignore`.
`untrack_managed_paths()` runs `git rm --cached` on any of the three
managed paths (`CLAUDE.md`, `.claude/settings.json`, `.claude/skills/`)
already tracked, keeping the working-tree file (now the real symlink
`adopt.sh` creates, never deleted) and letting the `.gitignore` entry
actually take effect. A project where a path was never tracked is
unaffected.

### F31 — `adopt.sh`'s symlink install survives a relocated checkout (issue #56/W32)

`adopt.sh` points `CLAUDE.md` at `$SPEC_DRIVEN_GUARDRAILS_DIR/WORKFLOW.md`
and `.claude/settings.json` at its `settings/session-hooks.json` — both
absolute symlinks, so a relocated checkout (a rename, a move) leaves
every already-adopted project's symlinks dangling until `adopt.sh` runs
again with the new location. Two things make that recoverable rather
than a silent trap. First, re-running `adopt.sh` from the new location
repoints both symlinks in one action, retroactively, no matter how many
projects or machines are affected — a third run after that is a no-op.
Second, a dangling `.claude/settings.json` (the checkout moved, but a
project hasn't re-adopted yet) reports itself loudly at session start
— "doesn't exist... run adopt.sh again" — instead of silently running no
hooks at all, which is worse than an error: nothing would otherwise
indicate the guardrails had gone quiet. A healthy symlink, or a project
that was never adopted, stays silent either way — this is a diagnostic
for exactly the broken-symlink state, not a general adoption check.

### F32 — `test/cases` file ↔ `TEST-SCENARIOS.md` heading, enforced 1:1 (issue #260)

The same mistake happened twice: a new `test/cases/s<n>_*.sh` file gets
numbered without checking `TEST-SCENARIOS.md`'s actual existing scenario
numbers, colliding with an unrelated pre-existing heading — #241/PR #249
hit it, #250/PR #259 hit it again for four earlier files, both times
caught only by hand during `pre-merge-review`. Nothing mechanical checked
the correspondence at all: `scenario-gate.sh` (link 2) checks headings
against issue `Covers:` fields, never against test-file names;
`check-traceability.sh` (link 1) checks PRD-functionality ↔ scenario
headings, not scenario-to-file correspondence.

`check-scenario-file-sync.sh` closes that gap, wired into `check`. Ground
truth for which IDs a file covers is its own header comment (the line
right after the shebang) — `# S19-S23 — ...` (a range, hyphen), `# S52,
S53, S59 — ...` (a discrete list, comma), prefixes may mix (`# T1, T2,
S30 — ...`) — not the filename, which is a human mnemonic only (a
range's filename typically names just its two endpoints). Reports, and
fails, on: a file claiming an ID with no matching heading; a heading
with no file claiming it; the same ID claimed by more than one file; the
same heading appearing more than once. A curated `pending_excluded` list
(same two-tier pattern as `check-no-dutch.sh`) exempts genuinely
pre-existing orphan headings found while building this check but out of
its own scope to resolve — tracked in #272, shrinking as each is
resolved.

Building this check surfaced the pre-existing S78/S79 gap this issue's
own AC2 names (fixed directly, given real F31), plus seven more (#272).

### F33 — `wait-for-ci.sh` enforces the CI-polling cadence as a script (issue #265)

`WORKFLOW.md`'s merge step stated the 5-minutes-then-1-minute CI-polling
cadence (issue #215: this repo's own CI clusters at 5.5-8 minutes, so a
short fixed interval produces a dozen-plus premature "still pending"
checks) as prose. That rule already lived in always-loaded context, so
the gap wasn't discoverability — an agent could still improvise a
different interval ad hoc, the same "agreement in prose, mechanism in a
script" gap `check-pr-issue-link.sh`/`check-main-via-pr.sh` already
closed for links 3 and W27.

`templates/wait-for-ci.sh` (scaffolded alongside those two, same
has-check-command gate — meaningless without CI to poll) waits 5 minutes
without checking at all, then polls `gh pr checks` every 1 minute until
every check reaches a terminal state, printing each check's name and
state and exiting non-zero if any of them didn't pass. Kept in sync with
its root copy the same way as `check-traceability.sh` (#230's own
pattern, extended here). `WORKFLOW.md`'s merge step now directs its use
directly instead of describing the interval only as prose.

### F34 — `compliance-evidence.sh` collects pre-existing OQ9 evidence for one work item (issue #296)

Read-only script: given a PR number, gathers pre-existing evidence for
each of the six decided compliance gates (OQ9, `PRD-MULTI-AGENT-WIP.md`
§6) and renders the Gate/Status/Evidence table to stdout. Implements the
decided OQ9 report shape; does not reopen it. No posting, no judgment, no
new dependencies — same category as `check-traceability.sh`/
`wait-for-ci.sh`.

`compliance-evidence.sh` at repo root (dogfood-only — not under `skills/`
or `templates/`, no propagation to adopted projects for this epic; not
invoked by `./check`, only its tests are, since it needs `gh`/network and
`./check` must stay usable with no GitHub credentials). Status vocabulary
is closed to four values — `evidenced`, `not-evidenced`,
`unverifiable-from-artifacts`, `indeterminate` — with `indeterminate`
reserved for an artifact that was found but can't be interpreted
(malformed marker, unknown CI bucket, a failed sub-lookup), kept
distinct from `not-evidenced` (no artifact at all) because the reader's
next action differs.

This single heading exists as the narrow, stated exception to normally
not touching `PRD.md` mid-epic (issue #296's non-goals; origin:
`ARCHITECT-REPORT.md` D3 option (a), accepted by Product) — it's routine
traceability wiring for real new functionality, not premature promotion
of the WIP design: `check-traceability.sh` enforces `Covers:`
bidirectionally, so `S150` can't resolve without an `F34` heading here.

### F35 — `role-label-staleness.sh` detects `role:<name>` label staleness for one issue (issue #315)

Read-only script: given an issue number, finds the issue's current
`role:<name>` label (if any) and every PR that closes it, extracts each
source's `model-record` stage markers (skills/model-choice/SKILL.md), and
reports whether the label is stale relative to the latest evidenced
stage — Discovery < Planning < Test < Implementation < Review, the same
fixed order that skill's own "Per-stage floors" table already fixes. A5
(`ARCHITECTURE-MULTI-AGENT-WIP.md`) decided the label is a traceability
record the orchestrator updates by hand, never state an execution
mechanism reads back; this script only ever informs a reader when that
record has fallen behind, never blocks or edits anything.

`role-label-staleness.sh` at repo root (same dogfood-only placement as
`compliance-evidence.sh` — not under `skills/` or `templates/`, no
propagation to adopted projects for this epic; not invoked by `./check`,
only its tests are, since it needs `gh`/network and `./check` must stay
usable with no GitHub credentials). Status vocabulary is closed to four
values — `not-started`, `in-sync`, `stale`, `indeterminate` — with
`indeterminate` reserved for two-or-more `role:<name>` labels at once, a
`model-record` marker that matched but carries no recognized `stage=`
value, or a PR lookup failure that leaves the evidence set provably
incomplete in a way that could still change the verdict; a label at or
ahead of the latest evidenced stage is `in-sync`, never `stale` — the
label tracks the active phase, not the last completed one.

This single heading exists as the same narrow, stated exception `F34`
above already used (that exception's origin is issue #296's non-goals
and `ARCHITECT-REPORT.md` D3 option (a), accepted by Product for `F34`
itself; applied here to real new functionality again, not premature
promotion of the WIP design): `check-traceability.sh` enforces `Covers:`
bidirectionally, so `S152` can't resolve without this heading.

### F36 — `classify-review-depth.sh` classifies a PR quick/thorough by Reviewer's six trigger categories (issue #328)

Read-only script: given a PR number, reads its changed-file paths and its
own title+body text, matches both against Reviewer's existing six
security-review trigger categories (`skills/
role-contracts/SKILL.md`'s "Security review triggers" table — Auth/
session, Secrets/credentials, Deploy/CI configuration, Infrastructure as
Code, Sensitive/personal data, Untrusted input), and prints `review-depth:
quick` or `review-depth: thorough (<matched categories>)` — no new risk
taxonomy, no size/files-touched dimension (A13 in
`ARCHITECTURE-MULTI-AGENT-WIP.md` explicitly rejected the latter). An
optional `--force-thorough` flag classifies `thorough` even with zero
category matches, evidenced as `(forced)` rather than a false category
claim, so the mechanism has a real, dogfoodable caller before issue #307
decides on any default-on rule; on a real match, the override is strictly
additive and never masks the genuine matched category names.

A REST call failure (changed-files or title/body lookup) fails open
toward `thorough`, not `quick` — the inverted direction from every other
gate in this repo, since this classifier's only purpose is triggering
*extra* scrutiny and an unreadable diff/description is exactly the case
with the least evidence to rule a category out. `gh` missing from `PATH`
entirely is a harder, distinct failure (non-zero exit, nothing on
stdout), never folded into that same fail-open behavior, so a caller can
tell "no answer" apart from "got an answer, chose caution."

`classify-review-depth.sh` at repo root (same dogfood-only placement as
`compliance-evidence.sh`/`role-label-staleness.sh` — not under `skills/`
or `templates/`, no propagation to adopted projects for this epic; not
invoked by `./check`, only its tests are, since it needs `gh`/network and
`./check` must stay usable with no GitHub credentials). The script also
defines and exposes (`--lens-adapter-count`) `LENS_ADAPTER_COUNT`, the
fixed number of generic lens-Adapter forks `skills/pre-merge-review/
SKILL.md`'s thorough-mode dispatch prose adds on top of Reviewer when the
verdict is `thorough` (A13) — a single named, testable seam for that
constant, so a future prose edit that lets the two numbers drift apart is
a test failure, not a silent mismatch. The classifier's own stdout never
prints this constant, or any other count/multiplier, on a `thorough`
verdict — only matched category names (or `forced`/`lookup-failed`).

This single heading exists as the same narrow, stated exception `F34` and
`F35` above already used (origin: issue #296's non-goals and
`ARCHITECT-REPORT.md` D3 option (a), accepted by Product for `F34`
itself; applied here again to real new functionality, not premature
promotion of the WIP design): `check-traceability.sh` enforces `Covers:`
bidirectionally, so `S154` can't resolve without this heading.

### F37 — The multi-agent workflow is adoptable, opt-in (issue #369)

v0.2.0 shipped the five-role pipeline as something only this repo used:
the role contracts lived under `wip/`, which `adopt.sh` doesn't install,
and `CHANGES.md` had no entry, so `pending-changes.sh` asked an adopted
project nothing. An adopting project that tried to take up v0.2.0 found
it "not adoptable yet". This feature closes that gap without adding an
orchestrator: the offer stays contracts plus read-only evidence.

What an adopted project can do afterwards:

- **Be asked.** One `CHANGES.md` entry, `process-multi-agent-roles`,
  `Default: question` (no general preference: it multiplies agent
  sessions per work item and has only been run on this repo), `Applies
  if: always`. Every adopted project sees it as pending at its next
  session; `question` rows never seed at adoption.
- **Dispatch the five roles from its own checkout.** `role-contracts`
  lives under `skills/`, so `adopt.sh` symlinks it like every other
  skill. Every pointer in it resolves from an adopted project: methods it
  relies on are named as installed skills (`grilling`,
  `codebase-design`, `model-choice`, `tdd-seams`, `pre-merge-review`),
  not as paths into this repo's `wip/.../vendor/`; anything that does
  stay in this repo (the WIP design sources, used only to settle a
  dispute about a contract's intent) is named as living in the clone
  `SPEC_DRIVEN_GUARDRAILS_DIR` points at. The human who receives
  escalations and decisions is named by role (the project's human
  decision-maker), not by person.
- **Know what the run needs.** The skill states the fixed stage order
  (Discovery, Planning, Test, Implementation, Review), the
  `model-record` marker each stage leaves (`model-choice`), the five
  `role:<name>` labels (`role:product`, `role:architect`, `role:qa`,
  `role:dev`, `role:reviewer`) the project must create in its own
  GitHub repo if it wants `role-label-staleness.sh` to say anything, and
  that every role takes part in every change (no phase skipping in v1).
- **Optionally read the evidence.** `compliance-evidence.sh`,
  `role-label-staleness.sh` and `classify-review-depth.sh` stay at this
  repo's root (not copied, not run by any `check`), and are invoked by
  path from the clone with the adopted project's checkout as working
  directory; they address `repos/{owner}/{repo}` from that directory's
  remote, need `gh`, and never write. This narrows the "no propagation to
  adopted projects" clause in `F34`-`F36` to "not installed or wired";
  invoking them from the clone is supported.

Not part of this feature: an orchestrator, the release-branch tier
(still this repo's own practice), and shortening the pipeline per change
type.

### F38 — A session in an opted-in project runs the five-role pipeline without being prompted (issue #371)

F37 made the multi-agent workflow adoptable, but nothing makes a session
apply it. Verified failure (2026-10-01, while working on #369): a session
in this repo did the whole change itself, playing every role, and only
started the pipeline after the human asked why. Nothing it loaded told it
to: this repo's local `CLAUDE.md` link had gone missing (machine-local
drift that nothing reported; `WORKFLOW.md` said nothing conditional on a
yes row anyway), `SessionStart` reports only unanswered
rows, `role-contracts` isn't auto-loaded, `model-choice` says a single
session per stage is fine, and the evidence can't tell a dispatched
pipeline from one session playing five roles. This feature states the
requirement; the Architect designs the mechanism.

Requirement: in any project whose `WORKFLOW-ADOPTION.md` answers
`process-multi-agent-roles` yes, this repo included, a session that
starts a work item (a request that produces a commit intended for a PR)
acts as orchestrator and dispatches the five roles as separate role
sessions, from the first work item, unprompted. A session that doesn't is
detectable from the work item's own evidence before merge. The same
guarantee covers future workflow changes: a change that alters what a
session must do can't ship as prose no session loads.

Acceptance criteria (full text in issue #371):

- **AC1-AC2** activation in an opted-in project and in this repo (no
  special case); **AC3** no activation without a yes; **AC4** none for
  non-work-items (questions, research, reviewing an existing PR, adoption
  questions, git/ops on reviewed work, co-thinking).
- **AC5** role sessions never nest a pipeline; **AC6** a human override
  is explicit and leaves a machine-readable record, never self-granted
  ("trivial"); **AC7** if the session can't dispatch, it says so and asks
  rather than role-playing; **AC8** a new session resumes at the next
  unevidenced stage.
- **AC9** a run where one session played every role, with no override
  record, is distinguishable from a dispatched pipeline and flagged before
  merge, fail-open without `gh`/network.
- **AC10** a `CHANGES.md` entry whose *Yes means* changes what a session
  must do fails `./check` unless it declares how it reaches the session
  (always-loaded context, hook, or gate), and that path is tested.
- **AC11** updates reach opted-in projects through the existing symlinks;
  **AC12** no always-loaded or installed text calls a single session
  doing every stage the norm (`model-choice`'s "No behavior change"
  section is reconciled).

What is honestly not mechanically testable: the session's own behaviour.
AC1 and AC4-AC8 (starting the pipeline, declining it for non-work-items,
never nesting, stopping when it cannot dispatch, resuming at the right
stage) can only be shown by a human dry run in a real session. Scenarios
cover the loaded text and hooks that are supposed to cause that
behaviour, not the behaviour. The merge-time block in AC9 is mechanical:
the merge guard refuses `gh pr merge` on the gate's `role-played:`
finding in an opted-in project (S183, S186); S185 checks the review
procedure says the same. Delivery depends on two platform facts, probed
once (Claude Code 2.1.287, headless): `SessionStart` output reaches the
top-level session but not a freshly dispatched subagent, and the hook
fires again on resume and after compaction.

Not part of this feature: orchestrator software, per-change-type phase
shortening (#281), changing the role contracts' content (#369), and
verifying the role sessions' quality (AC9 covers only that they were
separate dispatches).

### F39 — Review is at least as capable as Implementation, not necessarily a different model (issue #392)

#244 resolved a contradiction between `CHANGES.md` and `pre-merge-review`
in favour of the stricter rule: a genuinely different Review model,
same-model only as a recorded `same-model-exception`. A bounded dry run of
the pipeline (#371) showed the cost: the orchestrator chose one model and
one low effort for every stage, and the gate flagged Review. The
maintainer reversed the choice (2026-10-03).

Requirement: Review's model and effort, taken together, are at least as
capable as the Implementation stage's, and among the combinations that
clear that, the cheapest is chosen (the `model-choice` principle applied
to Review). A different model is not required. No text or script names a
model or tier.

Decisions (maintainer, 2026-10-03):

- On the same model, a Review at lower effort than Implementation is a
  gate finding. For two different models no capability finding is raised:
  there is no ordering a script can check without a model table, and a
  table would break the rule that floors never name a model.
- `quality-review-before-merge` moves to meaning version 3, so adopters
  that answered at v1 or v2 are re-surfaced to re-confirm.
  `same-model-exception` is retired: ignored completely for one release
  (not counted as a substitute for anything), not repurposed.
- Every Review `model-record` marker carries `floor-basis="<one
  sentence>"`, the Reviewer's stated reason why its model and effort clear
  Implementation's. A missing or empty one is a non-blocking finding; the
  text is never verified.
- `compliance-evidence.sh` reports two different models as
  `unverifiable-from-artifacts`, never `evidenced`.
- Documentation names the full model id as the platform reports it, but
  does not require it. A short alias and its full id then count as
  different models: gate 2 reports `unverifiable-from-artifacts` (the script
  cannot tell an alias from a different model), never a pass. `normalize_model` stays generic (no model table).
- The orchestrator assesses each stage's floor per `model-choice` and
  sets model and effort per stage, not one pair for the whole run.

Acceptance criteria (full text in issue #392): **AC1-AC2** the rule is
stated one way and no live text demands a different model; **AC3** same
model: effort compared; **AC4** different models: no mechanical verdict,
stated as such; **AC5** a legacy `same-model-exception` is ignored;
**AC6** gate 2 keeps its lookup-failure degradation to `indeterminate`;
**AC7** the meaning-version bump and its fixtures; **AC8** the
orchestrator wording; **AC9** the recorded judgment (`floor-basis`);
**AC10** specs and scenarios follow.

What is mechanically verified: that Review and Implementation markers
exist; that on an equal normalized model Review effort is not lower (known
effort values `low < medium < high` only); that `floor-basis` is present
and non-empty; that the orchestrator text states the per-stage rule; that
no live text demands a different model. What stays judgment and is only
recorded, never checked: whether `floor-basis` is true; whether a
different model clears Implementation's capability; whether an effort that
is equal and low was adequate for both stages; and whether the
orchestrator in a real session actually chooses efforts per stage (model
behaviour, shown only by a human dry run). An unknown or missing effort gives
no claim in the gate and `indeterminate` in gate 2; a short model alias that
doesn't normalize equal to its full id counts as a different model, so gate 2
reports `unverifiable-from-artifacts`, never a pass.

Delivery: two PRs in the same release as #369/#371, before its release PR
opens, so the gate never blocks a Review the new rule allows. PR 1 changes
only `skills/role-contracts/ORCHESTRATOR.md`. PR 2 is the rest: the shared
`lib/model-record.sh`, both scripts, `model-choice` and `pre-merge-review`,
the `CHANGES.md` v3 entry, this repo's adoption row, and the specs and
tests. The dispatch tool takes a model but not an effort, so the
orchestrator may not control effort; its wording covers that by choosing a
more capable model instead.

Not part of this feature: a model-capability table, verifying `floor-basis`
text, a hard merge block (findings use the existing non-blocking
`model-record:` prefix), and changing the markers of the other four stages.

### F40 — Dispatched roles write well-formed `model-record` markers, and the gate says when one is unreadable (issue #402)

A rerun of the bounded full-pipeline dry run (release head fa1beae) showed
two gaps in the multi-agent pipeline. The Product, Architect, QA and
Developer roles wrote their markers unquoted
(`model=claude-haiku-4-5 effort=low`), so `compliance-evidence.sh`
reported gates 1 and 2 `indeterminate`; only the Reviewer, which read
`pre-merge-review`, wrote the documented quoted form. And
`model-record-gate.sh` printed nothing for a PR whose Implementation
marker had no parseable quoted `model=`, while the collector said
`indeterminate`: the same unreadable marker was visible in one tool and
silent in the other.

Requirement: (1) nobody types a marker. One command,
`skills/pre-merge-review/model-record-emit.sh` (`marker_emit` in
`lib/model-record.sh`, A26), prints the one valid line, checked by parsing
it back, or nothing. The orchestrator puts that command into every
dispatch prompt with the stage and effort filled in (`unknown` when it
can't know the effort); the role adds its own exact model id (and, for
Review, its `floor-basis`) and pastes the output unchanged as the first
line of its report. The marker format and grammar are written down in one
place, `model-choice`; `ORCHESTRATOR.md` carries no copy. (2) For the
latest marker of each of the five stages, an unquoted, empty or missing
`model` or `effort` makes `model-record-gate.sh` print a visible finding
with the existing `model-record:` prefix, one per stage and field, and a
malformed marker of any stage (a quoted `stage="..."` included) is named.
The findings are non-blocking, consistent with the collector's
`indeterminate`, and never use the `role-played:` prefix that the merge
guard keys on.

Decision (maintainer, 2026-10-03): fix before the release PR that carries
#369, #371 and #392. The scratch repo is kept for a re-run that validates
the fix. Further decisions on the Architect's design (A26): an unquoted
marker is reported, not tolerated; the finding covers all five stages and
both `model` and `effort`; the role fills in `model`. The emitter is never
stricter than the grammar for a `floor-basis`: it refuses only a double
quote, a control character (newline, U+001E, ...), a blank or over-long
text, and a floor-basis on a stage other than Review.

Acceptance criteria: full text in issue #402.

What is mechanically verified: that `ORCHESTRATOR.md` tells the
orchestrator to pass the emit command per stage and contains no second
copy of the grammar; that every line the emitter prints reads back
through the parser in both locales, and every refused input prints
nothing; that the gate prints a `model-record:` finding for an unreadable
`model` or `effort` on the latest marker of any stage and for a malformed
marker, and stays silent for a well-formed one, a stage that is missing (already a
separate finding), a `stage=...` placeholder (not a real marker) and a
project that did not opt in where applicable. What stays judgment and is
not checked: whether the orchestrator in a real session actually pastes
the marker line (model behaviour, shown only by a re-run on the scratch
repo); whether the model name a role records is the model it really ran
on (a pasted marker can carry a made-up name); and whether every role
session follows the instruction.

Not part of this feature: the role-played-in-fence issue (#400), the
dispatch tool having no effort argument (A25), interactive-mode and fork
dispatch coverage, and verifying marker contents beyond parseability.

### F41 — Every Review round is a fresh Reviewer dispatch (issue #414)

The meta review (#405) found one Reviewer continued through `SendMessage`
across rounds 3 to 5 of #397 and again for #403, so the later rounds
inherited the earlier round's view. Requirement: every Review round is a
new dispatch of a fresh agent, never a resumed or continued one (not via
`SendMessage`, not via the dispatch tool's `fork` type); its brief is built
from artifacts (PR head SHA and diff, the work-item issue, the previous
round's findings), never from the earlier Reviewer's conversation; the
previous round's findings are inputs the new Reviewer re-checks, not
memory. Whether two rounds came from different agent instances cannot be
checked from GitHub artifacts: the rule states that limit, and the
fallback is a pipeline-log line per dispatch plus a self-check line before
asking for a merge.

Acceptance criteria: full text in issue #414. Mechanically verified: the
rule text in the three files, the explicit Reviewer ban on `SendMessage`
and `fork`, the brief inputs, the carry-forward wording, the stated limit
and the log and self-check text. Not verified: that a real orchestrator
follows the rule, and that two rounds were different instances (the
stated limit, case (b) of AC5: not a pass).

---

## Non-functional characteristics

### Security

Relevant, limited. The guardrails hook (F7) is itself a security measure.
`check-traceability.sh` parses issue and PR text — input that isn't fully
under this repo's own control — so no `eval`, just as the predicates are
deliberately a `case`. No secrets in this repo.

### Data integrity

Strongly relevant. `WORKFLOW-ADOPTION.md` is the durable record of decisions
and must never be overwritten. F16 touches this directly: filling in
`a2t-emails` must not become a fresh seed with today's date. F6 is explicitly
designed so it does *not* change what "answered" means. `adopt.sh` stays
idempotent — "running it twice yields an identical tree" becomes a test.

### Failure modes

Strongly relevant. Hard requirement: a hook never blocks a session. The new
`PreToolUse` hooks (F7, F8) are the exception — they're *supposed* to block,
but must fail to *allow* if they're broken themselves (and F8 also without
`gh` or network), and the `if/exec/fi` form is decisive for that.
`check-traceability.sh` warns and proceeds without `gh` or network, following
the existing rule from the deploy guards.

### Observability

Relevant. Silent degradation is the main failure mode: the hook chain ends in
`|| true`, so a broken symlink produces silence. `check` (F1) and the
outdated-adoption notice (F6) are the antidote — what CI and the hook can
see doesn't erode.

### Performance and scale

Barely relevant, but named. `pending-changes.sh` re-reads its source once per
outstanding ID (O(n·m)); negligible at 27 entries. F4 splits the source in
two, so the shared parser must not get slower because of that.

### Deployability

Strongly relevant, and unusual in form. "Rolling out" means: merging to
`main`. Consumers follow `main` live via symlink, so every merge is
immediately active in four projects, with no opt-in and no rollback path
other than a revert. There's no staging between merge and use — that raises
the bar for F1. What `adopt.sh` installs lags behind instead, until someone
re-runs it; F6 makes that self-reporting.

### Privacy

N/A, substantiated. No personal data beyond the git author information
that's already there. Adoption tables contain decisions.

### Compliance and auditability

N/A as a legal requirement; yes as a self-imposed one. The adoption registry
exists precisely to make it demonstrable which project applies which
agreement and why. F4 and F5 must not break that demonstrability: a moved or
archived entry must remain findable from a `WORKFLOW-ADOPTION.md` that points
to it. That's R8, and after F4 it also applies to the fifteen relocated NFRs.

### Backup and recovery

Relevant, low risk. Everything of value lives in git. The vulnerable part is
what's *not* in git: the local, untracked symlinks per machine. Recover by
re-running `adopt.sh` — idempotent, already documented as a safety net.

### Portability

Relevant, with a deliberate new dependency. Until now, this repo was bash +
`gh` + markdown. Skills are a **Claude Code-specific** format; the
frontmatter F11 uses (`context: fork`, `model:`) isn't supported by other
harnesses. Deliberately taken on, recorded here so it's a decision and not an
accident. Within that, a further limit: this frontmatter is recent, and the
two machines may run different Claude Code versions — verify before W13
relies on it. Bash 3.2 is the second portability limit and constrains the
scripting idiom.

**Boundary between the core and agent tooling (W31, #55).** Level **a —
naming only**: this table documents the boundary that already implicitly
exists, without building an adapter layer or contract (see `CHANGELOG.md`,
"Decided in W29 (#53)", decision 2).

**Translation scope, A + B, via a criterion (W29 decision 3, W33/#57).**
What migrates along to the four adopted projects (not translated
themselves) isn't a hand-maintained list but a durable criterion: *every
literal string that a script from this repo matches in a file of another
repo* — layer A (physically shared files, e.g. `CLAUDE.md`) plus layer B
(shared vocabulary a script reads back, e.g. `**Covers:**`). Layer C
(scaffolded output already locally owned by an adopted project) is
explicitly excluded. Full reasoning: `CHANGELOG.md`, "Decided in W29
(#53)", decision 3.

| Agent-independent | Claude Code-specific |
|---|---|
| Templates (`PRD.md`, `TEST-SCENARIOS.md`, `ARCHITECTURE.md`) | `settings/session-hooks.json` |
| Adoption registry (`CHANGES.md`, `WORKFLOW-ADOPTION.md`) | `hooks/` (`PreToolUse`, `SessionStart`, `SessionEnd`) |
| The `nfr/` registry | `skills/` |
| Traceability (`Covers:`, `AC<n>`) | `CLAUDE.md` as the symlink name |
| Git conventions, `check`, the test harness | the `.claude/` directory structure |

Two things that aren't a clean layer and can't become one: the enforcement
itself is agent-specific (a `PreToolUse` hook exists only by grace of Claude
Code; another agent has a different mechanism or none), and the core isn't
freely portable (`check`, the test harness, and the scripts are bash —
platform-dependent, not agent-dependent).

`#55` also specified AC4 (an ongoing `check` test that guards the left
column against `.claude/`, `SKILL.md`, and hook-name references) and AC5 (a
one-time measurement of what still works without `.claude/`). Both are
**deliberately deferred**: they defend against a claim nobody is making yet —
the front page that could make that claim (W35, #59) doesn't exist yet.
Building against a promise that doesn't exist is the same speculation level
b/c already rejected (rule-of-three, see above). Trigger to build them after
all: as soon as W35 makes an agent-neutrality claim to the outside world.

**Front page order (W29 decision 4, W35/#59).** Not "which reader is
primary" but which question gets answered first: functional framing above
the fold (what problem, for whom, what does it cost), then a
self-contained developer section complete on its own for installing, with
no need to have read the rest. Full reasoning: `CHANGELOG.md`, "Decided in
W29 (#53)", decision 4.

### Maintainability

Strongly relevant — largely what this release is about. F3 removes the
parser and predicate duplication, F4 the NFR duplication, F5 the growing
reading burden. New burden added: a `skills/` tree, an `nfr/` registry with a
generator, a test harness, and a third script. Net positive, not free.

### Testability

Strongly relevant, and currently the biggest gap: **zero** tests for fourteen
specified scenarios. Design requirement that follows from that: both scripts
must make their input injectable. `pending-changes.sh` is nearly there;
`adopt.sh` pulls everything from globals and requires `.git`, so fixtures
must be `git init`'d.

### Usability

Relevant. The user is TiesL plus the agent. The concrete failure mode is
already in the PR #6 review: seventeen rows of homework per new project,
generically answered in one stroke. F6 makes that visible and decides it:
substantiate in phases, secured by three gates.

### Cost control

Relevant, in tokens. `WORKFLOW.md` loads in full in every session of every
project. Roughly 45% is conditionally relevant. Skill descriptions cost a
few hundred tokens once per session; the body only on invocation.
Measurement point: lines in `CLAUDE.md` before/after, to be reported in F12's PR.

### Documentation

Relevant. `README.md` is demonstrably outdated (F16) and needs rows for
`skills/`, `hooks/`, `lib/`, `nfr/`, `test/`, `check`, and
`CHANGES-ARCHIEF.md`, plus an explanation of why skills are symlinked but
templates are copied. Every skill carries its own explanation; the core
explicitly points to it, so R7 keeps holding.

---

## Reusable design principles

Distilled from executing epic #11 — the full work-item schedule and the
ordering decisions live in `CHANGELOG.md`; these are the principles future
epics still apply, detached from the execution history in which they arose.

- **Installer before reference.** A symlink or scaffold that points
  somewhere must already exist before anything else points to it — otherwise
  an early `git pull` points at something installed nowhere.
- **Deduplicate before extending.** Don't add a third consumer to
  duplicated logic; remove the duplication first, or you multiply the
  problem instead of solving it.
- **Bundle similar `CHANGES.md` additions.** Work items that each add a new
  adoption question land close together, so adopted projects get one batch
  of questions instead of a drip across multiple sessions.
- **Extra verification round for irreversibility, writing into other
  people's repos, or meaning loss that `grep` can't see.** Such changes
  deserve a separate, manual check on top of `./check` — a false positive or
  a silent substantive error there doesn't hit one session, but immediately
  every adopted project.

---

## Out of scope

- **The end-to-end run-through itself.** Still needed, still has no issue,
  epic, or owner — it only exists as a sentence in two other issues.
  Recommendation: turn it into a real issue, with `a2t-emails` PR #10 as the
  most likely vehicle (the only one that already has issues #3–#8 open).
- **Retroactive traceability** over 27 issueless PRs.
- **Moving the twelve non-NFR entries into `nfr/`** — no second consumer, so
  no duplication problem.
- **Adopting `mattpocock/skills`' grilling/to-spec template.** The grilling
  *technique* as a method for filling in NFR sections remains a separate
  exploration. *(Revised: the `grilling` technique itself was adopted as a
  real skill, issue #291 — but for general requirement elicitation, not
  this specific NFR-section-filling template use case, which stays
  unexplored.)*
- **A pinnable version for consumers.** *(Revised: picked up after all in
  W37 (#79), see `CHANGELOG.md`, "Decided in W29 (#53)", decision 5 — this
  exclusion held for epic #11, no longer for epic #52.)*

---

## Known limitations

- Skills provide no enforcement; a hook can only point to one.
- The guardrails hook is machine-local: a new machine without an `adopt.sh`
  run doesn't have it. The same applies to the git hooks from F17 — those
  don't travel with a clone.
- Server-side branch protection isn't available: GitHub requires a paid plan
  for that on a private repo. W27 is therefore after-the-fact detection, not
  prevention; the command has already run by then.
- Models share training data, so `pre-merge-review` too raises the floor
  without ruling out blind spots — that caveat is already in the
  `pre-merge-review` skill.
- Bash 3.2 constrains the scripting idiom.
- F13's link-integrity check verifies *that* a `Covers:` reference resolves,
  not whether the target makes sense. A reference to an open point that
  appears as a heading in the PRD — tennis-admin's `OP5` — succeeds.
  Deliberately accepted in W17 (#29): every alternative breaks the check in
  two of the four projects or requires per-project configuration that goes
  stale.
- The same check assumes an ID token appears as a heading in at most one of
  the two scanned files. If the same token is a heading in both `PRD.md` and
  `TEST-SCENARIOS.md`, it's no longer possible to tell which direction a
  `Covers:` reference points. None of the four projects has that overlap now;
  the design doesn't guard against it.

---

## Technical debt

| What | Why acceptable for now | Trigger to address |
|---|---|---|
| Traceability mechanism (F13, W17-W20) designed without practical proof | Deliberately overruled; W17 replaces proof with human review | Once the first real work item runs the chain |
| `model-record-gate.sh` orders issue-comments before the PR's own description and comments when building `all_text` for the same-model check — a heuristic match to the typical stage lifecycle, not a true global timestamp sort. A marker posted out of the typical order (e.g. a stray Review-stage marker landing on the issue after the PR's own) could still be picked up by `tail -1` instead of the PR's genuinely latest one. Found during PR #253's pre-merge-review (round 2), which also found and fixed the prior, more common inversion (issue text ordered last) | `gh`'s comment JSON carries `createdAt`, but nothing here reads it yet; the heuristic reorder covers the failure mode actually seen in practice | If a real review is affected by out-of-typical-order markers, or once the gate is worth extending to sort by actual timestamp across all three sources |
| Short model aliases (`opus`) and their full ids (`claude-opus-5`) normalize as different models, so the same-model effort check (F39, #392) is skipped for a Review recorded under an alias; gate 2 reports `unverifiable-from-artifacts`, never a pass, and `model-record-gate.sh` raises no effort finding. About 31 historical markers use aliases | `normalize_model` is deliberately generic (no model table, so a new model version needs no code change); the documentation names the full id as the platform reports it; the case is a missed check, not a false pass | If aliased markers keep appearing in new PRs, or a stable alias-to-id source exists |
| The shared marker parser (`lib/model-record.sh`, F39, #392) is slow on huge input under macOS awk (BWK), whose `substr` costs time proportional to the whole text: before round 3 of the PR #397 review a single 1 MB quoted value took about 20 s; the parser now jumps over a quoted value with `index()` (1 MB: 0.15 s), but about 500 KB of unquoted words inside one marker still takes about 20 s (mawk: 0.2 s). Correctness is unaffected | No real marker comes near this size (a `floor-basis` is one sentence); the cost is time, never a wrong answer, and fixing it means restructuring the parser around `match()`/`split()` for one platform's awk | A real comment makes a gate or `role-label-staleness.sh` noticeably slow, or a marker-scanning caller starts reading untrusted bulk text |
| The `effort` in a `model-record` marker is self-reported: nothing verifies it unless the platform set it, and the dispatch tool has no effort argument (A25), so a dispatched role's honest value is `unknown`. The gate and the collector compare efforts as recorded (F39); a wrong but well-formed effort passes | No platform reports the effort a session runs at in a form a script can read; `model-choice` says so and makes `unknown` the documented honest value, so a comparison is only as good as the record | The platform exposes the effort a session or dispatch actually ran at, or a dispatch tool gains an effort argument |
| `templates/PRD.md` becomes a build artifact | Price for removing the NFR duplication; `check` guards it | If the generator costs more than it saves |
| Link 2 (scenario → issue) stays without a hard block | The `pre-merge-review` gate covers it; only link 3 also runs in CI | If scenarios structurally end up without an issue |
| Skills bind this repo to Claude Code | Deliberately bounded, level a — see "Boundary between the core and agent tooling (W31, #55)" under *Portability*; AC4/AC5 from #55 are deliberately deferred until W35 makes a neutrality claim | On switching to a different agent, or once W35 (#59) makes a claim that then needs AC4/AC5 |
| `templates/ci.yml` is npm-only despite "platform-neutral" | Pre-existing; all adopters are npm or have no CI | First adopter on a different stack |
| Four projects have ~24 of 27 changes unanswered | Tables predate PR #6 | W7 makes it visible; F6's three gates bring it in gradually |
| Projects that scaffolded with the old `templates/ci.yml` keep their weaker CI | The `ci-on-pr-and-main` entry asks the question but doesn't answer it; until then the weaker workflow stays | Once a project answers the question — the session-start notice keeps it visible |
| `pre-merge-review`'s `scope.sh` falls back to `nfr/*.md`'s (still-Dutch) heading names for this repo's own NFR rows, now mismatched against this file's translated section headings (no `<!-- nfr: id -->` anchors exist in this hand-authored `PRD.md`, so the fallback was always active) | `scope.sh` degrades to a stderr warning rather than blocking (S27); the printed names are cosmetically stale, not incorrect data | Once `nfr/*.md` is translated via its own frozen-baseline refresh procedure (`LEESMIJ.md`) — separate from this translation effort since editing `nfr/*.md` directly breaks S66's freeze invariant |
| `pending-changes.sh` (W42/#114) embeds ~75 lines of network-mutating, `gh`-calling logic (the old-format migration notice and tracking-issue creation) inside a script whose module comment otherwise promises "no network, no mutation" | The exception is honestly documented and pinned to an explicit `-R <host>/<owner>/<repo>` derived from the project's own remote — found and reviewed by Opus (two review rounds) during pre-merge-review of PR #127 | If this logic grows further, or if another mutating exception is added — pulling it into its own script the `SessionStart` hook calls alongside `pending-changes.sh` would keep the no-mutation contract intact, make the mutating path independently testable, and self-delete once every project has migrated |
| Most `test/lib.sh` helpers that call `pending-changes.sh` (`pending_ids()` and its callers — s71, s72, r3, r4, r6, r8, r9, s8, s36, and others) run it on the plain, un-isolated `PATH`, relying entirely on sandboxed projects never having a `github.com` origin remote to keep `gh` unreachable. Found during PR #127's pre-merge-review (round 2, N3) | Correct today because the source-level fix (no origin → no `gh` call at all) carries the load; not defense in depth | If a future fixture or helper ever gives a sandboxed project a real `github.com`-shaped remote, add a refusing fake `gh` on `PATH` by default in `check`/`test/lib.sh`'s `sandbox_create()`, so no test can reach a real `gh` regardless of what any individual test sets up |
| Other `gh` call sites in this repo (`skills/pre-merge-review/scenario-gate.sh`'s `gh issue list`, `hooks/git-guardrails`'s `gh pr view`/`gh pr checks`) rely on `gh`'s own cwd/`GH_REPO`/`GH_HOST`-based repo detection, unlike `pending-changes.sh`'s W42 fix — found during PR #127's pre-merge-review (round 2, N4) | All are read-only (no wrong-repo *write* risk, only wrong-repo *evidence* — e.g. link 2 reading another repo's `**Covers:**` fields); pre-existing, not introduced by W42 | If any of these gains a mutating capability, or if wrong-repo evidence-reading becomes a real incident, pin `-R <host>/<owner>/<repo>` there too, the same way |
| `test/run.sh`'s per-test `mktemp -d` (its own sentinel, and every test's own `sandbox_create`) is unchecked — a failure there is silently treated as an empty/missing directory rather than a loud error. Pre-existing pattern, but issue #216/PR #217 multiplied the number of concurrent `mktemp -d` calls (one sentinel per worker instead of one per whole run), raising the exposure — found during PR #217's pre-merge-review | `mktemp -d` failing on a CI runner or a developer machine is rare enough, and the blast radius (one test's sentinel silently empty) is small; not worth blocking a test-infra PR over | If a test ever starts failing in a way that traces back to a missing/wrong sentinel directory rather than the test's own logic |
| `test/run.sh`'s `TEST_JOBS`/core-count validation (non-numeric, zero, negative, `xargs -P 0` meaning unlimited) has no regression test of its own — verified manually during PR #217's development, not covered by an automated case | The logic is small and was exercised by hand across several values before merge; this is test-infrastructure testing itself, where the value of a dedicated meta-test is lower than for the checks it runs — found during PR #217's pre-merge-review | If this validation logic changes again, or if a regression in it ever actually reaches CI unnoticed |
| The gitleaks CI backstop (#264, both `.github/workflows/ci.yml` and `templates/ci.yml`) re-downloads the pinned gitleaks release tarball on every run instead of caching it — found during PR #270's pre-merge-review | Cost is low today (one small binary download per run); `spec-cost-management` is in scope but this doesn't move the needle at this repo's CI volume | If CI minutes/cost from this step ever becomes noticeable — switch to `actions/cache` keyed on the pinned version |
| `hooks/pre-push`'s gitleaks scan (#264) has no regression test for a multi-ref push where one ref leaks and another ref's scan errors — the fix that keeps `leak_output`/`error_output` disjoint (PR #270 round 2) was verified by hand-tracing, not by an automated case — found during PR #270's pre-merge-review (round 3) | A multi-ref push is a narrow edge case in practice (most pushes touch one ref); the fix itself is small and was traced against the exact scenario before merge | If a real multi-ref push ever exposes a regression here, or once `test/cases/s145_gitleaks_prepush.sh` is next touched for another reason |
| `epic-auto-close.sh`'s `gh issue list --state all --json number,state,body --limit 5000` still silently truncates past that many issues — an epic could auto-close while an old open sibling outside the fetched window stays unseen. Raised from 1000 in PR #220's review, but not eliminated — found during PR #220's pre-merge-review (round 2) | Not worth paginating for a repo at ~220 issues; 5000 is a wide margin, and the failure mode (an epic closes slightly early) is low-severity and human-correctable, the same way #211 itself was | If this repo's issue count approaches the limit, or any project adopting this mechanism (once it's scaffolded, see F20) starts near it — switch to `gh api --paginate` instead of a single bounded `--limit` |
| F21's `check_stray_closes_guard` trusts the PR's own `closingIssuesReferences` as ground truth for what it *intends* to close — but that field is itself populated by scanning the PR's title/body text for closing keywords, with no understanding of quoting or context. PR #224 (the PR that built F21) demonstrated this directly: its own description quoted the historical incident text `"Closes #218"`, and GitHub added #218 to `closingIssuesReferences` for real, on a PR that had nothing to do with #218 — found live during that PR's own pre-merge-review, before merge, by re-querying its `closingIssuesReferences` after the fix and seeing it (briefly, until cache caught up) still there. Fixed for that specific PR by rewording its description; F21's check has no general defense against the same mistake in a future PR/issue body | This is the same class of bug F21 exists to catch, one layer up (PR body/title instead of commit message) — genuinely hard to guard against mechanically, since a legitimate reference to another issue in prose is indistinguishable from a real closing intent by keyword-matching alone. Rare in practice: it requires prose that both names a closing keyword and an issue number adjacently, which most PR descriptions don't do outside of exactly this repo's own meta-discussions about the mechanism itself | If this recurs on a future PR — especially one *not* about this mechanism, where it would be far less likely to be caught by the author's own awareness of the pattern |
| `check_ci_guard`, `check_stray_closes_guard`, and now `check_merge_guard`'s marker check (`hooks/git-guardrails`) each duplicate the same stdout/stderr-separation boilerplate (a `mktemp` error file, falling back to `2>/dev/null` if `mktemp` itself fails) rather than sharing one helper. Now three call sites — found during PR #224's pre-merge-review (round 3) at two, found again during PR #227's (round 1) at three. An extraction was attempted during PR #227 and reverted the same session after it (indirectly) caused a real incident: see the row below | Extracting a shared helper is still worth doing, but not attempted again casually — the revert wasn't about the extraction's design, it was about the incident it took down with it | Next time this pattern needs touching — with the apostrophe-in-single-quoted-heredoc risk (row below) fixed first, or checked for explicitly, before editing near either python block again |
| Writing prose with an apostrophe (`it's`, `doesn't`, `#227's`) inside a bash *single-quoted* `python3 -c '...'` block silently and catastrophically breaks the script: bash single quotes have no escape mechanism, so the apostrophe ends the string early and everything after is reparsed as bash code — with no error until a syntax mismatch surfaces somewhere later in the file, at an unrelated line. Concretely: a comment reading "found during PR #227's own pre-merge-review" inside `check_merge_guard`'s marker-parsing python block took down `hooks/git-guardrails` entirely — and since this repo adopts itself, every `Bash` tool call in the session broke immediately (the `PreToolUse` hook execs this same file to vet every command), discovered only by working blind through `Read`/`Edit` until the apostrophe was found by manual quote-counting | Caught and fixed within the same session, but only by disabling all git/gh command execution until found — a real, high-blast-radius incident, not a near miss | Add a `check-no-...` script (matching `check-no-sigpipe-race.sh`'s F22 pattern) that scans every `python3 -c '...'`-shaped single-quoted block for a bare apostrophe — tracked as its own issue rather than built under this incident's own time pressure |
| `compliance-evidence.sh`'s `normalize_model()` (F34, issue #296) is a verbatim copy of `skills/pre-merge-review/model-record-gate.sh`'s function of the same name (#268), not a shared import — two copies of the same model-string-comparison logic now exist. Deliberate (D5, Architect's implementation plan): extracting a shared lib would cross the dogfood-only boundary, since `skills/` is what `adopt.sh` propagates to adopted projects and this collector is dogfood-only | A reimplementation that drifted from `model-record-gate.sh`'s comparison rules would make the collector silently disagree with the gate it reports on — worse than the duplication itself; the two are kept in sync by comment (each names the other as origin/copy) | Unify if/when this collector is ever propagated beyond this repo, or if the two copies are ever found to have drifted |
| `compliance-evidence.sh` (F34, issue #308, fixing the #296 debt row this replaces) now discriminates a live marker from the same shape merely quoted in a fenced code block, an inline code span, or a Markdown blockquote — `live_text()` strips those enclosures (by CommonMark's own fence-closing rule: opening char + run length, no info string on a close, 3-space indent cap) before any `gate_*` predicate greps the result, and a real marker inline with prose keeps evidencing (AC3). This is a bounded heuristic, not a full CommonMark parser, and by design (non-goal 1, Product's ruling on D2) it **fails open** — counts as live, not flagged as quoted — for shapes it doesn't attempt: a 4-space-indented (or tab-indented) code block, an HTML `<pre>`/`<code>` block, a marker nested inside another HTML comment, backticks inside a link title, a blockquote's lazy-continuation line, and a backtick-fence opener whose own info string contains a backtick (this last one is the sole fail-*closed* residue — over-stripped, not under-stripped). The same `live_text()` copy also filters `role-label-staleness.sh` and, since #392 (round 5 of the PR #397 review), `model-record-gate.sh`'s stage-presence and Review-floor checks, so the three agree on these shapes (S201 checks the indented case). `test/cases/s151_compliance_evidence_quoting.sh` pins two of these (Q18, Q18b) as accepted debt on purpose, precisely so a later half-fix is a visible, reviewed status change rather than a silent one | Closing every one of these needs a real CommonMark-aware parser, which is out of proportion to a dogfood-only compliance reporter; the fail-open direction is the honest one to ship rather than overclaim full coverage (Product's D2 ruling) | If any of these shapes is ever seen quoted in a real PR/issue in a way that produces a false `evidenced` — delete the corresponding S151 arm (Q18/Q18b) and move this row, rather than leaving the debt undocumented once the gap closes |
| Every caller of `live_text()` (`compliance-evidence.sh`, `role-label-staleness.sh`) captures its output without checking awk's own exit status — an awk failure (a future regex-engine defect on some other awk build, say) would turn a body into `''` and produce a confident `not-evidenced`/`stale` verdict, the exact same failure shape issue #319 itself went unnoticed as until someone happened to run the real test suite under mawk. #319's fix removes the two known triggers (the panic, and the two mawk portability defects) but doesn't change this: a *third*, still-undiscovered awk defect would reproduce #319's original symptom precisely. Found during PR #325's own pre-merge-review (round 2) | #319's fix closes every known trigger; propagating awk's exit status through `live_text()` and degrading callers to `indeterminate` on failure (the same discipline `collect()` already applies to a failed `gh` call) is a real fix but a separate, non-trivial one — not worth bundling into #319's own scope | If a future awk defect (a different build, a different bug) reproduces #319's silent-empty-output symptom again — propagate `live_text()`'s exit status and have every caller degrade to `indeterminate` rather than treating empty output as "nothing was there" |
| `compliance-evidence.sh` and `model-record-gate.sh` (F34, issue #318) both append PR review bodies (`pulls/<pr>/reviews`) strictly after every PR comment when building their flat text corpus, not merged in true chronological order. This is harmless when a review genuinely is the newest event (it correctly lands last in append order too) — the real risk is the opposite: a comment posted *after* an existing review is still appended *before* every review in the fixed body→comments→reviews order, so that older review's `model-record` marker can still win under `tail -1` over a comment that's actually newer (e.g. a round-2 comment correcting a round-1 review's recorded model would lose to that stale review). The same class of ordering flaw #253 already fixed once for issue-text-vs-PR-text ordering, now reappearing between two PR-side sources instead of two different bundle sources. Found during PR #336's own pre-merge-review (round 1; the direction was initially misdescribed here and in this file's own code comment, corrected during round 2) | Both scripts' comment JSON and review JSON carry `created_at`/`submitted_at`, but neither script reads it — merging by real timestamp is a bigger, separate change than #318's own REST-transport scope, and reviews are a source neither script read at all before this PR, so this is a new, narrower version of an already-accepted risk class, not a regression this PR introduced from a previously-safe state | The first real PR where a `model-record` marker in a review body is superseded by a later, disagreeing marker in a plain PR comment, and gate 2 (or model-record-gate.sh's own same-model check) gives the stale review's verdict instead — sort PR_TEXT's sources by their own `created_at`/`submitted_at` instead of a fixed body→comments→reviews append order |

---

## Verification

1. **Baseline first.** W3 is green on unmodified `main` before W4 starts.
   Every deviation after that is explicitly explained in the PR — a silent
   change in the question set is never acceptable, not even as "cleanup" (R9).
2. **Red before green per work item.** The covering scenario is added first
   and seen red; the PR shows both states.
3. **R1–R9, T1–T5, and S1–S63** run in `check`, against fixtures, never
   against the real projects.
4. **R7 mechanically and by hand.** The test greps `WORKFLOW.md` for five
   terms and checks that every named skill has a `SKILL.md`. That doesn't
   see meaning loss — so additionally, open a session in `tennis-admin`
   after re-adoption and actually follow every routing-table row.
5. **Prove skill discovery** in a real adopted project before W9–W15.
6. **Running `adopt.sh` twice** produces an identical tree and an identical
   `.gitignore`.
7. **Token measurement**: lines in `CLAUDE.md` before/after, in W9's PR.
8. **`bash -n`** on every changed script — existing convention from all six PRs.
9. **This release applies its own rule**: every PR gets the quality review
   before the merge, with findings in the PR. Zero of the 27 PRs so far did that.

---

## Open questions

1. **Does the end-to-end run-through become a real issue?** The original
   idea was to plan it before W17, so practical proof would replace W17's
   human review. That order is now moot: W17 (#29) is done and the five
   field-format decisions are locked in. The run-through remains valuable,
   but now as a check on whether those decisions hold up in practice — not
   as a replacement for a review that's already happened.
2. **`quality-review-before-merge` has been answered by no project** and no
   PR ever had a review. Should W13 put that entry in front of all four
   projects right away?
3. ~~Generate or assemble?~~ Answered: generate — see `generate-prd-block`
   and F4.

---

## Project files

| File | Purpose |
|---|---|
| `WORKFLOW.md` | The workflow core; symlinked as `CLAUDE.md` in every adopted project |
| `USER-CLAUDE.md` | User-wide trigger instruction; symlinked as `~/.claude/CLAUDE.md` |
| `CHANGES.md` | Adoptable changes (after F4: the twelve non-NFR entries) |
| `CHANGES-ARCHIEF.md` | Retired entries, with ID and reason (F5, new) |
| `nfr/*.md` | Registry of the fifteen NFRs — one source for question, meaning, and fill-in guidance (F4, new) |
| `lib/changes.sh` | Shared parser and predicate logic (F3, new) |
| `adopt.sh` | Installs symlinks, copies, skills, and the adoption table |
| `pending-changes.sh` | Reports outstanding changes and substantiations at session start |
| `check` | Its own test command: syntax, JSON validation, shellcheck, test suite (F1, new) |
| `test/` | Test harness and `fixtures/baseline/` (F1, F2, new) |
| `hooks/` | Guard scripts for the `PreToolUse` hooks (F7, F8, new) |
| `skills/*/SKILL.md` | The skills — count changes as adopted; see `WORKFLOW.md`'s routing table for the current list (F10, new) |
| `settings/session-hooks.json` | Hook configuration; symlinked as `.claude/settings.json` |
| `templates/` | Templates for adopted projects (PRD, test scenarios, architecture, CI, issues) |
| `PRD.md` | This document |
| `TEST-SCENARIOS.md` | The scenarios that cover this document |
| `CHANGELOG.md` | Release history with required actions per release (F15, new) |
