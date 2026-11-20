# Co-thinking report — Product role (pass 2, independent)

Model/effort: Opus 5 (high effort), Product role.

Subject: the `agentic-workflow-installer` proposal (v1 = turn
`spec-driven-guardrails` into one Claude Code plugin), as specified in
`wip/claude-code-plugin/PRD.md`, `ARCHITECTURE.md`, `TEST-SCENARIOS.md`.
Pre-decision elaboration only — nothing here commits anyone to build.

**Material read beyond the scoped input** (declared per A8, all
project-internal ground truth; all of it was needed to check claims the
three scoped docs make *about* existing code and audiences rather than
about themselves):
- `spec-driven-guardrails/README.md` — the only place the product's own
  stated audience is written down. The PRD's Context asserts a different
  audience; that could not be checked without it.
- `spec-driven-guardrails/adopt.sh` (513 lines), `install.sh`, `lib/`,
  `skills/` — the PRD and ARCHITECTURE name specific functions
  (`install_skills`, `install_git_hooks`, `skill_symlink_update`,
  `seed_adoption_table`) as the v1 payload. The size and mechanism of that
  payload drives the whole value-vs-effort judgment.
- `agentic-workflow-installer/` repo (git log, file list, README) and
  `portfolio-mgt-agents/README.md` + `docs/` — to establish what exists
  today and whether the second consumer is real.
- `gh repo view` on all three repos — repo visibility decides whether
  plugin-marketplace distribution to a third party is even possible.

---

## 1. Requirement validation

The three documents are unusually disciplined for a pre-code design: the
options are genuinely weighed, the rejected ones are argued rather than
strawmanned, and the "for v1" qualifiers are applied consistently across
all three files. What follows is not a complaint about rigor. It is about
the product question the rigor is aimed at.

### 1.1 The stated audience contradicts the product's own stated audience

`PRD.md` Context, first paragraph:

> Both need to reach third-party users who are **not software engineers**

`spec-driven-guardrails/README.md`, "Who it's for, and who it's not":

> It's a personal workflow, not a product: the four projects using it
> today (this repo included) are Ties' own …
> This is for **solo developers using an AI coding agent** …
> It is not: … **A team tool, as shipped.**

These cannot both be true. One of the two documents is out of date, or the
PRD is asserting a new strategic intent (turn a personal workflow into a
distributable product) without saying so and without the README having
been changed to match. This is the single largest unvalidated assumption
in the proposal, and everything downstream — the primitive engine, the
cross-platform requirement A5, the whole business case — rests on it.

The proposal never names a user. Not a persona, not a segment, not one
real person who has asked for this. "A third such project is expected to
follow" is the only forward-looking evidence offered, and it is about
projects, not people.

### 1.2 "Install friction" is treated as the problem; it is at most the first five minutes

The PRD's diagnosis of `adopt.sh` is accurate and well-evidenced (I
verified it: `adopt.sh` hard-fails at line 15 without
`SPEC_DRIVEN_GUARDRAILS_DIR`, and `install.sh` ends by telling you to edit
`~/.zshrc`). But what `adopt.sh` installs is a *software engineering
workflow*: `feature/<issue-number>-<kebab-case>` branch naming enforced by
a `pre-commit` hook, `gh pr create`, `gh pr merge --squash`, a merge guard
that blocks on CI, `check-traceability.sh`, PRD/TEST-SCENARIOS scaffolds,
a `pre-merge-review` skill, and a `WORKFLOW-ADOPTION.md` table of
twenty-odd workflow changes to answer one at a time.

A person who cannot export an environment variable is not, one conversational
installer later, a person who can act on "your branch name doesn't match
the required pattern, create the issue first." The PRD optimizes the
doorway and says nothing about the building. F1–F7 end at "verification
reports pass/fail per criterion" — day two is out of frame entirely.

This does not make the project wrong. It makes it **necessary but not
sufficient**, and the PRD presents it as sufficient. Explicitly scoping
"installation, not ongoing use" as v1's boundary — and naming day-two
usability as the next, separate problem — would make the document honest
about what shipping it buys.

### 1.3 The functional scope stops short of what the named audience needs

`adopt_project()` refuses outright if the target has no `.git` directory:

> `Error: '$project_dir' is not a git repository (no .git directory found).`

For the stated non-engineer audience, the realistic starting state is: no
GitHub account, no `gh auth`, no `git config user.name/user.email`, no
repository, no remote. F1 detects *tools* (git, gh, Claude Code version);
nothing in F1–F7 covers detecting or establishing *identity and
repository state*. A6 correctly carves out "we can't install Claude Code
from inside Claude Code" as an admission gate — but it carves out only
that one precondition, and silently leaves several others inside a scope
that does not address them.

Either these belong in v1's functionality (a new F-item: "establish a
usable git/GitHub context"), or they belong in the bootstrap manual
alongside A6. Today they belong nowhere, which is the one outcome that
guarantees a real user hits them.

### 1.4 The symlink model is load-bearing and collides head-on with A5

This is the most consequential technical-product fact in the proposal, and
neither document mentions it.

`adopt.sh` does not copy the workflow into a project. It **symlinks** it:
`CLAUDE.md` → `$CLAUDE_WORKFLOW_DIR/WORKFLOW.md`, `.claude/settings.json` →
`settings/session-hooks.json`, one symlink per skill into
`.claude/skills/`, `.git/hooks/pre-commit` and `pre-push` → the repo's
`hooks/`, and `~/.claude/CLAUDE.md` → `USER-CLAUDE.md`. The code comments
state the intent plainly: *"Symlink, not a copy: … the rule must always be
the current version from spec-driven-guardrails, not a snapshot."*
`write_gitignore_block` then gitignores those paths precisely because they
point at an absolute path on one machine.

A5 requires Windows support. On Windows, creating a symlink requires
Developer Mode or elevation — exactly what "no admin rights" in the PRD's
own Failure modes section anticipates. So v1 cannot be "the same effects
`adopt.sh` produces today" (PRD F4's literal wording) on Windows. It has
to choose a different mechanism, and that mechanism **changes the
product's semantics**: copies are snapshots, and the "always current"
property — which the whole `CHANGES.md`/`WORKFLOW-ADOPTION.md` adoption
machinery is built around — becomes "current as of the last plugin
update."

That may well be the *better* answer (a version a user opted into beats
a moving target under their feet, especially for a non-engineer). But it
is a product decision about how the workflow propagates, not an
implementation detail, and it is currently invisible in both documents.
See Q4.

### 1.5 The plugin mechanism already deletes part of the payload — unacknowledged

A Claude Code plugin ships its own skills, hooks, commands and agents and
they load from the plugin itself. If `spec-driven-guardrails` becomes a
plugin, then `install_skills`, `skill_symlink_update`,
`skill_symlink_cleanup_if_orphaned` and `install_user_skill` — four of the
functions ARCHITECTURE's "Build order decided" earmarks for lifting into
primitives, and a substantial share of `adopt.sh`'s complexity — do not
need reimplementing. They need *deleting* for plugin users. The orphaned-
symlink cleanup logic exists only because symlinking into a live clone can
orphan; that failure class disappears with the plugin.

What genuinely remains project-local: `CLAUDE.md`, `.claude/settings.json`,
the two git hooks, the `.gitignore` block, the scaffolds (`PRD.md`,
`TEST-SCENARIOS.md`, `ARCHITECTURE.md`, `check-traceability.sh`, issue
templates, conditional CI files), and `seed_adoption_table`. That is a
meaningfully smaller and simpler payload than "what `adopt.sh` does" —
mostly "write this file if absent" and "seed a table."

This matters for scope: it shifts the ratio between engine and payload
further in the direction discussed in 1.6.

### 1.6 The engine is larger than the thing it installs

ARCHITECTURE specifies 6–8 primitives, each with **three** implementations
(execute, plan/dry-run, verify), plus a per-step state record carrying
`started`, `verified`, a hash of the step definitions, a hash of the
inputs, and verification evidence, plus resume logic that re-checks actual
target state rather than trusting flags.

The payload it drives, after 1.5, is roughly ten idempotent file
placements and one table seed, all of which complete in under a second
against a local directory. The justification for the engine is explicitly
*reuse across future projects* — which ARCHITECTURE then, correctly,
defers ("does not build that generic core speculatively, ahead of any real
consumer"). The build order defers the *extraction* but keeps the *full
generality of the engine* in v1. That is half the deferral. The
`portfolio-mgt-agents` consumer is confirmed non-existent as an install
target (I checked: specification-only repo, no application code, its own
README says so).

There is a sharper decomposition available. Resumability and rich state
earn their keep where steps are **slow, externally dependent, and
non-idempotent** — i.e. F2, installing git/gh over a network, possibly with
an OS installer and a reboot. They earn very little where steps are
**fast, local, and idempotent** — i.e. F4, where "resume" and "re-run from
scratch" are the same operation and verification (F7) already answers "did
this land" more reliably than any marker file can. The PRD itself asserts
F4's steps are idempotent, under Data integrity. If that holds, F6's
hash-bearing state model is mostly protecting against a cost that
idempotence already eliminated. See Q5.

### 1.7 Smaller gaps and ambiguities

- **"A specific Claude Code version" (F1, S1) is never specified.** No
  floor version, no source for the floor, no scenario asserting behavior
  below it. Undetectable as an acceptance criterion in its current form.
- **`--user` / machine-wide mode is named in F3 but has no scenario and no
  step.** F4's step list (place skills, hooks, symlink `CLAUDE.md`, seed
  the table) is the *project* path only; `adopt_user_trigger()` and
  `install_user_skill()` have no counterpart anywhere in F1–F7 or S1–S7b.
  For a non-engineer who will only ever have one project, the user-level
  trigger is arguably the *more* important of the two.
- **Re-adoption / upgrade is not specified.** `adopt.sh` is designed to be
  re-run (that is what the symlink-replacement and `scaffold_if_missing`
  logic is for). "The user already adopted, then the workflow changed" is
  a first-class, recurring scenario and appears nowhere. F6's resume
  covers *interrupted* runs, not *repeat* runs against an already-adopted
  project, which is a different thing.
- **Where the plugin's code lives is unstated.** The design lives in the
  `agentic-workflow-installer` repo; v1's deliverable is a
  `spec-driven-guardrails` plugin. Compounding this: `agentic-workflow-installer`
  is **private**, `spec-driven-guardrails` is **public**. A plugin
  distributed from a private repo cannot be installed by a third party. See Q2.
- **The docs exist in two places.** `wip/claude-code-plugin/*.md` in this
  repo is byte-identical to `agentic-workflow-installer/*.md` today (I
  diffed them), so no drift yet — but two copies of a normative spec with
  no stated authority between them is a drift generator, and this
  co-thinking round is about to add two reports to one of them.
- **A4 (no unexplained remote execution) has no test scenario.** It is a
  security-shaped requirement with no observable check, unlike A2/A3/A5
  which all have scenarios.
- **Uninstall / de-adopt is absent** from scope, limitations, and debt.
  The PRD's Deployability section correctly rules out rollback of applied
  steps, but never says whether a user can back out of the whole thing.
  `agent-skill-installer` is cited in ARCHITECTURE's prior art
  *specifically* for "clean uninstall ownership", and then that lesson is
  not taken up anywhere.

---

## 2. Acceptance criteria check

**Partly. Better than most pre-code specs, and still missing the layer
that would let anyone say "v1 is done."**

What exists and works: `TEST-SCENARIOS.md` gives 15 Given/When/Then
scenarios with `Covers:` fields, at least one happy path and one failure
path per F-item, and the failure paths are the good kind — S5b (a
primitive without a plan function is refused, not run blind), S6b (crash
between side effect and status update), S7b (F4 claims success, F7 catches
that the symlink points at the wrong target). Those three are genuine
acceptance criteria that a build could be held to. The
`Covers:`-traceability convention means coverage is mechanically checkable
rather than asserted.

What is missing:

1. **No product-level definition of success.** There is no criterion
   anywhere of the form "a person matching [profile] completes adoption
   in [conditions] with [amount of help]." Every scenario is a
   component-behavior check. The project's *entire premise* — usability
   for a non-engineer — is therefore the one thing v1 cannot fail. The
   PRD's own Usability section calls this out ("the largest remaining risk
   to this characteristic actually holding in practice") and then does not
   convert it into a criterion. See Q9.

2. **A5 is a requirement with no acceptance criterion.** Cross-platform is
   named "central to this project, not incidental," and no scenario asserts
   behavior on Windows or Linux. S2 is explicitly macOS. S2c covers an
   *unsupported* OS. The three *supported* OSes have no scenario each.
   Given 1.4, Windows is not a variation on the macOS path — it is a
   different mechanism — so "runs on Windows" cannot be inferred from
   "runs on macOS."

3. **The generic/specific split has a violation signal but no check.**
   ARCHITECTURE states it precisely: "a `spec-driven-guardrails` literal
   appearing in the generic side's files is the violation signal." That is
   a grep. This repo already has exactly this genre of check
   (`check-no-dutch.sh`, `check-no-quote-break.sh`, `check-traceability.sh`)
   wired into a `check` command. Turning the stated signal into a script
   would make the single most important structural claim of v1 —
   the one the whole build order rests on — mechanically enforced instead
   of aspirational. Cheap, high-leverage, currently absent.

4. **No criterion for "idempotent."** Data integrity asserts idempotence as
   *the* invariant that must hold, and no scenario tests running a
   completed install a second time. S6 tests resume from partial, not
   re-run from complete.

5. **No parity criterion against `adopt.sh`.** S4's "the target directory
   ends up in the same state `adopt.sh` would produce today" is the right
   idea but is not testable as written — "same state" is undefined, and per
   1.4/1.5 it will deliberately *not* be the same state (copies vs symlinks,
   plugin-provided vs symlinked skills). This needs to become an explicit,
   enumerated expected-tree criterion, with the intended differences listed.

6. **No criterion for the bootstrap manual**, which the PRD names as the
   largest open risk and places outside v1's scope. If it stays out of
   scope, v1 cannot be accepted by the audience v1 exists for. That is a
   sequencing statement, not a criticism — see E1 in §5.

7. **F6's state model is specified in detail but under-tested.** `started`,
   `verified`, a definitions hash, an inputs hash, and verification
   evidence are five fields; S6/S6b exercise roughly two of them. Nothing
   tests the definitions-hash case (plugin updated between runs — which,
   for a plugin that auto-updates, is a *likely* case, not an exotic one)
   or the inputs-hash case (user answers differently on re-run).

---

## 3. Business case

### The problem, and what it costs today

`spec-driven-guardrails` is, by its own README, four projects' worth of
personal infrastructure with a distribution mechanism (`adopt.sh` +
`install.sh` + an exported env var + a shell profile edit + a manual clone)
that gates adoption on being comfortable in a terminal. The concrete costs
being paid today:

- **Reach is zero outside the author.** Every capability in the repo — the
  merge guard, the traceability check, the PRD/scenario scaffolds, ten
  skills — is unreachable for anyone who won't clone a repo and edit
  `~/.zshrc`. The work is done; the delivery is the bottleneck.
- **Per-machine setup cost for the author.** This repo's own `CLAUDE.md`
  opens with "This project is developed from multiple computers."
  Every machine pays the clone + env-var + adopt dance, and every adopted
  project's symlinks are machine-absolute (hence the `.gitignore` block).
  A plugin removes that class of setup entirely for the author too.
- **Platform lock.** Everything is Bash 3.2/POSIX and symlink-dependent.
  The author's own machines are Macs, so this cost is currently zero and
  becomes real only on first contact with a Windows user.
- **An abstraction that has never been tested against a second consumer.**
  The core/manifest idea has been designed twice now (Option 1, then
  sharpened into primitives) without ever being exercised. Design debt
  accrues silently; only a build retires it.

Honest accounting: of these, only the second is a cost the author is
**currently** paying. The first is an opportunity cost that becomes real
only when a specific person is blocked, and no such person is named.

### Expected value

**High-confidence, near-term (accrues even if no third party ever adopts):**
- Distribution collapses from "clone + env var + shell profile + run a
  script" to "add a marketplace, install a plugin." `spec-driven-guardrails`
  is public, so this path is available today.
- Skills, hooks and settings become plugin-managed and versioned instead of
  machine-absolute symlinks — which also removes the orphaned-symlink
  failure class `adopt.sh` carries dedicated code for, and makes the
  `.gitignore` block largely unnecessary.
- A forcing function to state, in testable form, what adoption actually
  produces. The parity criterion in §2.5 is worth writing even if nothing
  else here gets built.

**Medium-confidence, conditional on 1.1 resolving in favor of real third
parties:**
- One additional consumer per unit of manifest work once the core is
  extracted — the stated long-term goal. Discounted heavily: the second
  consumer (`portfolio-mgt-agents`) has no application code, so this value
  is not merely unrealized, it is unschedulable.

**Low-confidence / speculative:**
- Non-engineers successfully *using* the workflow after installing it.
  See 1.2. Nothing in this proposal advances that, and it is the value
  the business case is implicitly claiming.

### Why now

The strongest "now" argument is not the audience. It is that **the design
is at a natural stopping point and further design without code has
negative return.** ARCHITECTURE has resolved hybrid-vs-plugin, narrowed
the bootstrap gate against real docs, and closed the manifest-format
question by declaring it moot for v1. Both remaining open items
("how `portfolio-mgt-agents` plugs in", "the manifest format") are
explicitly blocked on a consumer that does not exist. A third design round
would add words, not knowledge. The choice in front of Ties is build
something small or shelve it — not design more.

The weakest "now" argument is demand. There is no deadline, no waiting
user, no competitive pressure. Claude Code's plugin system is the one
genuinely time-sensitive element: it is young, and building against it now
means absorbing its churn. That argues for the *thinnest possible* plugin
surface in v1, not for waiting.

### Recommended framing

Fund **E1 + E2** (bootstrap manual + thin plugin, §5) as a bet that is
cheap, self-justifying through the author's own use, and — critically —
produces the evidence needed to decide about everything else. Treat
E3–E7 as conditional on E1 producing a real person who gets stuck
somewhere specific. Do not fund the primitive engine on the strength of a
reuse argument whose second consumer does not exist; that is the exact
speculation ARCHITECTURE's own build order was written to avoid, applied
one level short of where it should have been.

---

## 4. A note on effort

Per my role, I do not estimate effort — the roles that would do the work
do. Every epic below carries an **[Effort: open — Architect]** marker, and
§7 lists the specific ones where my priority ordering would flip if the
effort estimate comes back differently from what the ordering assumes.

---

## 5. Proposed epic / work-item decomposition

Ordered by recommended sequence. Each is independently shippable in the
sense that stopping after it leaves something usable.

### E1 — Bootstrap admission manual, tested against one real person
**Priority: 1 (highest).** [Effort: open — Architect]

The plain-language, step-by-step path from "a machine with nothing on it"
to "a running Claude Code session with a folder open," per A6 (Claude
Desktop app install + sign-in). Plus the gaps identified in §1.3 that A6
does not cover: a GitHub account, `gh auth login`, `git config` identity,
and getting a repository to exist at all.

Separate unit because it is the only part of this proposal that **cannot
be built by the plugin, by definition** (A6 is a hard boundary), because
it requires zero code, and because it is the *only* item that generates
the evidence the rest of the roadmap needs. It is also the only item that
delivers value if everything else is cancelled: a written manual plus a
human helper already gets a non-engineer adopted today, via `adopt.sh`.

**Done looks like:** a written document; one person matching the target
profile follows it unaided; every point where they stopped, asked, or
guessed is recorded verbatim. That transcript is the requirements document
for E3–E7 and the tiebreaker on Q1.

### E2 — `spec-driven-guardrails` as a thin Claude Code plugin (no engine)
**Priority: 2.** [Effort: open — Architect]

Ship the repo as a plugin: `plugin.json`, the ten existing skills carried
by the plugin, the session hooks, and one conversational entry point
(`/adopt` or equivalent) that walks the project-local placement steps —
implemented as directly as possible, with no primitive abstraction, no
plan/verify triad, no state model.

Separate unit because it delivers the **single largest item in the
business case** (distribution without clone/env-var/shell-profile) and
carries essentially none of the engine cost. Per §1.5 it also deletes four
of `adopt.sh`'s functions rather than reimplementing them. It is the
cheapest possible answer to "does the plugin route work at all," and every
later epic is easier to scope once it exists.

**Done looks like:** on a clean macOS machine, `plugin marketplace add` +
`plugin install`, then a conversation, leaves a target repo in a state
matching an explicitly enumerated expected tree (the §2.5 parity
criterion), with the intended deviations from `adopt.sh` listed. The
generic/specific grep check (§2.3) is wired into `check` from day one.

### E3 — Narrated intake and execution as tested primitives (F3, F4 subset)
**Priority: 3.** [Effort: open — Architect]

Refactor E2's direct implementation into the parameterized, tested
primitives ARCHITECTURE calls for, verifying as they move that they carry
no project literals (the ARCHITECTURE correction is explicit that these
functions are "generic-shaped but not yet separated"). Adds per-question
validation and per-step narration.

Separate unit because it is a *refactor of working code toward a future
consumer*, not new user-facing value — precisely the work that should be
justified by E1's evidence and deferred until E2 proves the route. Doing it
as step 3 rather than step 1 is the difference between extracting an
abstraction and inventing one.

**Done looks like:** primitives with tests against a fake filesystem;
E2's end-state parity criterion still passes unchanged; the grep check
still passes.

### E4 — Preview and verification (F5, F7)
**Priority: 4.** [Effort: open — Architect]

Per-primitive plan functions, the aggregate preview, the per-criterion
pass/fail report, and the refusal-to-preview-blind rule (S5b).

Separate unit, and deliberately paired: these are the **trust pair** for a
user who cannot read the code. Preview without verification tells someone
what will happen and not whether it did; verification without preview asks
them to consent blind. Shipping one without the other is worse than either.
It follows E3 because "every primitive owns its plan function" presupposes
primitives exist.

**Done looks like:** S5, S5b, S7, S7b pass; `check` fails if any primitive
lacks a plan function; the preview is demonstrably honest (running F4 after
a preview produces exactly the previewed changes — worth making its own
scenario).

### E5 — Cross-platform support (A5): Windows and Linux
**Priority: 5, but see Q4 — may need to move to 2.** [Effort: open — Architect]

Make detection, resolution and placement work on Windows and Linux. Owns
the symlink decision from §1.4 and its consequence for how workflow
updates propagate.

Separate unit because it is where the current design's foundation
(symlinks into a live clone) breaks, because it carries a **product
semantics decision**, not just a port, and because it is the epic most
likely to require revisiting E2/E3's step implementations. Sequenced late
only if the first real users are on macOS — if any are on Windows, this
moves ahead of E3 and possibly ahead of E2's completion, because a
mechanism decision taken after two epics are built on the other mechanism
is rework.

**Done looks like:** adoption completes on Windows without elevation and
on Linux; the propagation semantics (live vs. versioned) are documented as
a decision; a scenario per supported OS.

### E6 — Prerequisite detection and guided resolution (F1, F2)
**Priority: 6.** [Effort: open — Architect]

Detect git / gh / Claude Code version; per-OS guided resolution.

Separate unit because it is the least testable part of the system (the PRD
says so itself under Testability), the most OS-coupled, and the most
plausibly descopable: "detect, explain what is missing, and hand the user
the official install page for their OS" delivers most of the user value at
a fraction of the risk of actually driving package installers across three
platforms. Also the only epic whose steps are slow and non-idempotent, and
therefore the only one that genuinely motivates E7.

**Done looks like:** S1, S1b, S2, S2b, S2c pass; the version floor from Q11
is declared and checked; whether F2 installs or only guides is settled per
Q6.

### E7 — Resume state model (F6)
**Priority: 7 (last).** [Effort: open — Architect]

The per-step record (`started`, `verified`, definitions hash, inputs hash,
evidence) and resume-by-re-checking-actual-state.

Separate unit and deliberately last: per §1.6 it is the largest piece of
machinery protecting against the smallest observed cost, and most of what
it buys for E3's fast, local, idempotent steps is already bought by
idempotence plus E4's verification. Its real justification is E6's slow,
network-dependent steps. Scoping it after E6 means it can be scoped to the
problem it actually solves rather than to the general case.

**Done looks like:** S6, S6b pass, plus the two untested state fields from
§2.7 (plugin updated between runs; user answers differently on re-run) get
scenarios and defined behavior.

### E8 — Re-adoption and de-adoption
**Priority: 8, but promote if E1 surfaces it.** [Effort: open — Architect]

Re-running against an already-adopted project after the workflow changed
(§1.7), and backing the whole thing out.

Separate unit because both are absent from the current spec entirely, and
because re-adoption is the *most frequent* operation over a project's
lifetime — `adopt.sh` is re-run every time `CHANGES.md` grows — while the
spec treats adoption as one-shot.

**Done looks like:** re-running a complete install is a verified no-op;
a workflow update applies without duplicating or clobbering user-modified
files; de-adoption is either implemented or documented as a manual
procedure and recorded under Known limitations.

### E9 — Generic core extraction (explicitly NOT v1)
**Priority: deferred.** [Effort: open — Architect]

Listed only so it stays visible as the stated long-term goal. Its trigger
is already correctly written in ARCHITECTURE: a second real project needs
it. That trigger is not met and cannot be met until `portfolio-mgt-agents`
has code to install.

---

## 6. Open questions and risks

Numbered per the grilling method, each with my recommended answer. These
are the decisions I judge to be genuinely Ties' — everything I could look
up, I looked up (see the declared reading list at the top). Q1 and Q2 are
the frontier: several later questions reshape depending on how they land.

❓ **Q1 — Who is v1's real user?** `PRD.md` says non-engineer third
parties; `README.md` says solo developers and "a personal workflow, not a
product." One is wrong. This is not a wording fix: it sets whether A5
(Windows), the conversational layer, and the bootstrap manual are
requirements or gold-plating. Sub-question: can you name one actual person
who would use this in the next three months?

➡️ If you can name a person: keep the non-engineer framing, make E1 the
first deliverable, and update `README.md` to match the new intent. If you
cannot: rescope v1's stated audience to "anyone with Claude Code, no
terminal comfort assumed" — a strictly weaker claim that E2 satisfies on
its own, that keeps `README.md` true, and that makes the whole primitive
engine optional rather than assumed. My recommendation is the second,
because "a third such project is expected to follow" is the only demand
evidence in the document and it is about repos, not people.

---

❓ **Q2 — Which repo holds the v1 plugin's code?** The design lives in
`agentic-workflow-installer`; the deliverable is a `spec-driven-guardrails`
plugin. `agentic-workflow-installer` is **private**; `spec-driven-guardrails`
is **public**. A plugin cannot be distributed to a third party from a
private repo. Three options: (a) plugin code in `spec-driven-guardrails`,
design stays where it is; (b) move everything into
`agentic-workflow-installer` and make it public; (c) keep both and
duplicate.

➡️ (a). The plugin *is* `spec-driven-guardrails`'s own distribution
mechanism for v1, it is already public and already carries the skills and
hooks the plugin ships, and `${CLAUDE_PLUGIN_ROOT}` removes the
cross-repo-path problem that motivated `SPEC_DRIVEN_GUARDRAILS_DIR` in the
first place. Leave `agentic-workflow-installer` as the design/decision home
for the eventual generic core, and — importantly — pick **one** copy of
the three design docs as normative (I would say the
`agentic-workflow-installer` repo, since traceability checks run there) and
make `wip/claude-code-plugin/` either a pointer or a snapshot marked as
such. Two byte-identical normative specs will not stay identical.

---

❓ **Q3 — Does v1 claim engine generality, or is it allowed to be
hardcoded?** ARCHITECTURE defers *extracting* the core but keeps the full
primitive/plan/verify/state apparatus in v1. Per §1.6 the payload after
§1.5 is roughly ten idempotent file writes plus a table seed.

➡️ Allow it to be direct in E2 and extract primitives in E3, once real
steps exist to generalize from. This is the same argument ARCHITECTURE
already accepted ("de-risks the abstraction against a real consumer before
generalizing") applied one level deeper — to the primitive set, not just
to the plugin split. Keep the generic/specific *file* split and its grep
check from day one: that costs nothing and preserves the extraction path.

---

❓ **Q4 — Symlinks or copies, and does the workflow stay live?** §1.4:
`adopt.sh` symlinks so adopted projects always track the current
`WORKFLOW.md`. Windows (A5) makes symlinks require elevation. Copies make
adoption a snapshot and change how `CHANGES.md` updates reach projects.
This is a product decision about propagation, not a port detail.

➡️ Plugin-provided content (skills, settings, hooks) comes from the plugin
and is versioned by plugin updates — which is *better* for a non-engineer
than a moving target, and removes the orphaned-symlink failure class
outright. Project-local files (`CLAUDE.md`, scaffolds, hooks) become copies
with a recorded source version, refreshed by re-running adoption (E8).
Keep `adopt.sh` and its symlink model unchanged for your own machines; do
not try to make one mechanism serve both. Then say so in the PRD, because
it changes what "the same state `adopt.sh` would produce" means in S4.

---

❓ **Q5 — How much of F6's state model does v1 need?** Five fields
(`started`, `verified`, definitions hash, inputs hash, evidence) plus
re-check-on-resume, against steps the PRD itself says are idempotent and
that complete in under a second.

➡️ Cut to: idempotence plus E4's verification for the fast local steps
(F4), and a real progress marker only for the slow, externally-dependent
prerequisite phase (F2), where an interruption actually costs something.
Revisit when E6 exists and you can see which failures really occur. Keep
S6b's *insight* (never trust a bare flag; re-check actual state) — it is
correct and cheap; it is the five-field record that is speculative.

---

❓ **Q6 — Does F2 install prerequisites, or detect and guide?** Actually
driving Homebrew / winget / apt across three OSes, with confirmation, is
the riskiest and least testable code in the proposal.

➡️ v1 detects, explains in plain language what is missing and why, and
hands the user the official install page for their detected OS, then
re-checks. Automating the install is E6-plus, justified only if E1's real
user demonstrably cannot follow a link. Note that `gh auth login` is
different and should stay automated-to-the-browser-flow — the PRD's
Security section is right about that one.

---

❓ **Q7 — Is the machine-wide (`--user`) path in v1?** F3 mentions it;
F4 and every scenario ignore it (§1.7). For a plugin, the user-level
skill install (`install_user_skill`) is largely superseded — a plugin's
skills are available user-wide already.

➡️ Yes, in scope, and simplified: with the plugin installed, the only
remaining user-level artifact is the `~/.claude/CLAUDE.md` trigger, and
even that could move into the plugin. Decide this in E2 and add a scenario,
because a non-engineer with exactly one project will hit the user-level
path first, not the project path.

---

❓ **Q8 — Is de-adoption in scope?** Absent from the PRD entirely, though
ARCHITECTURE cites `agent-skill-installer` specifically for "clean
uninstall ownership."

➡️ Not as automation in v1, but it must not stay unmentioned: document a
manual removal procedure and record it under Known limitations. The
audience that cannot export an env var also cannot unpick symlinks and
gitignore blocks by hand, so "no way out" is a real adoption deterrent for
exactly the people this is for. Full undo stays out of scope, consistent
with the PRD's existing "declining a step is not rollback" correction.

---

❓ **Q9 — What is v1's success metric?** §2.1: no product-level criterion
exists, so v1's central claim is unfalsifiable.

➡️ Adopt this as the acceptance criterion for E1+E2 jointly: *one person
matching the target profile, starting from a machine with nothing
installed, reaches a fully adopted project without typing a terminal
command and without more than one clarifying question to a human, within
30 minutes.* Every number in that is arbitrary and every one is better than
the absence of a number. Record the transcript either way — a failure
tells you which epic to fund next, which is worth more than a pass.

---

❓ **Q10 — Is the workflow itself ready to be handed to a non-engineer?**
§1.2: a frictionless installer delivers issue-first branch naming, PR
discipline, a CI merge guard and a traceability check to someone who may
never have opened a pull request. Installation success and adoption
success are different outcomes.

➡️ Before funding E3–E7, run the cheap version of this experiment: sit
with one target user, install via `adopt.sh` yourself, and watch them work
for an hour. If the workflow itself does not survive contact, the installer
is the wrong problem and E1+E2 (which are worth building on your own-use
value alone) are the correct stopping point. This is the highest-value,
lowest-cost test available and it needs no code.

---

❓ **Q11 — What is the minimum supported Claude Code version?** F1 and S1
both reference "a specific Claude Code version" and nothing declares one.
As written it is an untestable criterion.

➡️ Declare the floor as the version whose plugin-system behavior E2 is
actually built and tested against, record it in the PRD, and have F1 check
it mechanically. Given the plugin system's youth, also record how you will
find out when it changes under you — that is the one real external
dependency risk in this proposal.

---

❓ **Q12 — Does the priority order in §5 survive real effort estimates?**
I ordered by value and evidence-generation, with effort unknown by design.

➡️ Hold §5's order as provisional and re-rank once the Architect returns
estimates. The two flips I would expect: if E5 (cross-platform) turns out
to be foundational rather than additive (likely, per Q4), it moves ahead of
E3; and if E2 turns out to be nearly free — which it may be, since the
plugin mechanism supplies most of it — then E1 and E2 should run in
parallel rather than in sequence.

---

## 7. Handover note for the Architect

The points below are the ones most likely to change your grouping, plus
the ones where I made a product judgment that rests on a technical fact
you should verify rather than inherit.

**Verify these facts — my epic ordering depends on them:**

1. **How much of `adopt.sh` the plugin mechanism simply deletes** (§1.5).
   I claim `install_skills`, `skill_symlink_update`,
   `skill_symlink_cleanup_if_orphaned` and `install_user_skill` largely
   disappear when skills ship with the plugin, leaving a payload of ~10
   idempotent file placements plus `seed_adoption_table`. If that is wrong
   — if plugin-provided skills cannot replace project-local
   `.claude/skills/` symlinks for some reason — E2 is much bigger and E3
   may need to merge into it.

2. **Windows symlink behavior and the propagation semantics that follow**
   (§1.4, Q4). This is the one place where a technical constraint forces a
   product decision. If copies are required on Windows, decide whether
   macOS/Linux also switch to copies for consistency, or whether the
   product deliberately behaves differently per OS. Either answer is
   defensible; an unstated answer is not. My ordering assumes this is
   settled *before* E3, not during E5.

3. **Whether `${CLAUDE_PLUGIN_ROOT}` fully replaces
   `SPEC_DRIVEN_GUARDRAILS_DIR`.** My business case leans hard on
   "distribution friction collapses to two commands." If the plugin still
   needs a checkout path on disk for some artifact, that claim weakens and
   E2's value drops.

4. **The plugin system's stability and version floor** (Q11). It is the
   only external dependency in this proposal whose churn you cannot
   control, and E2 is built directly on it.

**Grouping decisions I expect you to challenge:**

5. **E3/E4 split (primitives, then preview+verification).** I split them
   because preview and verification are a *user-trust* pair that ships
   together. You may find they are an *implementation* triad
   (execute/plan/verify per primitive) that is cheaper to build at once
   than to retrofit. If so, merge E3 and E4 and say so — my split would be
   wrong on effort grounds and I would accept that.

6. **E7 (resume state) last, and possibly cut** (§1.6, Q5). If the
   five-field record is nearly free once primitives exist, my argument
   dissolves and it folds into E3. My claim is that its cost is
   disproportionate to the observed problem, not that it is wrong.

7. **E6 (prerequisites) at priority 6.** Product-wise it is late because
   it is descopable to "detect and link." Technically it may be the thing
   everything else is blocked behind on a clean machine. If a clean-machine
   run cannot get past F1 without F2, tell me and it moves up.

**Things the current design does not account for, which may need
architecture rather than just scope:**

8. **Re-adoption / upgrade** (§1.7, E8) — the most frequent operation over
   a project's lifetime, absent from the spec. It interacts with Q4: if
   files become copies, "apply the workflow update" needs a real merge
   strategy for files the user has since edited (`PRD.md` scaffolds in
   particular — `scaffold_if_missing` deliberately never overwrites). This
   may be a bigger architectural question than anything in F1–F7.

9. **Identity and repository bootstrap** (§1.3) — `adopt_project()`
   hard-fails without `.git`, and nothing in F1–F7 establishes a GitHub
   account, `gh auth`, `git config` identity, or a repository. Decide
   whether this becomes a new F-item or joins A6's admission gate. It
   cannot stay unassigned.

10. **The generic/specific grep check** (§2.3). ARCHITECTURE states the
    violation signal precisely and this repo already has three checks of
    exactly that genre wired into `check`. Making it mechanical in E2 is
    the cheapest possible insurance on the build order's central claim.
    If you agree, it belongs in E2's definition of done, not later.

**Finally, the product framing I would ask you to price against:** the
recommendation in §3 is to fund E1+E2 only, and treat E3–E7 as conditional
on E1 producing a real user who gets stuck somewhere specific. If your
estimates show E2 is not meaningfully cheaper than E2+E3+E4 together, that
recommendation does not hold and Ties should hear that from you.
