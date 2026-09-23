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
primitives, not a general-purpose interpreter.** Concretely: `check_tool`,
`install_package`, `clone_repository`, `copy_template`, `write_config`,
`run_approved_command`, `assert` — 6-8 primitives, each with its own
execution, plan/preview, and verification logic. No general `shell`
primitive in v1: a step a manifest needs that isn't expressible as one of
these primitives is a signal to add a primitive, not to reach for an
escape hatch, because a generic `shell` step would make preview,
cross-platform behavior, safety, and idempotence a per-manifest concern
again — exactly what the core/manifest split exists to avoid.

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

## Build order decided 2026-09-20: plugin-first, single project

This does **not** replace "The decision" above — the target shape (generic
core, small tested primitives, declarative per-project manifests) stays
the intended eventual architecture. What's decided here is *build order*:
v1 does not build that generic core speculatively, ahead of any real
consumer. Instead, v1 turns `spec-driven-guardrails` itself into **one
Claude Code plugin**, with the generic/specific split enforced internally
from day one — a generic side (no `spec-driven-guardrails` literals: the
primitive scripts, state model, preview/verification logic) and a
`spec-driven-guardrails`-specific side (which skills, which templates,
which questions, which git hooks — the plugin's own embedded
configuration, playing the role a per-project manifest will later play).

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
Building the plugin means lifting the first kind out into tested,
parameterized primitives (verifying they carry no project literals as
they move, not just relocating them unchanged) — a split `adopt.sh`
shows is achievable (`lib/`), not one it has already done for these
specific functions — and keeping the second kind as the plugin's own
data.

**Why this order, not core-first:** de-risks the abstraction against a
real consumer before generalizing (this session's second-opinion review's
own recommendation — write one realistic manifest first, derive
primitives from it), and reuses Claude Code's own plugin infrastructure
(inter-plugin `dependencies`, deterministic hook/script execution — see
"Still open"'s "distribution of the installer core itself, for v1" entry
below) instead of hand-building a manifest interpreter and distribution
mechanism before either is proven necessary.

**What stays deferred, not decided against:** extracting the generic side
into its own distributable "core" plugin, which a second project's plugin
would declare as a `dependencies` entry, happens only once a second real
project actually needs it. Until then, "one plugin, internally split" is
the whole system — there is no separate core artifact yet. This is a new
trigger, alongside the existing "third consuming project needs a
capability the primitive set can't express" trigger in "When we would
revisit this choice" below.

**A5 (cross-platform) is not weakened by this.** `adopt.sh` today is
Bash/POSIX-only (`SPEC_DRIVEN_GUARDRAILS_DIR` exported by hand, Bash
scripting throughout) — exactly the shell-comfort assumption this project
exists to remove for a non-engineer audience (`PRD.md` Context). Building
the plugin as a thin wrapper that shells out to `adopt.sh`'s existing
Bash implementation would inherit that limitation and violate A5. The
plugin's own primitive scripts must be written cross-platform-safe
(macOS/Windows/Linux) from the start, even though the project they wrap
currently isn't — reimplementing the relevant logic as tested primitives,
not reusing `adopt.sh`'s script body as-is.

---

## Architecture requirements that follow from this

**"Manifest" below names the concept, not a current artifact.** These
requirements (A1-A6) describe invariants the target shape must hold.
**For v1** (per "Build order decided" and "System boundaries and
ownership"), there is no separate manifest file — "manifest"/"manifest
step" means the `spec-driven-guardrails`-specific side of the plugin's
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

**Amended 2026-09-20:** a single `done` flag per step is not enough
state — it can't distinguish "step ran and finished" from "step started,
then the process died before recording completion." Per-step state must
record at least: `started`, `verified`, a version/hash of the step
definitions it ran under (the plugin's embedded steps for v1, an external
manifest once one exists — see `PRD.md` F1/F6), a hash of the inputs it
ran with, and the verification evidence that proved it succeeded. On
resume, the core re-checks actual target state against `verified` rather
than trusting `started` or a bare `done` flag — see `PRD.md` F6.

### A4 — Auditable, no unexplained remote execution
Consistent with `install.sh`'s own "no curl-to-bash" principle: no step
executes fetched code the user hasn't been told about and hasn't
approved via the conversation. Unlike `install.sh`, this can't rely on
the user already trusting or reading a shell script — approval has to
come from the plain-language explanation the core already owes them
under A2, not from an assumption that they could audit the code
themselves.

### A5 — Cross-platform prerequisite handling
Prerequisite detection and resolution (`PRD.md` F1/F2) must work
correctly on macOS, Windows, and Linux using each OS's own standard
install mechanisms — never assume a POSIX shell or Unix-style paths are
available, since the non-engineer audience's OS is unknown in advance and
can't be assumed to be a Mac, unlike this project's own development
machine. Violation signal: a prerequisite check or fix that only runs
under Bash/POSIX.

### A6 — Bootstrap is a separate admission gate, not a manifest concern
**Added 2026-09-20:** an installer that runs *inside* Claude Code cannot
also install Claude Code — this is a hard boundary, not an open detail to
resolve inside F1-F7. A precondition the core assumes holds before it is
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

---

## System boundaries and ownership

**This describes the target shape once generalized (see "Build order
decided" above), not v1.** For v1, "installer core" and "per-project
manifest" are not separate artifacts — both live inside one
`spec-driven-guardrails` plugin, as an internal generic-side/
specific-side split (own files — a `spec-driven-guardrails` literal
appearing in the generic side's files is the violation signal for *this*
split, distinct from A1's wording-vs-structured-field signal below). The
boundaries below are the design this internal split is written against,
so extracting the generic side later doesn't require redesigning it —
only relocating already-separated code.

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
  the install lands in. The installer may only write within the target
  directory the user confirmed (F3); it may never assume or modify
  anything about the user's broader machine beyond installing declared
  prerequisites (with confirmation, per A2/F2).

No component reaches into another's internal state directly: the core
never hardcodes a project's specifics, and a manifest never dictates
core behavior beyond the declarative fields the core defines.

---

## Dependencies

| Dependency | For what | Maintenance and maturity | License | Why not build it ourselves |
|---|---|---|---|---|
| `git` | Version control operations the installer may need to perform or check for on the target | Ubiquitous, extremely mature | GPLv2 | Reimplementing version control is absurd on its face |
| GitHub CLI (`gh`) | Auth flow (F2) and any GitHub-side steps the plugin declares (embedded for v1, manifest-declared once one exists) | Actively maintained by GitHub | MIT | Reimplementing OAuth/GitHub API auth is a security liability, not a savings |
| Claude Code | The runtime that runs the plugin's scripts/skills (embedded core + specifics for v1; core + manifest once separated) and drives the conversation with the user | Actively maintained by Anthropic; this project's entire premise depends on it | Proprietary | This project is explicitly built to run inside it, not as a replacement for it |
| Manifest format (TBD — likely YAML or Markdown-with-frontmatter) | Declarative per-project configuration | Not yet chosen — open question below | N/A | N/A — decision deferred, not skipped. **Moot for v1** (see "Build order decided" above): no external manifest file exists yet, `spec-driven-guardrails`-specific config lives embedded in the plugin. Becomes relevant again only once a second project's manifest needs to be expressed externally. |

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
install manifest, and clean uninstall ownership.

---

## When we would revisit this choice

- **Added 2026-09-20:** a second real project (e.g. `portfolio-mgt-agents`,
  once it has application code) needs the same installer behavior — the
  trigger to extract the plugin's generic side into its own distributable
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
  itself into question, not just its wording.

---

## Still open after this document

- **Resolved 2026-09-20: hybrid-core-first vs. single-project-plugin-first.**
  See "Build order decided" above — v1 builds `spec-driven-guardrails` as
  one Claude Code plugin, generic/specific split enforced internally, core
  extraction deferred to a second project. No longer open.
- **Resolved 2026-09-20: distribution of the installer core itself, for
  v1.** v1 needs no separate distribution mechanism — it's one plugin,
  installed the normal Claude Code plugin way (marketplace add + plugin
  install). What remains genuinely open is only the *later* question: once
  a second project needs the generic side extracted, plugin inter-plugin
  `dependencies` (`plugin.json`, semver ranges — verified capability) is
  the leading candidate for how that second plugin references the first's
  generic side, not yet a made decision at that point.
- **The manifest format itself** — moot for v1 (see Dependencies table
  above: no external manifest file exists yet). Revisit once a second
  project's specifics need to be expressed outside the plugin that
  currently embeds them.
- **The bootstrap problem's concrete resolution** — A6 establishes and
  narrows the admission gate (Claude Desktop app install + sign-in,
  verified against official docs). The trigger that was blocking the
  actual bootstrap manual (literal step-by-step for a non-engineer) — the
  hybrid-vs-plugin decision — is now met (plugin-first, above). The manual
  itself is still not written; writing it (marketplace-add + plugin-install
  steps, in plain language, following A2) is now unblocked and ready to be
  scheduled as its own piece of work. This remains the single largest open
  risk to the whole project's usability goal until it's written and tested
  against a real non-engineer.
- **How `portfolio-mgt-agents` will eventually plug in** — that project
  has no application code yet, so there is nothing to write a manifest
  for today; explicitly deferred, not designed against a guess.
