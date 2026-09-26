# Architecture decision — generic installer core vs. per-project manifest

This document records *why* the system is the way it is. `PRD.md` describes
what it must do; this is where the structural choices underneath that live,
which alternatives were weighed, and when a choice should be revisited.

Not every decision belongs here. Yes: platform choices, the split into
layers or components, who owns which data, and adding a substantial
dependency. No: how one function is written.

---

## The decision

**Decided on 2026-09-20: the installer splits into a generic, data-driven
core and a thin, declarative per-project manifest.**

**Sharpened on 2026-09-20 (second-opinion review, resolving "Option 1 vs.
Option 4" below): the core is a small, mechanically tested set of
primitives, not a general-purpose interpreter.**

**Re-derived on 2026-09-26 against the real `adopt.sh` implementation, not
just the docs' description of it (co-thinking session pass 2):** the
originally stated set (`check_tool`, `install_package`, `clone_repository`,
`copy_template`, `write_config`, `run_approved_command`, `assert` — 6-8
primitives) was itself speculative rather than derived. Applying the
deletion test and the two-adapters rule (`vendor/codebase-design/SKILL.md`
in `wip/multi-agent-development/`) to every operation `adopt_project()`
and `adopt_user_trigger()` actually perform:

| Primitive | Deletion test | Adapters that really vary | Verdict |
|---|---|---|---|
| `check_tool` | Complexity reappears at every caller (per-OS probing, version parsing) | macOS / Windows / Linux — three, real | **Deep. Keep.** |
| `install_package` | Same | brew / winget / apt | **Keep** (Q8 in "Still open" below narrows this to detect-and-guide, not driven installs) |
| `clone_repository` | Nothing reappears — v1 has zero callers; the plugin mechanism itself is the delivery mechanism that replaced cloning | none | **Deleted from the set** |
| `copy_template` | Nothing reappears; it is `scaffold_if_missing`, a shallow pass-through with one caller shape | one | **Folded into plain step data**, not a primitive |
| `write_config` → **`write_managed_block`** (renamed) | Complexity reappears — `write_gitignore_block` is 85 lines of `awk` with marker-integrity guarding, protecting real data (a documented past failure erased an unrelated `.gitignore` block) | one today, but the *behaviour* is deep | **Keep, renamed** — the one payload item where a casual reimplementation loses correctness silently |
| `run_approved_command` | This is the only place A4 can be enforced; without it, "no unexplained execution" is a property of every caller instead of one seam | one production adapter, one recording/test adapter | **Keep — it is the A4 seam** |
| `assert` | This is F7 (verification), not a peer of the others | — | **Not a primitive; it is the verify mode** |

**Four primitives, not 6-8: `check_tool`, `install_package`,
`write_managed_block`, `run_approved_command`**, each with its own
execution, plan/preview, and verification logic, plus a step list that is
plain data. No general `shell` primitive in v1: a step a manifest needs
that isn't expressible as one of these primitives is a signal to add a
primitive, not to reach for an escape hatch, because a generic `shell` step
would make preview, cross-platform behavior, safety, and idempotence a
per-manifest concern again — exactly what the core/manifest split exists to
avoid. (`run_approved_command` is not that escape hatch: every invocation
it makes ships its own plan and verification function, the same discipline
as any other primitive, just parameterized — a closed whitelist, not an
open shell.)

**Build-order correction, decided 2026-09-26:** rather than building this
full execute/plan/verify apparatus before a real step list exists, v1
implements the steps directly (`PRD.md` F4) and extracts them into this
primitive set later (`PRD.md` Epics, E4) — the same "de-risk before
generalizing" principle "Build order decided" below already applies to the
plugin split, applied one level deeper to the primitives themselves.

The core owns everything that's the same across every consuming project:
detecting and resolving prerequisites, running the conversational
question flow, narrating actions in plain language, tracking install
progress for resume, and verifying success. A manifest — one per
consuming project (`spec-driven-guardrails`, later `portfolio-mgt-agents`,
future projects) — declares only *what* that project needs: which
prerequisites, which questions, which steps (as calls to the core's
primitives), which files, which verification checks. The manifest never
controls *how* something is phrased or executed; that stays the core's
job, so every installed project feels like the same product to the user.

A Claude-driven skill/prompt still has a role, but as the conversational
layer on top of this mechanical core — explaining steps, answering
follow-up questions, guiding the user through ambiguity — not as the
execution engine itself. See Option 4 below for why the reverse (prompt as
execution engine) was rejected as the primary layer.

---

## Evaluation criteria

| Criterion | Why it counts |
|---|---|
| Reuse across projects | The whole point of this repo existing separately: a third project must be addable without touching the logic that already works for the first two. |
| Non-engineer usability | The target user has no git/terminal background — the conversational and explanatory layer must be consistent and can't be reinvented per project. |
| Maintenance burden | One codebase drifting into N bespoke installers (the `adopt.sh` shape) is the failure mode this project exists to avoid. |
| Time to add a project | A new consuming project should cost "write a manifest," not "write an installer." |
| Reliability across runs | The install must behave the same way every time it's used — determinism and dependable resumability matter more here than raw flexibility, since a non-engineer gets no second chance to debug a flaky run. |

---

## Options weighed

### Option 1 — Generic core + declarative per-project manifest (chosen)
A single installer engine reads a project-supplied manifest (prerequisites,
questions, steps, verification, all declarative) and drives the
conversation and execution itself. Mirrors `adopt.sh`'s own existing split
of `lib/changes.sh`/`lib/nfr.sh` (shared logic) from the adopting script
(project-specific glue), taken one step further: even the "glue" becomes
data, not code, per project.

Scores well on reuse, usability (one voice/UX for every project), and time
to add a project (author a manifest, not a script). Costs: the manifest
format itself becomes a thing to design and maintain, and any step a
manifest needs that the core doesn't yet support requires a core change
(see "When we would revisit this choice").

### Option 2 — Fully bespoke installer per project
Each consuming project gets its own installer script, purpose-built —
the shape `adopt.sh` already has for `spec-driven-guardrails` itself.

Fast to start for exactly one project, but every property that matters
here degrades with each additional project: the conversational UX drifts
project to project (nothing forces consistency), prerequisite-detection
logic gets rewritten or copy-pasted, and a fix to one installer doesn't
reach the others. Rejected: this is the status quo shape this project
exists to replace, not repeat under a new name.

### Option 3 — Single monolithic script covering every known project inline
One script with per-project branches (`if project == "spec-driven-
guardrails" then ... elif project == "portfolio-mgt-agents" then ...`).

Avoids a manifest format up front, but mixes generic and project-specific
logic in one file that only grows, and every new project is a code change
to a script every other project also depends on — the opposite of
isolating project-specific concerns. Doesn't scale past 2-3 projects.
Rejected.

### Option 4 — Prompt-driven core + minimal state marker (hybrid, added 2026-09-20, not yet compared against Option 1)
Generic behavior — ask, explain, detect prerequisites, narrate, verify —
lives as a reusable prompt/skill Claude follows directly, the same shape
`adopt-workflow`/`write-spec` already use in `spec-driven-guardrails`
itself. No manifest interpreter and no schema to design: per-project
specifics are a prose brief (what this project needs), not declarative
data. The one piece deliberately kept mechanical rather than prompted: a
small local progress-marker file, filled the same role as Option 1's F6
state, that the prompt is instructed to read before each step and write
after it — so "was this already done" is answered by a file on disk, not
by trusting the model's memory of the conversation so far.

Scores well on time to add a project (write a brief, not a schema-
conformant manifest) and reuses a pattern already proven in this
ecosystem. Costs real ground on reliability across runs: a manifest-
driven engine (Option 1) executes a declared step identically every
time by construction, while a prompt's execution depends on the model
correctly following it — rewording the prompt, or a model swap, can
shift behavior in a way a manifest schema can't. The state-marker file
keeps resumability (A3) mechanically grounded even so, which is why this
is recorded as a hybrid rather than a pure prompt-only design (the
version this option deliberately does *not* propose): verification
(F7) is the part that stays weakest here, since "did this step actually
succeed" is judged by the model reading the brief rather than a script
asserting a fixed condition.

---

## Comparison and choice

Option 1 wins on every criterion that matters for a project explicitly
meant to be reused by a growing set of consuming projects, at the
deliberate cost of having to design and maintain a manifest format — a
real cost, not a free lunch. Option 2 is simpler per-project but is
exactly the pattern already shown not to scale (`adopt.sh`'s own
audience mismatch is what motivated this project). Option 3 defers the
manifest-design cost but pays it back with interest as a shared,
ever-branching script.

**Resolved 2026-09-20 (second-opinion review):** Option 4 is rejected as
the primary execution layer. The requirements that matter most here —
reliable resume, honest preview, and real verification — don't follow
reliably from model instructions alone. A progress-marker file helps
Option 4's resumability (A3), but it can't by itself prove a step actually
executed, or that an interruption didn't land between a side effect and
its status update — that gap is exactly what a mechanical, tested
primitive with its own state and verification logic (Option 1, sharpened
above) closes and a prompt cannot. Option 4's conversational strengths are
kept, but as the layer that explains and guides the core's execution, not
as a replacement for it — see the sharpened decision above.

---

## Build order decided 2026-09-20, revised 2026-09-26: two plugins by scope, single project

This does **not** replace "The decision" above — the target shape (generic
core, small tested primitives, declarative per-project manifests) stays
the intended eventual architecture. What's decided here is *build order and
plugin topology*: v1 does not build the generic core speculatively, ahead
of any real consumer. Instead, v1 turns `spec-driven-guardrails` into
**two Claude Code plugins, split by install scope**, with the
generic/specific split enforced internally within each — a generic side
(no `spec-driven-guardrails` literals: the primitive scripts, state model,
preview/verification logic) and a `spec-driven-guardrails`-specific side
(which skills, which templates, which questions, which git hooks — the
plugins' own embedded configuration, playing the role a per-project
manifest will later play).

### Why two plugins, not one (decided 2026-09-26)

The original one-plugin design had a hazard, found only by reading the
actual mechanism rather than the docs describing it: **a plugin's hooks
don't wait for one of its skills or commands to be used — Claude Code
registers them when a session loads the plugin, and they fire on their
events from then on, in every project the session touches.** A user-scope
`spec-driven-guardrails` plugin would mean `git-guardrails`,
`push-after-commit`, and the SessionEnd auto-push fire in *every* project
Ties opens, not only ones actually adopted — including work/client repos
his own user-level `CLAUDE.md` explicitly says must never receive this
workflow unasked. The SessionEnd hook runs `git push origin HEAD` on any
non-main branch; the blast radius is not theoretical.

An initial fix considered — an "adoption guard" self-check inside every
hook, reading a per-project marker before doing anything — was rejected as
a workaround, not a proper solution, once investigated further. `hall-of-
automata-cli`, cited as a supposed prior example of solving this, turned
out on inspection to have the opposite: zero project scoping in its own
hook, saved only by three independent bugs (a wrong JSON field parsed, a
non-blocking exit code, a GNU-only flag macOS rejects) — verified
empirically, not asserted. That made the case for a structural fix rather
than a conventional one.

**The real, native mechanism: Claude Code's plugin install scope.**
Plugins install at user, project, or local scope. Local scope writes
`.claude/settings.local.json` and **both fetches and confines** the plugin
to that one directory — the same file doing the same confinement job
`adopt.sh`'s symlinked `settings/session-hooks.json` does today, with
Claude Code owning the bookkeeping instead of a shell script. A hook that
is not loaded in a project structurally cannot fire there; nothing inside
the hook has to be correct for that to hold.

**Resulting split** — mirrors a split that already exists in the repo
between `USER-CLAUDE.md`/`adopt-workflow` (must work in *not-yet-adopted*
projects) and `WORKFLOW.md`/`session-hooks.json`/the other skills:

- **`spec-driven-guardrails-adopt`** (user scope): the
  `/spec-driven-guardrails:adopt` command and the adoption-time skills.
  **No hooks.** Harmless in a client repo, because it does nothing until
  explicitly invoked there.
- **`spec-driven-guardrails`** (local scope): the other skills plus all
  hooks. Installed by the adopt command running
  `claude plugin install --scope local`, inside the target repo the user
  already confirmed (`PRD.md` F3) — never anywhere else.

De-adoption (`PRD.md` F8) becomes a native `plugin uninstall --scope
local`, which is also a direct consequence of this split, not a separately
designed feature.

**An alternative was weighed and rejected:** project-local hooks, written
into the target repo directly by the adopt command, instead of carried by
either plugin. Rejected on four grounds: it re-creates the exact
dangling-path propagation problem the plugin mechanism was meant to
remove; for hooks specifically, auto-update-with-the-plugin is *more*
valuable than for skills, not less (a false-positive guard bug would need
fixing in every already-adopted project individually, not once); it gives
up the native uninstall path; and it still needs a user-scope artifact
(the command) regardless, making it the same two-artifact design with the
second one hand-rolled instead of native. Kept as a documented fallback
only if distribution ever has to work without a marketplace.

**Residues, named honestly:** a collaborator who clones an adopted project
reaches the local-scope plugin's configuration but does not auto-fetch it
(one test scenario, no action needed beyond that); a multi-root session
(`--add-dir`) needs no special handling. One cheap assertion is kept on
the SessionEnd push hook specifically — the only hook with an irreversible
side effect — as defense in depth, not as the scoping mechanism itself.

### The propagation decision: one mechanism, copies everywhere (decided 2026-09-26)

`adopt.sh` symlinks project-local content today so it always tracks the
current `spec-driven-guardrails` checkout. Two independent facts force
this away from symlinks, not only Windows:

1. **A `.git/hooks` symlink into a plugin's cache dangles on the plugin's
   next update.** `${CLAUDE_PLUGIN_ROOT}` is documented as changing when
   the plugin updates — exactly the failure mode `adopt.sh`'s own code
   comments name as the reason it symlinks by absolute, not relative,
   path today, applied one layer further up. Git silently skips a
   dangling hook; there is no report at all.
2. **`hooks/pre-commit` fails open when it is not a symlink** — verified
   in the actual hook code: it `readlink`s itself to find `rules.sh`, and
   on failure prints a warning and exits 0, silently skipping the check
   most users will never see the warning for. So "copies instead of
   symlinks" is not a placement-strategy change; it forces a code change
   inside the hook itself regardless of which OS is in scope.

**Decided: one mechanism, copies everywhere, including Ties' own
machines — not two mechanisms running side by side.** Two mechanisms would
mean two definitions of "adopted" across four real, currently-adopted
projects, doubling the verification matrix for exactly the scenario (a
symlink pointing at the wrong target) that already exists, with any drift
landing on Ties specifically, on his own machines. `adopt.sh` is marked
**author-only legacy**, with a stated retirement trigger: retired once the
plugin passes the enumerated parity criterion (`PRD.md` F7) on all four of
Ties' adopted projects. An undated "keep both" was considered and
rejected — it is how a third mechanism appears later.

Propagation semantics, stated plainly: plugin-carried content (skills,
session hooks) tracks the plugin version, updated when the user runs
`/plugin marketplace update` (auto-update is off by default — verified
against the official docs); project-local content (`CLAUDE.md`, hooks,
scaffolds, the `.gitignore` block) is a copy stamped with the plugin
version it came from, refreshed by re-running adoption (`PRD.md` F9).

**Corrected 2026-09-20 (review finding — an earlier draft of this section
misattributed which file these functions live in):** `adopt.sh` already
demonstrates this kind of split working for a different concern —
`lib/changes.sh` and
`lib/nfr.sh` hold generic-shaped helper functions (`nfr_field`,
`nfr_section`, `iterate_nfr`, and equivalents for `CHANGES.md` handling),
separate from `adopt.sh`'s own body. The install-specific functions this
plan lifts into primitives — `backup_if_real_file`, `scaffold_if_missing`,
`skill_symlink_update`, `install_skills`, `install_git_hooks` — are
**generic-shaped but not yet separated**: they live in `adopt.sh` itself
today, alongside the genuinely `spec-driven-guardrails`-specific
`seed_adoption_table`, `copy_issue_templates`, and `adopt_project`.

**Correction, 2026-09-26:** `install_skills`, `skill_symlink_update`,
`skill_symlink_cleanup_if_orphaned`, and `install_user_skill` do not need
lifting into primitives at all — they are **deleted**, not reimplemented.
A Claude Code plugin ships its own skills, loaded from the plugin itself;
there is no project-local skills directory to maintain under either
plugin, and the orphaned-symlink-cleanup logic exists only because
symlinking skills into a live clone could orphan them — that failure class
disappears entirely once skills are plugin-carried. This is a genuine
**scope widening**, not parity: today skills are installed per project; a
user-scope-carried skill set (via `spec-driven-guardrails-adopt`) makes
all of them available in every project, namespaced. Mostly welcome on its
own, and exactly why the hook-scoping problem above needed a real fix
rather than an afterthought — the same mechanism that deletes four
functions for free would otherwise have widened hook exposure right along
with it.

Three payload items, verified against the plugin manifest reference,
**cannot** become plugin content regardless: plugin `settings.json` only
honors `agent`/`subagentStatusLine` (so `attribution.commit: ""` stays a
real project-local file); Claude Code does not load a `CLAUDE.md` at a
plugin's root as project context (so `CLAUDE.md` → `WORKFLOW.md` and the
`~/.claude/CLAUDE.md` trigger both stay real file placements, per `PRD.md`
F3/F9). `.claude/settings.json` therefore does not disappear under the
plugin split — it shrinks to the attribution setting and stays written
project-locally.

**Why this order, not core-first:** de-risks the abstraction against a
real consumer before generalizing (this session's second-opinion review's
own recommendation — write one realistic manifest first, derive
primitives from it), and reuses Claude Code's own plugin infrastructure
(install scope, inter-plugin `dependencies`, deterministic hook/script
execution) instead of hand-building a manifest interpreter and
distribution mechanism before either is proven necessary.

**What stays deferred, not decided against:** extracting the generic side
into its own distributable "core" plugin, which a second project's plugin
would declare as a `dependencies` entry, happens only once a second real
project actually needs it. Until then, "two plugins, internally split, by
install scope" is the whole system — there is no separate core artifact
yet. This is a trigger, alongside the existing "third consuming project
needs a capability the primitive set can't express" trigger in "When we
would revisit this choice" below.

**A5 (cross-platform) is not weakened by this, and is narrower than
originally stated (decided 2026-09-26).** `adopt.sh` today is
Bash/POSIX-only — exactly the shell-comfort assumption this project
exists to remove for a non-engineer audience (`PRD.md` Context). Building
the plugins as a thin wrapper that shells out to `adopt.sh`'s existing
Bash implementation would inherit that limitation and violate A5. The
plugins' own primitive scripts and the F0-F2 installer logic must be
written cross-platform-safe (macOS/Windows/Linux) from the start. **What
A5 does not cover, found only by reading the actual guardrails rather
than the design docs about them:** the *payload* — `git-guardrails` (822
lines of Bash, hard-requiring `python3`), the other git hooks, and the
traceability check scripts — is Bash-and-`python3`, not portable, and the
installer being portable does not make it portable. Decided 2026-09-26: on
Windows, WSL or Git Bash is a **declared prerequisite** (`PRD.md` F1),
detected and explained, not silently assumed and not reimplemented for
v1. `git` itself is already a prerequisite of installing either plugin
from a git-hosted marketplace, so the marginal ask is small and honest.
Reimplementing the guardrails as genuinely cross-platform code was
considered and rejected for v1 as by far the largest single item on
either co-thinking report — revisit only if a real Windows user's
experience with the WSL/Git-Bash prerequisite proves it insufficient.

---

## Architecture requirements that follow from this

**"Manifest" below names the concept, not a current artifact.** These
requirements (A1-A7) describe invariants the target shape must hold.
**For v1** (per "Build order decided" and "System boundaries and
ownership"), there is no separate manifest file — "manifest"/"manifest
step" means the `spec-driven-guardrails`-specific side of each plugin's
internal split. The requirements apply to that internal split exactly as
written; they don't imply an external file exists yet.

### A1 — Conversational layer and mechanical steps stay separable
The core decides *how* to ask, explain, and narrate; a manifest only ever
declares *what* to ask, check, or run — never wording, tone, or sequencing
logic of its own. Violation signal: a manifest containing a literal
sentence meant to be shown to the user verbatim, instead of a
structured field the core phrases itself.

**Amended 2026-09-20:** this doesn't bar project-specific, non-executable
context. A manifest step may carry a `purpose`/`rationale` field and error
context describing *why* that step matters for this specific project — the
core still owns turning that into final user-facing wording (A2), but it
can't honestly explain "why this, for this project" without the manifest
supplying that reason. The violation signal above is unchanged: the line
is fixed phrasing vs. structured data the core phrases, not "any
project-specific content at all."

### A2 — No assumption of engineering background
Every prerequisite check and manifest step explains *why* it matters,
in plain language, before acting — never a bare command name or flag as
the entire explanation. Violation signal: any step whose only user-facing
output is a tool name, a flag, or a raw CLI invocation.

### A3 — Idempotent, resumable execution
Every manifest step must be safe to report-as-done and skip on a second
run, and the core must persist enough local state (per `PRD.md` F6) to
know which steps already completed. Violation signal: re-running the
installer after an interruption redoes a step whose effect already
happened, or duplicates a side effect.

**Amended 2026-09-20, narrowed 2026-09-26:** a single `done` flag per
step is not enough state — it can't distinguish "step ran and finished"
from "step started, then the process died before recording completion."
**Per-step state, decided 2026-09-26: two fields, not five.** `verified`
(with the evidence that proved it) and the plugin version the step ran
under. `started` and an inputs hash were considered and dropped:
verification is authoritative once every primitive owns a `verify` mode
(if `verify` passes, "did it start" tells you nothing `verify` doesn't
tell you better; if the user answers differently on re-run, verification
simply fails and the step re-runs, which is the desired behavior without a
separate hash). The plugin-version field is the one that earns its place —
plugin updates are manual (background auto-update is off by default,
verified against the docs), so a user can easily be running a version
behind what their project's state recorded, and the version is the thing a
human can act on. On resume, the core re-checks actual target state
against `verified` rather than trusting a bare `done` flag — see `PRD.md`
F6.

### A4 — Auditable, no unexplained remote execution
Consistent with `install.sh`'s own "no curl-to-bash" principle: no step
executes fetched code the user hasn't been told about and hasn't
approved via the conversation. Unlike `install.sh`, this can't rely on
the user already trusting or reading a shell script — approval has to
come from the plain-language explanation the core already owes them
under A2, not from an assumption that they could audit the code
themselves. `run_approved_command` is the sole seam through which any
command execution happens (see "The decision" above); a shell invocation
anywhere outside it is the violation signal, and is intended to become a
mechanical CI check (`ARCHITECTURE.md`'s "Still open," `check`-script
genre) once there is code to check.

### A5 — Cross-platform prerequisite handling, narrowed 2026-09-26
Prerequisite detection and resolution (`PRD.md` F0-F2) must work
correctly on macOS, Windows, and Linux using each OS's own standard
install mechanisms — never assume a POSIX shell or Unix-style paths are
available, since the non-engineer audience's OS is unknown in advance and
can't be assumed to be a Mac, unlike this project's own development
machine. **This governs the installer's own logic; it does not, by
itself, make the installed guardrails (Bash/`python3`) portable — see
"Build order decided" above and `PRD.md` F1/Portability for the declared
WSL/Git-Bash prerequisite that covers the payload specifically.**
Violation signal: a prerequisite check or fix that only runs under
Bash/POSIX.

### A6 — Bootstrap is a separate admission gate, not a manifest concern
**Added 2026-09-20:** an installer that runs *inside* Claude Code cannot
also install Claude Code — this is a hard boundary, not an open detail to
resolve inside F0-F9. A precondition the core assumes holds before it is
ever invoked, checked and satisfied by a separate admission step outside
the core/manifest system entirely. Violation signal: any manifest or core
primitive that assumes responsibility for getting Claude Code itself
installed or authenticated.

**Narrowed 2026-09-20 (verified against official docs, not a guess):**
the precondition is installing and signing into the **Claude Desktop app**
(macOS/Windows/Linux) — the Desktop app bundles Claude Code, so that alone
gets a non-engineer to a running session capable of real command
execution (app → sign in → Code tab → pick a folder). A separate CLI
install is not required for this and stays optional, only relevant for
someone who later wants to run `claude` from their own system terminal
directly. Don't conflate "Claude Code" with "the standalone CLI package"
when reading this requirement — the admission gate is the Desktop app.

**Widened 2026-09-26:** the admission gate also covers `git` itself
(required to install either plugin from a git-hosted marketplace at all —
F1 can never usefully report it missing, since a machine that got the
plugin already has it) and GitHub-account creation plus `git config`
identity, which the plugin should not decide on a user's behalf. What
stays inside the plugins' reach, as `PRD.md` F0, is `gh auth login`,
`git init`, and `gh repo create` for a repository that doesn't yet exist —
distinct from A6's boundary because none of those three assume
responsibility for installing or authenticating Claude Code itself.

### A7 — Local-scope install structurally confines hooks (decided 2026-09-26)
The `spec-driven-guardrails` plugin (hooks + remaining skills) installs at
**local scope**, inside the target repository the user already confirmed
(`PRD.md` F3), never at user scope. `spec-driven-guardrails-adopt` (the
`/spec-driven-guardrails:adopt` command + adoption-time skills) installs
at **user scope** and carries **no hooks** — it is harmless in any project
because it does nothing until explicitly invoked there. No hook-scoping
self-check ("adoption guard") is part of this design; confinement is
structural, not conventional. Violation signal: any hook shipped in the
user-scope plugin, or the local-scope plugin installed anywhere other
than the confirmed target repository.

---

## System boundaries and ownership

**This describes the target shape once generalized (see "Build order
decided" above), not v1.** For v1, "installer core" and "per-project
manifest" are not separate artifacts — both live inside the two
`spec-driven-guardrails` plugins, as an internal generic-side/
specific-side split within each (own files — a `spec-driven-guardrails`
literal appearing in the generic side's files is the violation signal for
*this* split, distinct from A1's wording-vs-structured-field signal
above). The boundaries below are the design this internal split is
written against, so extracting the generic side later doesn't require
redesigning it — only relocating already-separated code.

- **Installer core** — owns the conversational flow, prerequisite
  detection/resolution, execution engine, progress-tracking state, and
  verification logic. Knows nothing about any specific consuming
  project; everything project-specific arrives only through a manifest.
- **Per-project manifest** — owned by each consuming project (lives in
  that project's own repo, e.g. eventually `spec-driven-guardrails`
  ships its own manifest for this installer to read). Declares
  prerequisites, questions, steps, and verification checks only; may not
  embed executable logic the core doesn't already support as a
  declarative primitive.
- **Claude Code runtime** — interprets the core's instructions together
  with a manifest, in a live conversation with the user; owns nothing
  persistent itself beyond the conversation.
- **Target environment/repo** — the user's own machine and the directory
  the install lands in. The plugins may only write within the target
  directory the user confirmed (F3) and, for the `--user`-scope trigger
  file specifically (`PRD.md` F3), the confirmed user-level location —
  never anywhere else on the user's broader machine beyond installing
  declared prerequisites (with confirmation, per A2/F2).

No component reaches into another's internal state directly: the core
never hardcodes a project's specifics, and a manifest never dictates
core behavior beyond the declarative fields the core defines.

---

## Dependencies

| Dependency | For what | Maintenance and maturity | License | Why not build it ourselves |
|---|---|---|---|---|
| `git` | Version control operations the installer may need to perform or check for on the target; also a precondition of installing either plugin from a git-hosted marketplace at all (A6) | Ubiquitous, extremely mature | GPLv2 | Reimplementing version control is absurd on its face |
| GitHub CLI (`gh`) | Auth flow (F0/F2) and any GitHub-side steps the plugins declare (embedded for v1, manifest-declared once one exists) | Actively maintained by GitHub | MIT | Reimplementing OAuth/GitHub API auth is a security liability, not a savings |
| Claude Code | The runtime that runs the plugins' scripts/skills (embedded core + specifics for v1; core + manifest once separated) and drives the conversation with the user | Actively maintained by Anthropic; this project's entire premise depends on it | Proprietary | This project is explicitly built to run inside it, not as a replacement for it |
| WSL or Git Bash (Windows only) | Runtime for the installed guardrails themselves (`git-guardrails`, other git hooks, traceability checks — Bash/`python3`), declared as a prerequisite rather than reimplemented (decided 2026-09-26) | Ubiquitous on Windows dev machines already running `git` | Various (open source) | Reimplementing the guardrails cross-platform is by far the largest single item in this proposal; declaring the dependency is honest and cheap |
| Manifest format (TBD — likely YAML or Markdown-with-frontmatter) | Declarative per-project configuration | Not yet chosen — open question below | N/A | N/A — decision deferred, not skipped. **Moot for v1** (see "Build order decided" above): no external manifest file exists yet, `spec-driven-guardrails`-specific config lives embedded in the plugins. Becomes relevant again only once a second project's manifest needs to be expressed externally. |

**Prior art informing the manifest/primitive design (not a dependency —
no code reused, reviewed 2026-09-20 as inspiration only):**
[chezmoi](https://github.com/twpayne/chezmoi) — strongest reference for
dry-run, execution ordering, and persistent per-step state; its
[script-state documentation](https://www.chezmoi.io/user-guide/use-scripts-to-perform-actions/)
distinguishes "always run," "run on content change," and "run once,"
directly relevant to F6.
[dotbot](https://github.com/anishathalye/dotbot) — reference for a
compact declarative action language with a deliberately small, idempotent
action set — the shape the primitive list above follows, not a template
for unrestricted shell steps.
[agent-skill-installer](https://github.com/omry/agent-skill-installer) —
reference for install-target scoping (project vs. global), a written
install manifest, and clean uninstall ownership — realized concretely by
A7's local-scope confinement and `PRD.md` F8's native uninstall.

---

## When we would revisit this choice

- **Added 2026-09-20:** a second real project (e.g. `portfolio-mgt-agents`,
  once it has application code) needs the same installer behavior — the
  trigger to extract the plugins' generic side into its own distributable
  "core" plugin (see "Build order decided" above), not before.
- A third consuming project's manifest needs a capability the core's
  declarative primitives can't express (would signal the manifest
  format itself needs to grow, not that Option 2/3 were right after all).
- The bootstrap step (documented as open below) turns out to require
  logic that can't live in a manifest at all — e.g. something that must
  run *before* Claude Code or the core is even reachable — which would
  mean this architecture needs a genuinely different entry point, not
  just a new manifest field.
- Real non-engineer users, once tested against this design, get stuck at
  a step the plain-language narration (A2) doesn't actually resolve for
  them — a usability failure that would call the conversational design
  itself into question, not just its wording. **Not gated as a
  precondition for further funding (decided 2026-09-26)** — see `PRD.md`
  Epics.
- The declared WSL/Git-Bash prerequisite (A5) proves insufficient once a
  real Windows user is tested against it — would reopen whether the
  guardrails themselves need reimplementing cross-platform.

---

## Still open after this document

- **Resolved 2026-09-20: hybrid-core-first vs. single-project-plugin-first.**
  See "Build order decided" above — v1 builds `spec-driven-guardrails` as
  two Claude Code plugins, generic/specific split enforced internally
  within each, core extraction deferred to a second project. No longer open.
- **Resolved 2026-09-20: distribution of the installer core itself, for
  v1.** v1 needs no separate distribution mechanism — two plugins,
  installed the normal Claude Code plugin way (marketplace add + plugin
  install, then the adopt command performing a local-scope install of the
  second). What remains genuinely open is only the *later* question: once
  a second project needs the generic side extracted, plugin inter-plugin
  `dependencies` (`plugin.json`, semver ranges — verified capability) is
  the leading candidate for how that second plugin references the first's
  generic side, not yet a made decision at that point.
- **Resolved 2026-09-26: hook scoping.** See "Build order decided" above,
  "Why two plugins, not one" — local install scope, not a self-check, is
  the mechanism.
- **Resolved 2026-09-26: symlinks vs. copies.** See "The propagation
  decision" above — one mechanism, copies everywhere, `adopt.sh` retired
  on a stated trigger.
- **The manifest format itself** — moot for v1 (see Dependencies table
  above: no external manifest file exists yet). Revisit once a second
  project's specifics need to be expressed outside the plugins that
  currently embed them.
- **The bootstrap problem's concrete resolution** — A6 establishes and
  narrows the admission gate (Claude Desktop app install + sign-in, `git`
  present, GitHub account created — verified against official docs). The
  manual itself is `PRD.md`'s E1, funded and next, but not yet written or
  tested against a real non-engineer. This remains the single largest open
  risk to the whole project's usability goal until it's written and tested.
- **How `portfolio-mgt-agents` will eventually plug in** — that project
  has no application code yet, so there is nothing to write a manifest
  for today; explicitly deferred, not designed against a guess.
- **Q8 from the 2026-09-26 co-thinking session — does F2 ever drive package
  installs, or only detect-and-guide, forever?** Decided for v1: detect
  and guide only (`PRD.md` F2). Revisit only if E1's bootstrap manual, once
  tested, shows a real user demonstrably cannot follow a linked install
  page unaided.
