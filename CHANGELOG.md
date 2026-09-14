# Changelog

Release points: moments where a tag records the merge point as a human
reference point. Adopted projects follow `main` live via symlink, so this
isn't a pinnable version — see "Why local symlinks instead of committed
symlinks" in `README.md`. For the ongoing list of adoptable changes per
project: `CHANGES.md`.

## personal-workflow-to-shareable-product — 2026-09-13

Epic [#52](https://github.com/TiesL/spec-driven-guardrails/issues/52): from
a workflow built for Ties' own multi-machine use into something a stranger
could plausibly adopt — the rename to `spec-driven-guardrails`, the
provider-agnostic boundary (naming only), full translation to English, a
front page ordered for a non-technical reader first, and a tagged,
pinnable install path for a second user (W37, #79).

### Decided in W29 (#53)

Design session with Ties, no code (AC3 of that work item) — four decisions
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
answered what "installing" means for someone who isn't Ties. The current
model — a loose checkout, an environment variable, `adopt.sh` — is a model
for one person on multiple machines, not for a consumer who doesn't want
to follow main. This document previously explicitly excluded "a pinnable
version for consumers" (see "Out of scope" above, and F15's "a tag is a
human reference point, not a pinnable version" — both updated with a
reference here), which contradicted this release's own promise
(shareability).

Decided: consumers pin a **tagged release** (building on W22/#35's
existing tag/CHANGELOG mechanism from epic #11 — F15 correctly described
that mechanism for Ties' own live-via-symlink usage; W37 builds a second,
pinnable path on top of it, not a replacement); the loose-checkout-plus-
env-var model continues to exist alongside it for Ties' own multi-machine
usage. Worked out as a new work item: **W37 (#79)**.

Also decided: `CHANGES.md` is read as **product defaults**, not as Ties'
personal preference register. Every entry thereby implicitly gets a
defensible default for a new adopter; Ties' own answers in the four
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
alle drie. Ties overrulede de blokkade met twee mitigaties: de veldformaten
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
- **Fase 4 — Traceability** (W17 ontwerpreview met Ties, W18 `Dekt:`/`AC<n>`,
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
