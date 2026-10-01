# Changelog

Release points: moments where a tag records the merge point as a human
reference point. An adopted project either follows `main` live via symlink
or pins one of these tags with `install.sh` — see "Getting started" in
`README.md`, which also explains why those symlinks are local rather than
committed. For the ongoing list of adoptable changes per project:
`CHANGES.md`.

**Versioning:** [Semantic Versioning](https://semver.org/) (`MAJOR.MINOR.PATCH`), starting at
`v0.1.0` (2026-09-29) — see that entry for why `0.y.z`, not `1.0.0`, is the deliberate starting
point.

## Unreleased

- **Fix #378: `pre-commit` no longer runs the full `./check`.** It runs the project's declared `check-commit` within a 30 s budget: a static failure blocks, a timeout warns, and the test suite never runs at commit time. A project without `check-commit` gets one warning line, and the full `./check` runs in CI as before. Adopters with a `check`: see `CHANGES.md` `ci-commit-check`.

- **Fix #377: `./check` and the test suite are isolated from git's repo-local environment.**
  git exports `GIT_DIR`, `GIT_INDEX_FILE`, `GIT_PREFIX` and similar variables to hooks; a
  `./check` that ran fixture git commands from the `pre-commit` hook acted on the real repo
  (moved branches, added tags, set `core.bare=true`, rewrote the index of a partial commit).
  `hooks/pre-commit` now clears git's repo-local variables (`lib/git-env.sh`) for the
  `./check` child only, and skips `./check` with a warning if that library is missing;
  `test/lib.sh` clears them on load and `sandbox_guard` refuses if one is set again. Adopted
  projects get this with no action of their own, through the existing `pre-commit` symlink
  (not a project that kept its own pre-existing hook). Accepted cost: a `./check` that
  inspects *staged* content during a partial or `-a` commit now sees the real index, not
  git's temporary one. No `CHANGES.md` entry: there is no choice to make (ARCHITECTURE.md
  A20).

## v0.2.0 — multi-agent development workflow (2026-09-30)

Epic [#295](https://github.com/TiesL/spec-driven-guardrails/issues/295): the multi-agent
development workflow (epic #65's design, accepted 2026-09-21) becomes **executable** — real
scripts and role contracts a fresh session can actually run, not prose an orchestrator
hand-derives from a design document each time. A MINOR bump from `v0.1.0`, not a MAJOR one:
deliberately not `v1.0.0`/`v2.0.0` — the latter would collide with epic #307's own internal
name ("multi-agent workflow v2," the next round of improvements this release's own dogfooding
already surfaced).

### What shipped

- **Compliance-evidence collector** (`compliance-evidence.sh`, W1) — given a PR, renders the
  OQ9 gate/status/evidence table from pre-existing artifacts (model-record markers,
  `pre-merge-review` markers, CI, PR↔issue links). Read-only, no posting, no judgment.
- **Role-contracts skill** (`role-contracts/SKILL.md`, W2) — the five role contracts (Product,
  Architect, QA, Fullstack Developer, Reviewer) as a real, quotable skill: per-role write/action
  scope (A4), floor-or-ceiling input scope (A8), Reviewer's security-trigger table. Supersedes
  the earlier `ROLE-DESCRIPTIONS.md` prose file.
- **Role-label staleness detector** (`role-label-staleness.sh`, W3) — catches a `role:<name>`
  GitHub label that's fallen behind the latest evidenced pipeline stage.
- **Review-depth classifier** (`classify-review-depth.sh`, W4/#328) — decides `quick` vs.
  `thorough` review for a PR, reusing Reviewer's existing six-category security-trigger list;
  `thorough` dispatches Reviewer plus a fixed 2 independent lens-Adapters. The first work item
  this epic ran through the complete five-role pipeline end to end (Product → Architect → QA →
  Fullstack Developer → Reviewer, two review rounds) — the run that resolved OQ11 (below).
- **OQ11 resolved** (issue #294): the multi-agent workflow has now run end-to-end on a real
  work item, with genuine, independently-verified findings surfaced and fixed at every stage.
  Target release: this one.

### BMad Method comparison (methodology credit)

A co-thinking session (issue #324) compared this repo against the
[BMad Method](https://docs.bmad-method.org/) — not adopted wholesale, but directly responsible
for several mechanisms in this release: the `--force-thorough` override and fixed lens-Adapter
count on the review-depth classifier (candidate 2.4), the `adversarial-review` pattern for
co-thinking sessions (candidate 2.5), "built" vs. "done" vocabulary (candidate 2.6), severity
and disposition fields on the finding format (candidates 2.2/2.7), and the halt-preservation
patch-artifact pattern, A12 (candidate 2.8). Explicit non-adoptions are recorded too (BMad's
single-agent build model, standing reviewer personas, `tickets.toml` tracking) — see
`wip/bmad-method-comparison/` for the full reports and decisions.

### Defects found and fixed while dogfooding this epic's own construction

Real correctness gaps, not hypothetical — each found by running the mechanism live, not by
reading the source: a marker merely quoted in prose faking real compliance evidence (#308); a
mawk-specific regex panic silently producing wrong verdicts, not just a crash (#319); GraphQL
`gh` calls blocking entirely from inside a Claude Code session, and separately being blind to
every non-default-branch PR — fixed across four scripts (#318/#320/#323) plus a fifth,
`hooks/git-guardrails`'s own merge guard (#355), found only in this release's own pre-merge
holistic audit. The Reviewer role now posts its own `pre-merge-review:done` marker on approval
(#357), closing a redundant-review-pass gap the pipeline's own dogfooding surfaced.

### Known, deliberately deferred

Filed as debt, not blocking this release: `compliance-evidence.sh`'s test-fixture diversity
(#300), a residual false-`evidenced` edge case in the same script (#338), the same
quoted-marker-as-evidence defect class in two more scripts (#310), a non-deterministic
conflict-message ordering (#304's AC1), shared boilerplate across three scripts with no
common lib (#356), and `finding-carryforward-gate.sh`'s own quoted-string false-positive
(#347). All tracked under epic #307 (v2 backlog).

**Versioning (decided 2026-09-29, issue #348):** releases from this point on are tagged with
[Semantic Versioning](https://semver.org/) (`MAJOR.MINOR.PATCH`), a genuinely new convention
— the two named-slug tags below (`personal-workflow-to-shareable-product`,
`van-proza-naar-mechanisme`) predate it and were never treated as a numbered release scheme.
Starting deliberately at `v0.1.0`, not `v1.0.0`: SemVer's own `0.y.z` range means "initial
development, anything may change," which is honest about where this project actually is
rather than presumptuous about a stability promise it hasn't made. `1.0.0` is a future,
deliberate decision, not something to back into by accident. Each named-slug era below gets
folded into whichever numbered release first covers it once this scheme starts; older
entries keep their original slug names as the historical record they already are.

## v0.1.0 — 2026-09-29

Everything on `main` up to this point, retroactively version-tagged as the starting line for
SemVer going forward — not a new epic of its own, but the first point this repo commits to a
numbered release identity. Encompasses both prior named releases below in full, plus
everything since `personal-workflow-to-shareable-product` (2026-09-13):

- **Full Dutch→English translation completed** (W40-W43, issues #118-#207): every script,
  skill, hook, test file, and identifier this repo's own code touches — not just prose. What
  `personal-workflow-to-shareable-product`'s decision 3 scoped (layers A and B) is now fully
  executed, not just decided.
- **This repo adopts its own workflow** (#102): the self-adoption exception that used to
  exclude `spec-driven-guardrails` itself from `adopt.sh` is gone — this repo now follows the
  same rules it enforces on adopted projects.
- **Traceability hardened**: the 4th link (issue → acceptance-criteria structure, #251),
  drift guards between `check-traceability.sh` and `templates/` (#232), heading-correspondence
  enforcement between `test/cases/` and `TEST-SCENARIOS.md` (#273), and machine-readable
  model-record/finding-carryforward gates (#249) that make `pre-merge-review`'s own process
  mechanically checkable instead of resting on an agent remembering to follow it.
- **CI and commit-time enforcement tightened**: `./check` wired into `pre-commit`, blocking a
  bad commit before it lands (#269); `gitleaks` secret-scanning in `pre-push` with a CI
  backstop (#270); the merge guard extended to block a stray commit-level `Closes #N` the
  PR's own title/body doesn't share (#224); `wait-for-ci.sh` encoding the 5-minute-then-1-
  minute polling cadence as a script instead of a norm an agent has to remember (#279).
- **`model-choice` skill added** (#236): capability/cost-aware model selection guidance at
  every stage of a work item's pipeline, not just review.
- **Epic #65 (multi-agent development) begins as design work**: direction accepted, a
  co-thinking session on turning `spec-driven-guardrails` into a Claude Code plugin, and W1
  (the compliance-evidence collector, #296/#298) as the epic's first concrete artifact — still
  exploratory at this point (`wip/multi-agent-development/`, directional, explicitly marked
  **TBD**), not yet an executable, dogfooded pipeline. That's `v0.2.0`'s scope (issue #349),
  not this one's.

## personal-workflow-to-shareable-product — 2026-09-13

Epic [#52](https://github.com/TiesL/spec-driven-guardrails/issues/52): from
a workflow built for TiesL's own multi-machine use into something a stranger
could plausibly adopt — the rename to `spec-driven-guardrails`, the
provider-agnostic boundary (naming only), full translation to English, a
front page ordered for a non-technical reader first, and a tagged,
pinnable install path for a second user (W37, #79).

### Decided in W29 (#53)

Design session with TiesL, no code (AC3 of that work item) — four decisions
that steered this epic, each with its reasoning. Follow-up items that
anticipated this were updated: W31 (#55), W32 (#56), W33 (#57), W35 (#59),
and epic #52 itself.

**Revised after an independent second opinion** (a fresh model, with no
context from the design session itself, asked to critique purely the
content of the four decisions — not the writing). That review found a hard
naming collision and three substantiations that had the right outcome for
a weak reason. All four were adjusted as a result; decision 5 is new and
follows from a gap the review exposed.

#### 1. The name: `spec-driven-guardrails`

**Revised.** The original working title `agentic-SDD-workflow` turned out,
on external research, to be **GitHub's own Spec Kit's term** for its
methodology ("Agentic SDD"). For the audience that knows this field, that
name reads as a derivative of Spec Kit, not as something standalone — and
the field is already full of similar names anyway (`cc-sdd`,
`agentic-sdlc-spec-kit`, `specky`). For a release whose whole point is
shareability, that's not a detail.

`spec-driven-guardrails` — the previously considered and dropped
alternative — collides with nothing and puts the emphasis on what
distinguishes this project from an arbitrary SDD approach: **the
enforcement**, not yet another spec generator. It also avoids the
acronym that collided with decision 4's audience. Consistently lowercase
(no mixed casing) — it becomes a directory name, a repo URL, and the basis
of an environment variable, and mixed casing is a known source of
cross-platform trouble there.

#### 2. Provider-agnostic: level a — naming only

Of the three levels (a: name it, b: an adapter layer with one
implementation, c: build a second implementation alongside it), **a** was
chosen. The boundary between agent-independent and Claude-Code-specific
(see W31/#55) gets documented, not built as a contract.

**Substantiation revised.** The original reason ("a contract with no
second implementation stays an assumption") proves too much — by that
reasoning, no abstraction is ever justified before its second consumer.
The real reason is a rule-of-three: there's no second agent in sight and
no concrete requester, so a contract is speculative right now. The
strongest reason was already there, but in second place: epic #52's own
boundary ("no new functionality").

**The risk that *is* real:** after this release, the product presents
itself externally as neutral (new name, a front page for a non-technical
reader), while it's 100% tied to Claude Code — hooks, skills,
`.claude/settings.json`. That's not technical debt but promise debt, sold
to exactly the new reader. To make level a strong rather than merely
cheap, W31 (#55) gets two concrete steps added to it: a `check` test that
enforces the boundary (not just describes it), and a one-time measurement
of what actually still works without Claude Code.

The existing technical-debt row ("Skills bind this repo to Claude Code")
isn't closed by this decision — that only happens once W31 delivers the
boundary table and the two steps above, and then not as "resolved" but as
"deliberately bounded, with a concrete trigger to go further (level b or
c)".

#### 3. Translation scope: A + B, via a criterion — not via a list

That this repo itself — documentation, hook messages, test names,
comments — becomes English isn't in question; that's W33 (#57)'s main
work. What this decision is actually about: which pieces of that
translation move along in the four Dutch adopted projects, where they
aren't translated themselves.

**Revised: the criterion replaces the enumeration.** The original list
(two items: entry IDs and `**Dekt:**`/`AC<n>`) turned out, on closer
inspection, to be incomplete — the review independently found at least
five machine-matched Dutch tokens missing from it (the filename
`WORKFLOW-ADOPTIE.md` itself, the `ja`/`nee` answer values, the "requires
substantiation" stamp, the `.gitignore`-managed block marker, and the
issue templates that get refreshed on every `adopt.sh` run anyway). A
hand-maintained list has exactly the failure mode this decision says it's
fighting: something gets missed and quietly falls through.

The underlying, actually durable criterion:

> **Migrates along: every literal string that a script from this repo
> matches in a file of another repo.**

That's layer **A** (physically shared files — symlinks: `CLAUDE.md`,
`WORKFLOW.md`, `skills/*/SKILL.md`, `session-hooks.json`) plus layer **B**
(shared vocabulary that sits as a loose token in someone else's file, and
that a script from this repo reads back). W33 (#57) generates the full
inventory of layer B by searching the scripts themselves for what they
match in other files, instead of trying to keep the list here complete by
hand.

Explicitly out of scope stays a third layer, **C — scaffolded document
headings and script output** (e.g. `check-traceability.sh`'s own messages
*inside* the four projects) that, after scaffolding, have become locally
owned by those projects, and that no script from this repo reads back.
That doesn't migrate along. Newly scaffolded copies, for future projects,
are English — the source templates in `templates/` are part of this repo
and so do migrate.

Considered and not chosen: backward-compatible parsers (e.g. letting both
`Dekt:` and `Covers:` work, with a transition warning) instead of a single
migration. That would avoid the cross-repo mutation, but wasn't chosen
because it keeps the dual-language period open-ended — exactly what this
repo elsewhere (see R9, the baseline) tries to prevent.

#### 4. Front page: which question gets answered first — not which reader is primary

**Revised.** "The functional reader is primary" turned out to have two
gaps: the original substantiation ("the developer finds their way via
`WORKFLOW.md`") is insider logic — that file is agent-instruction text,
not an installation manual, and so no guide for a genuine outsider. More
importantly: the functional reader can't take the first installation step
(cloning, setting an environment variable, running a bash script, having
Claude Code) themselves anyway — a front page optimized for someone who
can't act on it converts nothing.

The question therefore isn't "which reader is primary," but **which
question gets answered first**: functional framing above the fold (what
problem, for whom, what does it cost — business analysts, product owners,
and product managers read that first), followed by a self-contained
developer section that's complete on its own for installing, with no need
to have read the rest. W35 (#59) gets an extra acceptance criterion for
this: a developer who never saw the repo installs it using only
`README.md`.

#### 5. Installation and update model: a tagged, pinnable release

**New, from the second opinion.** None of the four original decisions
answered what "installing" means for someone who isn't TiesL. The current
model — a loose checkout, an environment variable, `adopt.sh` — is a model
for one person on multiple machines, not for a consumer who doesn't want
to follow main. This document previously explicitly excluded "a pinnable
version for consumers" (see "Out of scope" above, and F15's "a tag is a
human reference point, not a pinnable version" — both updated with a
reference here), which contradicted this release's own promise
(shareability).

Decided: consumers pin a **tagged release** (building on W22/#35's
existing tag/CHANGELOG mechanism from epic #11 — F15 correctly described
that mechanism for TiesL's own live-via-symlink usage; W37 builds a second,
pinnable path on top of it, not a replacement); the loose-checkout-plus-
env-var model continues to exist alongside it for TiesL's own multi-machine
usage. Worked out as a new work item: **W37 (#79)**.

Also decided: `CHANGES.md` is read as **product defaults**, not as TiesL's
personal preference register. Every entry thereby implicitly gets a
defensible default for a new adopter; TiesL's own answers in the four
existing projects remain as a worked example, not as a prescription. Also
worked out in W37 (#79) — that text in `CHANGES.md`'s intro changes along
with it.

## van-proza-naar-mechanisme — 2026-09-06

Epic [#11](https://github.com/TiesL/claude-workflow/issues/11): de conventies
van dit repo verplaatsen van proza (tekst die onthouden moet worden) naar
mechanisme (hooks, scripts, `check`, skills), overal waar handhaving mogelijk
is. Aanleiding: over vier projecten en 27 gemergede PR's verwees **nul** PR's
naar een issue, had **nul** een kwaliteitsreview, en was
`quality-review-before-merge` door geen enkel project ooit beantwoord — terwijl
`WORKFLOW.md` dat allemaal al voorschreef.

### Herkomst en volgordebesluiten

Dit epic verving drie eerder los aangemaakte epics —
[#7](https://github.com/TiesL/claude-workflow/issues/7),
[#8](https://github.com/TiesL/claude-workflow/issues/8),
[#9](https://github.com/TiesL/claude-workflow/issues/9) — nadat de
kwaliteitsreview op PR #6 vier structurele problemen (→ #7) en een
traceability-gat (→ #8) blootlegde; #9 kwam later, vanuit een vergelijking met
`mattpocock/skills`.

**Overrulen van de "één echt work item end-to-end"-blokkade.** #7 en #8 waren
daarop geblokkeerd; de beste kandidaat (tennis-admin PR #5) haalde het niet —
issue vooraan, review in het midden en acceptatietest vóór de merge ontbraken
alle drie. TiesL overrulede de blokkade met twee mitigaties: de veldformaten
uit #8 eerst samen doornemen (W17, menselijke review in plaats van het
ontbrekende praktijkbewijs), en de nulmeting vastleggen als uitvoerbare tests
vóór er iets verandert (W1-W3) — refactoren tegen aannames is precies wat de
blokkade moest voorkomen, tests waren het alternatieve vangnet.

**De afgesproken volgorde (a)-(b)-(c)-(d) stond op één plek** — de body van
#8 — en is nooit op GitHub bediscussieerd: #7 verwijst alleen naar "de
discussie in #6", en PR #6 zelf heeft precies één comment, nul reviews, nul
inline-opmerkingen, en noemt geen volgorde. Het gesprek liep in een
chatsessie. De wél opgeschreven rationales bleken smaller dan de volgorde die
eruit werd afgeleid: "refactoren tegen een ongebruikte workflow refactort
tegen aannames" raakte de skills-migratie en de veldformaten, niet het
dedupliceren van een `case` of het uitvoerbaar maken van tests — die waren
intern en toetsbaar zonder praktijkbewijs.

**Volgorde in fasen** (werkitem-ID's `W<n>` zijn de schakel naar de
GitHub-issues van destijds):

- **Fase 0 — Fundament, geen gedragsverandering** (W1 testharnas + `check` +
  CI, W2 nulmeting-fixtures voor alle vier projecten, W3 R1-R4/R6/R9 als
  tests tegen ongewijzigde `main`, W16 blocking-edges in issue-templates,
  W12b documentatiecorrecties). W3 was de kern van de mitigatie: groen op
  ongewijzigde `main`, vóór er iets veranderde.
- **Fase 1 — Refactors, aantoonbaar gedragsbehoudend** (W4 gedeelde parser +
  predicaten, W5 nfr-register + generator, W6 changes-archief, W7
  onderbouwingssignaal, W10 git-guardrails-hook, W23 sessiestart-melding, W24
  `ci.yml` valideert PR's/`main`). W4 moest vóór alles wat een derde
  consument aan de duplicatie toevoegde; W5 haalde de duplicatie echt weg in
  plaats van hem te overbruggen. **W10 hoorde hier en niet later**: de
  hookconfiguratie is gesymlinkt en dus live na `git pull`, het guard-script
  arriveert via diezelfde pull en wordt gevonden via de bestaande
  `readlink`-keten — `adopt.sh` speelt geen rol. Het was bovendien de
  grootste directe veiligheidswinst van de release, dus hoorde alleen het
  testharnas (W1) hem te blokkeren.
- **Fase 2 — De structurele wijziging, hoogste risico** (W8 `adopt.sh`
  installeert skills + hooks, W9 `WORKFLOW.md` → kern + Wegwijzer). W8 vóór
  W9: installer-eerst-met-no-op was strikt veiliger dan een vroege puller die
  naar nog niet geïnstalleerde skills zou verwijzen.
- **Fase 3 — Skills en guards** (W13 `pre-merge-review`-scoping, W10b
  merge-guard, W14 `tdd-seams`, W15 `diagnose-bug`, W16b `CONTEXT.md`, W25
  push-na-commit, W26 git-hooks in het project).
- **Fase 4 — Traceability** (W17 ontwerpreview met TiesL, W18 `Dekt:`/`AC<n>`,
  W19 offline traceability-check, W19b CI-hard-slot, W20 PR-poort, W27 CI
  detecteert `main` buiten een PR).
- **Fase 5 — Release** (W21 PR-linkbacks herstellen, W22 dit `CHANGELOG.md` +
  tag + `README.md`).

**Uitbreiding na het doorlichten van de dekking.** W23-W27 stonden niet in de
oorspronkelijke opzet — ze kwamen er nadat, ná afronding van W10, bleek dat de
guard alleen dekt wat Claude zelf uitvoert, niet wat in een eigen terminal,
een IDE, of op een tweede machine gebeurt. Zie F17 in `PRD.md` voor de
blijvende specificatie van die dekking; deze vier werkitems zijn de
implementatie ervan. Ingevoegd op de plek waar hun afhankelijkheden ze
toelieten, niet achteraan: W23 en W24 hingen alleen van het testharnas af (W24
inhoudelijk van niets, maar rood-vóór-groen gold ook voor hem) en kwamen dus
in Fase 1; W25 en W26 hingen aan de guard zelf (W26 ook aan `adopt.sh`) en
volgden in Fase 3; W27 had het bijgewerkte CI-sjabloon nodig en landde in
Fase 4.

**Extra verificatieronde nodig bevonden voor:** W2 (een onherhaalbare
nulmeting als hij fout werd vastgelegd), W8 (schrijft in andermans repo's,
migreert een getrackte `.gitignore`), W9 (betekenisverlies dat `grep` niet
ziet), W10 en W10b (een vals positief blokkeert werk in élk project, en
bereikt ze zónder her-adoptie omdat de hookconfiguratie gesymlinkt is), en W26
(schrijft git-hooks in andermans repo's, en een te strenge hook blokkeert
daar élk commando, niet alleen dat van Claude).

**Vereiste actie na deze release, per project en per machine:**

- Draai `adopt.sh` opnieuw in elk geadopteerd project (`a2t-emails`,
  `tennis-admin`, `tennis-registration`, `tennis-invoicing`), op elke machine
  waarmee je eraan werkt — dat ververst de skill-symlinks en de nieuwe
  `CHANGES.md`-vragen verschijnen als openstaand. Sjablonen die al bestaan
  (`ci.yml`, `PRD.md`, …) worden **niet** overschreven; alleen wat nog
  ontbreekt wordt gescaffold, en de issue-templates worden altijd ververst.
- Draai `adopt.sh --user` één keer op elke machine waarmee je aan deze
  projecten werkt. Zonder die stap ontbreekt de user-level skill
  `adopt-workflow`, en verwijst de bijgewerkte `USER-CLAUDE.md` naar iets dat
  er niet is — precies in een nog niet-geadopteerd project, waar je het niet
  merkt.

**Belangrijkste toevoegingen:**

- Hooks: `git-guardrails` tegen destructieve git-commando's, en (W10b) de
  merge-guard op `gh pr merge` zonder review-marker.
- `check`: NFR-registerdrift, PR-linkbacks in `CHANGES.md`, en (per project,
  via `check-traceability.sh`) traceability-schakel 1.
- CI: een hard slot op "PR verwijst naar issue" (W19b).
- `pre-merge-review`: echte scoping in plaats van proza (W13), plus een
  PR-poort voor schakel 2 en 3 (W20).
- Negen skills, waaronder de nieuwe `tdd-seams` en `diagnose-bug` (W14, W15).
- `templates/CONTEXT.md`, een optioneel begrippenkader per project (W16b).
- De nulmeting-fixtures vriezen nu ook het `nfr/`-register in, niet alleen
  `CHANGES.md` (W28).

Volledig overzicht: de work items onder epic
[#11](https://github.com/TiesL/claude-workflow/issues/11).
