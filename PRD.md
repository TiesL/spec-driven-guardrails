# PRD — claude-workflow, release "From prose to mechanism"

**Status:** As-built for epic #11 (closed, shipped 2026-09-06 — see
`CHANGELOG.md`); "Besloten in W29 (#53)" below steers the ongoing epic #52.

---

## Context

`spec-driven-guardrails` (formerly `claude-workflow`, renamed in W32/#56) is the
shared source of truth for Ties' personal Git/GitHub workflow, adopted by
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
coverage field, and `kwaliteitsreview-voor-merge` has never been answered by
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

**Do not add a `package.json`** just to reuse `templates/ci.yml`: that would
flip this repo's own `heeft-package-json` predicate and change what the
scripts say about this repo. CI calls `./check` directly — exactly the
"different stack" case the `check-convention` skill already describes.

### F2 — Recorded baseline as fixtures

The current outcome for all **four** adopters, frozen in
`test/fixtures/nulmeting/` as golden sets, before anything changes.

A manual dry run against copies isn't repeatable; freezing it as a fixture
makes R9 a permanent regression test. All four sources live locally —
`tennis-registration` and `tennis-invoicing` as full-fledged git repos (own
`.git`, own remote, own `WORKFLOW-ADOPTIE.md`) nested inside `tennis-admin/`.

`a2t-emails` is the fourth and has **no** `WORKFLOW-ADOPTIE.md` at all. Its
baseline is therefore "everything outstanding" — record it as found, don't fix
it first, or the fixture would capture the fix instead of the actual state.

**W28:** the question set has come from two sources since W5, `CHANGES.md` and
`nfr/`, and until W28 only the first was frozen (`CHANGES.md.momentopname`).
`nfr.momentopname/` (a verbatim copy of `nfr/`, a single `cp -r`) closes that
gap — see `test/fixtures/nulmeting/LEESMIJ.md`.

### F3 — Shared parser and predicates (`lib/changes.sh`)

It's not just the predicates that are duplicated — the entire `CHANGES.md`
parser is too (`## ` headings, `${regel##*\*\* }`, the `case` skeletons). Both move.

```
predicaat_waar <predicaat> <project_dir>   # the sole predicate logic
itereer_entries <bron> <callback>          # callback <id> <standaard> <predicaat>
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
nfr/spec-data-integriteit.md
…  (fifteen files)
```

Each file carries everything known about that one NFR:

```markdown
---
id: spec-security
kop: Security
standaard: ja
van-toepassing-als: altijd
productie-poort: ja
status: actief
---

## Vraag
Is Security relevant genoeg voor dit project om te specificeren (toegang,
autorisatie, secrets)?

## Ja betekent
`PRD.md` beantwoordt de subsectie "Security" — wie mag wat, welke rechten zijn
minimaal nodig, waar staan secrets.

## Invulhulp
Wie mag wat? Welke rechten zijn minimaal nodig? Waar staan secrets, en hoe komen
ze niet in git terecht?
```

What this eliminates:

- **The naming problem gets solved instead of managed.** `id` and `kop` live
  in the same file, so `spec-compliance` ↔ "Compliance en auditeerbaarheid"
  needs no normalization, no stopword rule, no alias table.
- **`CHANGES.md` shrinks from 27 to 12 entries.** The scripts iterate
  `CHANGES.md` and `nfr/*.md`. That serves the growing reading burden more
  directly than the archive alone: fifteen of the twenty-seven entries leave
  the file every project walks through every session.
- **Retirement becomes a field** (`status: geretireerd`) instead of a file
  move, for these fifteen.

The `productie-poort` field carries F6's second gate: which NFRs must be
substantiated before the first production rollout is now a recorded decision
instead of a list in a script.

**`templates/PRD.md` is generated** — only the NFR block, from `kop` +
`Invulhulp`, with the `id` as an HTML comment inside it. `check` fails if the
checked-in block doesn't match what the generator produces. The PRD becoming
a build artifact is the price; it's worth it because the generator also
plants the anchor F11 leans on.

**Only the fifteen NFRs move.** The remaining twelve entries (`proces-*`,
`test-*`, `ci-conventie`, `deploy-guards`) have no second consumer and
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
outstanding while all seventeen seeded rows still carry "vereist onderbouwing."

**Don't change `beantwoord()`.** That would change the outstanding set and
thereby break R9 — the release's most important regression test. Instead, a
**second, separate notice**:

```
17 rij(en) in WORKFLOW-ADOPTIE.md wachten nog op onderbouwing.
Volg de skill `adoption-registry`.
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

1. **Per PR** — if a PR touches a topic whose row still says "vereist
   onderbouwing," that's a review finding in `pre-merge-review`, and the row
   gets answered before the merge (F11).
2. **Before the first production deploy** — the deploy guards require that no
   row with `productie-poort: ja` still says "vereist onderbouwing" (F4).
3. **Every session** — the signal above stays; phased doesn't mean invisible.

Touched → answered on that PR; never touched but critical → by the first
production rollout at the latest; the rest → visible until you get to it.

### F7 — Git guardrails as a `PreToolUse` hook

Blocks `reset --hard`, `clean -f[d]`, `branch -D`, `checkout .`/`restore .`,
`commit` **on `main`**, and `push` **to `main`**.

**Blocking `commit` on `main` is a deliberate extension**, added at Ties'
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
loop: a command Ties types himself in his terminal never passes through it.
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
checks is not a red flag, CI is optional, see F6); a substantiated `nee` row
for `kwaliteitsreview-voor-merge` in `WORKFLOW-ADOPTIE.md` disables both
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
`kwaliteitsreview-voor-merge` next to those reads like an accident. Everything
Ties reads and maintains stays Dutch.

| Skill | Invocation | What goes in it |
|---|---|---|
| `pre-merge-review` | model + user | "Quality review before the merge" (40 lines) + scoping + F13's PR gate |
| `deploy-guards` | model | Deploy conditions per environment (~52 lines) + F6's production gate |
| `check-convention` | model | `check`/`deploy` naming convention + CI (~22 lines) |
| `adoption-registry` | model | Adoption registry (35) + substantiation requirement (15) + the protocol from `USER-CLAUDE.md` |
| `write-spec` | model + user | Specifying work + `Dekt:` convention + `CONTEXT.md` glossary |
| `refactoring-triggers` | model | Complexity/debt/refactoring (32 lines) |
| `tdd-seams` | model + user | New: seams, red-before-green, three anti-patterns |
| `diagnose-bug` | model | New: reproduction → hypotheses → regression test before fix |
| `adopt-workflow` | **user-level** | Adoption question + setting up a new project |

**Three choices that deserve explanation:**

*The substantiation requirement goes to `adoption-registry`, not `write-spec`.*
It currently sits under "Specifying work," but it's actually about answering
`WORKFLOW-ADOPTIE.md` rows — the same subject as the registry section, which
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
`write-spec`. Nine skills is already the limit of what stays coherent.

### F11 — `pre-merge-review` as an executable skill

The strongest post. `WORKFLOW.md` *asks in prose* for a review "with fresh
context and on a different model." Frontmatter expresses that literally:
`context: fork` gives the fresh, isolated context, `model:` pins a
different/heavier model, `allowed-tools` keeps it read-only.

The skill reads `WORKFLOW-ADOPTIE.md` → `ja`-answered `spec-*` → the anchor in
the project PRD → the review scope. Reading the diff itself is delegated to
the existing `code-review` skill; this skill owns the *scoping*, the
context/model requirement, and the "findings in the PR, then resolved or
filed under Technical debt" step.

Two additions from the merge-guard and substantiation decisions: the skill
places a **machine-recognizable marker** in its findings comment (which F8
keys on), and it treats a touched topic whose `WORKFLOW-ADOPTIE.md` row still
says "vereist onderbouwing" as a review finding — that row gets answered
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

**Decided in W17 (#29)**, the design review with Ties that replaces the "one
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
collision is sharper than it looks at first glance: `templates/ARCHITECTUUR.md`
uses `A1` for architecture requirements, and tennis-admin has 24 `A<n>`
scenarios. If tennis-admin scaffolded that template, `A1` would mean two
things within one project — not a collision between projects, but within one.
Verified: `AC` doesn't occur in any of the four projects.

**b. One field name, `**Dekt:**`**, in both directions; the token's prefix
says which link it is. Strict: start of line, comma-separated tokens
matching `^[A-Z]{1,2}[0-9]+[a-z]?$`. Both quantifiers come from reality, not
taste. The `[a-z]?` is there for `a2t-emails`' `S2b`; the `{1,2}` for
tennis-admin's `OP<n>` — that project uses `OP` for open points in both
`PRD.md` and `ARCHITECTUUR.md`, and `O<n>` for weighed architecture options.
A grammar that rejects either one is unusable on day one in one of the four
projects. Only the field counts; that prevents false positives by construction.

**c. Don't hardcode `F`/`S` — check link integrity instead.** Collect the ID
tokens from the headings of `PRD.md` and `TEST-SCENARIOS.md`, and check that
every `Dekt:` token resolves in the other set. This makes tennis-admin's
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
`ARCHITECTUUR.md` and therefore aren't collected. `Dekt: O2` therefore
correctly fails to resolve and gets reported. This problem can only occur for
things that live in the two scanned files.

That's deliberately accepted in W17. A reference to a wrong-but-existing
target is a documentation error a human catches in review; a hardcoded
`F`/`S` list makes the check useless in two of the four projects. Three
alternatives were weighed and rejected, on the same ground each time — they
require per-project configuration that silently goes stale:

- **Per-prefix exclusion list.** Goes stale the moment a project starts using
  a new prefix.
- **Filter by file.** Excludes `ARCHITECTUUR.md`, but decision c already does
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
Ties' own use: W37 (#79) builds a pinnable consumer path on top of this tag
mechanism, see "Besloten in W29 (#53)", decision 5. This — following `main`
live via symlink — remains Ties' own model.)* The first CHANGELOG entry
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
call executes" and names no other hook point; commands Ties types himself in
his terminal are not a tool call and therefore never pass through it. That's
an inference from the documented scope, not a warning the documentation
itself gives — but it's conclusive: there simply is no mechanism by which
those commands would reach the hook. The same `git reset --hard` in Ties'
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
  `CHANGES.md` entry (`ci-op-pr-en-main`, `heeft-package-json`): existing
  projects would otherwise keep their weaker CI without anyone asking. That
  entry is separate from `ci-conventie` — that answer covers *what* the
  workflow does, this one covers *when* it runs.
- **Git hooks in the project** (W26). A `pre-commit` and `pre-push` hook
  cover every tool on that machine. They reuse the decision logic from
  `hooks/git-guardrails`. Note what's actually reusable: a native
  `pre-commit` receives no command string, so the quote-aware tokenization
  from `lees-commando.py` is `PreToolUse`-specific by definition. What can be
  shared is the *rules* — which branch is protected, what the message says,
  which way out it names. That's narrower than "reuse the script," and W26
  must make that distinction explicit instead of assuming a simple reuse
  exercise. Limitation: git hooks are machine-local and don't travel with a
  clone, so a new machine only has them after `adopt.sh`. That's the same
  limitation as the existing hooks, and F6's outdated-adoption notice makes
  it visible.
- **CI detects commits on `main` that don't come from a PR** (W27). This is
  detection rather than prevention — the command has already run by then —
  but it's the only mechanism that works on every machine with every tool.
  The check only judges the incoming push, not the history: a retrofit that's
  red from day one teaches you to ignore the message.

The three layers are deliberately not interchangeable. W24 and W26 prevent,
W27 catches what slips through.

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

---

## Non-functional characteristics

### Security

Relevant, limited. The guardrails hook (F7) is itself a security measure.
`check-traceability.sh` parses issue and PR text — input that isn't fully
under this repo's own control — so no `eval`, just as the predicates are
deliberately a `case`. No secrets in this repo.

### Data integrity

Strongly relevant. `WORKFLOW-ADOPTIE.md` is the durable record of decisions
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
archived entry must remain findable from a `WORKFLOW-ADOPTIE.md` that points
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
exists, without building an adapter layer or contract (see "Besloten in W29
(#53)", decision 2).

| Agent-independent | Claude Code-specific |
|---|---|
| Templates (`PRD.md`, `TEST-SCENARIOS.md`, `ARCHITECTUUR.md`) | `settings/session-hooks.json` |
| Adoption registry (`CHANGES.md`, `WORKFLOW-ADOPTIE.md`) | `hooks/` (`PreToolUse`, `SessionStart`, `SessionEnd`) |
| The `nfr/` registry | `skills/` |
| Traceability (`Dekt:`, `AC<n>`) | `CLAUDE.md` as the symlink name |
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

Relevant. The user is Ties plus the agent. The concrete failure mode is
already in the PR #6 review: seventeen rows of homework per new project,
generically answered in one stroke. F6 makes that visible and decides it:
substantiate in phases, secured by three gates.

### Cost management

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
  exploration.
- **A pinnable version for consumers.** *(Revised: picked up after all in
  W37 (#79), see "Besloten in W29 (#53)", decision 5 — this exclusion held
  for epic #11, no longer for epic #52.)*

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
- F13's link-integrity check verifies *that* a `Dekt:` reference resolves,
  not whether the target makes sense. A reference to an open point that
  appears as a heading in the PRD — tennis-admin's `OP5` — succeeds.
  Deliberately accepted in W17 (#29): every alternative breaks the check in
  two of the four projects or requires per-project configuration that goes
  stale.
- The same check assumes an ID token appears as a heading in at most one of
  the two scanned files. If the same token is a heading in both `PRD.md` and
  `TEST-SCENARIOS.md`, it's no longer possible to tell which direction a
  `Dekt:` reference points. None of the four projects has that overlap now;
  the design doesn't guard against it.

---

## Technical debt

| What | Why acceptable for now | Trigger to address |
|---|---|---|
| Traceability mechanism (F13, W17-W20) designed without practical proof | Deliberately overruled; W17 replaces proof with human review | Once the first real work item runs the chain |
| `templates/PRD.md` becomes a build artifact | Price for removing the NFR duplication; `check` guards it | If the generator costs more than it saves |
| Link 2 (scenario → issue) stays without a hard block | The `pre-merge-review` gate covers it; only link 3 also runs in CI | If scenarios structurally end up without an issue |
| Skills bind this repo to Claude Code | Deliberately bounded, level a — see "Boundary between the core and agent tooling (W31, #55)" under *Portability*; AC4/AC5 from #55 are deliberately deferred until W35 makes a neutrality claim | On switching to a different agent, or once W35 (#59) makes a claim that then needs AC4/AC5 |
| `templates/ci.yml` is npm-only despite "platform-neutral" | Pre-existing; all adopters are npm or have no CI | First adopter on a different stack |
| Four projects have ~24 of 27 changes unanswered | Tables predate PR #6 | W7 makes it visible; F6's three gates bring it in gradually |
| Projects that scaffolded with the old `templates/ci.yml` keep their weaker CI | The `ci-op-pr-en-main` entry asks the question but doesn't answer it; until then the weaker workflow stays | Once a project answers the question — the session-start notice keeps it visible |
| `check-traceability.sh` is an unused root copy of `templates/check-traceability.sh` | Self-adoption (#98) scaffolds it like any project; this repo already handles traceability differently (T1/T2 run `templates/check-traceability.sh` directly against this repo) — an exception for it in `adopt.sh` would break #98's "no special case" principle | Once `templates/check-traceability.sh` changes without anyone noticing the root copy needs to follow (no test guards drift between the two), or if a reader mistakes the root copy for the source |
| `pre-merge-review`'s `scope.sh` falls back to `nfr/*.md`'s (still-Dutch) heading names for this repo's own NFR rows, now mismatched against this file's translated section headings (no `<!-- nfr: id -->` anchors exist in this hand-authored `PRD.md`, so the fallback was always active) | `scope.sh` degrades to a stderr warning rather than blocking (S27); the printed names are cosmetically stale, not incorrect data | Once `nfr/*.md` is translated via its own frozen-baseline refresh procedure (`LEESMIJ.md`) — separate from this translation effort since editing `nfr/*.md` directly breaks S66's freeze invariant |

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
2. **`kwaliteitsreview-voor-merge` has been answered by no project** and no
   PR ever had a review. Should W13 put that entry in front of all four
   projects right away?
3. ~~Generate or assemble?~~ Answered: generate — see `genereer-prd-blok`
   and F4.

---

## Besloten in W29 (#53)

Ontwerpsessie met Ties, geen code (AC3 van dat werkitem) — vier beslissingen die
epic #52 sturen, elk met redenering. Vervolgitems die hierop anticipeerden zijn
bijgewerkt: W31 (#55), W32 (#56), W33 (#57), W35 (#59) en epic #52 zelf.

**Herzien na een onafhankelijke second opinion** (een vers model, zonder de
context van de ontwerpsessie zelf, gevraagd om puur de inhoud van de vier
besluiten te bekritiseren — niet de tekst). Die review vond een harde naam-
botsing en drie onderbouwingen die de juiste uitkomst hadden met een zwakke
reden. Alle vier zijn hierop aangepast; besluit 5 is nieuw en volgt uit een
gat dat de review blootlegde.

### 1. De naam: `spec-driven-guardrails`

**Herzien.** De oorspronkelijke werktitel `agentic-SDD-workflow` bleek bij
extern zoekwerk **de eigen term van GitHub's Spec Kit** te zijn voor zijn
methodiek ("Agentic SDD"). Voor de doelgroep die dit veld kent, leest die naam
als een derivaat van Spec Kit, niet als iets zelfstandigs — en het veld is
sowieso al vol vergelijkbare namen (`cc-sdd`, `agentic-sdlc-spec-kit`,
`specky`). Voor een release waarvan het hele doel deelbaarheid is, is dat geen
detail.

`spec-driven-guardrails` — het eerder overwogen en afgevallen alternatief —
botst nergens mee en legt de nadruk op wat dit project onderscheidt van een
willekeurige SDD-aanpak: **de afdwinging**, niet nóg een spec-generator. Het
vermijdt ook het acroniem dat botste met besluit 4's doelgroep. Consequent
kleine letters (geen gemengde casing) — wordt een mapnaam, een repo-URL en de
basis van een omgevingsvariabele, en gemengde casing is daar een bekende bron
van cross-platform ellende.

### 2. Provider-agnostisch: niveau a — alleen benoemen

Van de drie niveaus (a: benoemen, b: adapterlaag met één invulling, c: een
tweede invulling erbij bouwen) is gekozen voor **a**. De grens tussen
agent-onafhankelijk en Claude Code-specifiek (zie W31/#55) wordt gedocumenteerd,
niet gebouwd als contract.

**Onderbouwing herzien.** De oorspronkelijke reden ("een contract zonder
tweede invulling blijft een aanname") bewijst te veel — met die redenering is
geen enkele abstractie ooit gerechtvaardigd vóór haar tweede consument. De
werkelijke reden is een rule-of-three: er is geen tweede agent in zicht en geen
concrete vrager, dus is een contract nu speculatief. De sterkste reden stond er
al, maar op de tweede plaats: epic #52's eigen grens ("geen nieuwe
functionaliteit").

**Het risico dat wél reëel is:** na deze release presenteert het product zich
naar buiten als neutraal (nieuwe naam, voorpagina voor een niet-technische
lezer), terwijl het 100% aan Claude Code vastzit — hooks, skills,
`.claude/settings.json`. Dat is geen technische schuld maar een belofte-schuld,
die je aan precies de nieuwe lezer verkoopt. Om niveau a sterk te maken in
plaats van alleen goedkoop, krijgt W31 (#55) er twee concrete stappen bij: een
`check`-test die de grens afdwingt (niet alleen beschrijft), en een eenmalige
meting van wat er zonder Claude Code daadwerkelijk nog werkt.

De bestaande technical-debt-rij ("Skills bind this repo to Claude Code")
wordt door dít besluit niet gesloten — dat gebeurt pas als W31 de grenstabel
en de twee bovenstaande stappen heeft geleverd, en dan niet als "opgelost"
maar als "bewust begrensd, met een concrete trigger om verder te gaan (niveau
b of c)".

### 3. Taalscope: A + B, via een criterium — niet via een lijst

Dat dit repo zelf — documentatie, hookmeldingen, testnamen, commentaar — Engels
wordt, staat niet ter discussie; dat is W33 (#57)'s hoofdwerk. Waar dit besluit
ook echt over gaat: welke stukken van die vertaling meebewegen in de vier
Nederlandse geadopteerde projecten, waar ze niet zelf vertaald worden.

**Herzien: het criterium vervangt de opsomming.** De oorspronkelijke lijst (twee
items: entry-ID's en `**Dekt:**`/`AC<n>`) bleek bij natrekken onvolledig — de
review vond zelfstandig minstens vijf machinaal gematchte Nederlandse tokens
die er niet in stonden (de bestandsnaam `WORKFLOW-ADOPTIE.md` zelf, de
`ja`/`nee`-antwoordwaarden, de stempel "vereist onderbouwing", de
`.gitignore`-beheerde-blokmarkering, en de issue-templates die sowieso al bij
elke `adopt.sh`-run ververst worden). Een hand-onderhouden lijst heeft precies
de faalmodus die dit besluit zegt te bestrijden: iets wordt gemist en zakt
stilzwijgend weg.

Het achterliggende, wél houdbare criterium:

> **Migreert mee: elke letterlijke string die een script uit dit repo matcht in
> een bestand van een ander repo.**

Dat is laag **A** (fysiek gedeelde bestanden — symlinks: `CLAUDE.md`,
`WORKFLOW.md`, `skills/*/SKILL.md`, `session-hooks.json`) plus laag **B**
(gedeelde vocabulaire die als los token in andermans bestand staat, en die een
script van dit repo terugleest). W33 (#57) genereert de volledige inventaris
van laag B door de scripts zelf te doorzoeken op wat ze in andermans bestanden
matchen, in plaats van de lijst hier met de hand te proberen compleet te
krijgen.

Expliciet buiten scope blijft een derde laag, **C — gescaffolde documentkoppen
en scriptoutput** (bijv. `check-traceability.sh`'s eigen meldingen ín de vier
projecten) die na het scaffolden lokaal eigendom zijn geworden van die
projecten, en die geen enkel script van dit repo terugleest. Die migreert niet
mee. Nieuw gescaffolde kopieën, voor toekomstige projecten, zijn wél Engels — de
bronsjablonen in `templates/` maken deel uit van dit repo en gaan dus mee.

Overwogen en niet gekozen: backwards-compatibele parsers (bijv. `Dekt:` én
`Covers:` allebei laten werken, met een overgangswaarschuwing) in plaats van
een migratie ineens. Dat zou de cross-repo-mutatie vermijden, maar is niet
gekozen omdat het de dubbele-taal-periode zonder einddatum in stand houdt —
precies wat dit repo elders (zie R9, de nulmeting) probeert te voorkomen.

### 4. Voorpagina: welke vraag wordt eerst beantwoord — niet welke lezer is primair

**Herzien.** "De functionele lezer is primair" bleek twee gaten te hebben: de
oorspronkelijke onderbouwing ("de ontwikkelaar vindt zijn weg via
`WORKFLOW.md`") is insiderlogica — dat bestand is een agent-instructietekst,
geen installatiehandleiding, en dus geen wegwijzer voor een echte
buitenstaander. Belangrijker: de functionele lezer kan de eerste installatiestap
(clonen, omgevingsvariabele zetten, een bash-script draaien, Claude Code
hebben) sowieso niet zelf zetten — een voorpagina geoptimaliseerd voor iemand
die er niet naar kan handelen, converteert niets.

De vraag wordt daarom niet "welke lezer is primair", maar **welke vraag wordt
als eerste beantwoord**: functionele framing boven de vouw (welk probleem, voor
wie, wat kost het — business analisten, product owners en product managers
lezen dat eerst), gevolgd door een zelfstandige ontwikkelaarssectie die op
zichzelf compleet is om te installeren, zonder de rest gelezen te hoeven
hebben. W35 (#59) krijgt hiervoor een extra acceptatiecriterium: een
ontwikkelaar die het repo nooit zag, installeert het uitsluitend vanuit de
`README.md`.

### 5. Installatie- en updatemodel: getagde, pinbare release

**Nieuw, uit de second opinion.** Geen van de vier oorspronkelijke besluiten
beantwoordde wat "installeren" betekent voor iemand die niet Ties is. Het
huidige model — los checkout, een omgevingsvariabele, `adopt.sh` — is een model
voor één persoon op meerdere machines, niet voor een consument die niet main
wil volgen. Dit document sloot "a pinnable version for consumers" voorheen
expliciet uit (zie "Out of scope" hierboven, en F15's "a tag is a human
reference point, not a pinnable version" — beide bijgewerkt met een
verwijzing hierheen), wat de belofte van deze release (deelbaarheid)
tegensprak.

Besloten: consumenten pinnen een **getagde release** (bouwend op W22/#35's
bestaande tag-/CHANGELOG-mechanisme uit epic #11 — F15 beschreef dat mechanisme
correct voor Ties' eigen live-via-symlink-gebruik; W37 bouwt er een tweede,
pinbaar pad bovenop, geen vervanging); het losse-checkout-plus-env-var-model
blijft daarnaast bestaan voor Ties' eigen multi-machine-gebruik. Uitgewerkt als
nieuw werkitem: **W37 (#79)**.

Aanvullend besloten: `CHANGES.md` wordt gelezen als **productdefaults**, niet
als Ties' persoonlijke voorkeurenregister. Elke entry krijgt daarmee impliciet
een verdedigbare default voor een nieuwe adopter; Ties' eigen antwoorden in de
vier bestaande projecten blijven staan als voorbeeld, niet als voorschrift.
Ook uitgewerkt in W37 (#79) — die tekst in `CHANGES.md`'s inleiding wijzigt
mee.

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
| `test/` | Test harness and `fixtures/nulmeting/` (F1, F2, new) |
| `hooks/` | Guard scripts for the `PreToolUse` hooks (F7, F8, new) |
| `skills/*/SKILL.md` | The nine skills (F10, new) |
| `settings/session-hooks.json` | Hook configuration; symlinked as `.claude/settings.json` |
| `templates/` | Templates for adopted projects (PRD, test scenarios, architecture, CI, issues) |
| `PRD.md` | This document |
| `TEST-SCENARIOS.md` | The scenarios that cover this document |
| `CHANGELOG.md` | Release history with required actions per release (F15, new) |
