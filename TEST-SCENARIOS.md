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
  `proces-issue-tracking`, `test-integratie`, `spec-performance-schaal`,
  `spec-compliance`, `spec-portability`, `spec-usability`, `spec-kostenbeheersing`

### R3 — `package.json` makes `ci-conventie` relevant
**Covers:** F3
- Given: the same project, now with a `package.json`
- When: `pending-changes.sh .` is run
- Then: `ci-conventie` additionally appears as pending

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
- Given: four test projects (with/without `package.json` × with/without a `"deploy"` script)
- When: the seed logic and `predicaat_waar()` both evaluate
  `heeft-package-json` and `heeft-deploy-script` against each of the four
- Then: both reach exactly the same answer for every combination
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
- Given: the frozen nulmeting fixtures of `tennis-admin`,
  `tennis-registration`, `tennis-invoicing`, and `a2t-emails`
- When: `pending-changes.sh` runs against each fixture after the refactor
- Then: the number and identity of pending questions is exactly equal to
  the baseline
- And: if this diverges, the test fails naming the difference per ID — a
  silent change in the question set is never acceptable, not even as
  "cleanup"

### S66 — The source of the question set is fully frozen, including the nfr part
**Covers:** F2
- Given: the nulmeting fixtures, after W28
- When: a golden set is recomputed
- Then: every `spec-*` ID in it traces back to a frozen file in
  `test/fixtures/nulmeting/nfr.momentopname/`, verbatim equal to
  `CHANGES.md.momentopname`'s form
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
  `nfr.momentopname` must then deliberately change along with it, with an
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

### S4 — The nulmeting fixture records `a2t-emails` as found
**Covers:** F2
- Given: `a2t-emails` has no `WORKFLOW-ADOPTIE.md`
- When: the nulmeting fixture is created
- Then: the fixture records "everything pending"
- And: no `WORKFLOW-ADOPTIE.md` is created or fixed — the fixture holds
  the state, not the repair

---

## NFR register and archive

### S38 — A field with no preceding heading yields no entry
**Covers:** F3
- Given: a malformed source where an `Applies if` field appears before the
  first `## ` heading
- When: `itereer_entries` reads that source
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
- And: both scripts **actually call** `predicaat_waar` from the library —
  established by instrumenting and running the function, not by searching
  text. A text match only sees literal copies; logic rewritten in another
  form slips through unnoticed

### S36 — An ID inside a note doesn't count as an answer
**Covers:** F3
- Given: a `WORKFLOW-ADOPTIE.md` where the ID of a still-unanswered change
  appears in the free-text note of a *different* row
- When: `pending-changes.sh` runs
- Then: that change is still pending — only the ID column counts as an
  answer
- And: notes are free text and IDs like `test-integratie` are ordinary
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
- Given: an adopted project with a well-formed `WORKFLOW-ADOPTIE.md` —
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

### S16 — Merge mét review-marker gaat door
**Covers:** F8
- Given: een open PR met de marker die `pre-merge-review` plaatst
- When: `gh pr merge` wordt aangeroepen
- Then: het commando gaat door

### S17 — De merge-guard faalt open zonder netwerk
**Covers:** F8
- Given: `gh` ontbreekt of heeft geen netwerkverbinding
- When: `gh pr merge` wordt aangeroepen
- Then: er verschijnt een luide waarschuwing dat de reviewcontrole is overgeslagen
- And: het commando wordt toegestaan

### S18 — Een onderbouwde `nee`/`no` schakelt de guard uit
**Covers:** F8
- Given: een project waarvan `WORKFLOW-ADOPTIE.md` (pre-migratieformaat, W42/#114)
  of `WORKFLOW-ADOPTION.md` `kwaliteitsreview-voor-merge` respectievelijk
  `quality-review-before-merge` op `nee`/`no` heeft staan
- When: `gh pr merge` wordt aangeroepen op een PR zonder marker
- Then: het commando gaat door, zonder blokkade
- And: dat gebeurt zonder netwerkaanroep — de rij wordt lokaal gelezen

### S64 — De merge-guard-uitweg schakelt alleen de merge-guard uit
**Covers:** F8
- Given: hetzelfde commandosegment bevat zowel
  `CLAUDE_WORKFLOW_MERGE_GUARD_UIT=1` als een destructief git-commando
  (bijvoorbeeld `git reset --hard`)
- When: dat segment beoordeeld wordt
- Then: het destructieve git-commando wordt nog steeds geblokkeerd
- And: de uitweg schakelt uitsluitend de merge-guard uit, niet de rest van
  git-guardrails — anders is de luide, gerichte uitweg uit AC6 in de praktijk
  een blanco vrijbrief voor het hele segment

### S65 — Waardevlaggen van `gh pr merge` schuiven het doel niet op
**Covers:** F8
- Given: `gh pr merge --body "een tekst met woorden" --subject "titel"` zonder
  expliciet PR-nummer/url/branch
- When: de merge-guard het doel bepaalt
- Then: hij vraagt de PR van de huidige branch op (`gh pr view` zonder
  argument), niet `gh pr view "een tekst met woorden"`
- And: een marker-loze PR wordt dus nog steeds geblokkeerd, in plaats van via
  het faal-openpad (een mislukte opvraging van een niet-bestaande "PR" met die
  naam) alsnog toegelaten te worden

### S73 — Merge wordt geblokkeerd als CI niet groen is
**Covers:** F8
- Given: een PR met de review-marker, maar met een check die faalt
- When: `gh pr merge` wordt aangeroepen
- Then: het commando wordt geblokkeerd, met de naam van de falende check in de
  melding

### S74 — Merge gaat door als alle checks slagen
**Covers:** F8
- Given: een PR met de review-marker en alle checks `pass`
- When: `gh pr merge` wordt aangeroepen
- Then: het commando gaat door

### S75 — Geen gerapporteerde checks blokkeert niet
**Covers:** F8
- Given: een PR met de review-marker, maar zonder gerapporteerde checks (geen
  CI geadopteerd voor dat project, zie F6)
- When: `gh pr merge` wordt aangeroepen
- Then: het commando gaat door — geen checks is geen rode vlag

### S76 — De CI-controle faalt open als de opvraging zelf mislukt
**Covers:** F8
- Given: een PR met de review-marker, maar de CI-opvraging zelf mislukt (geen
  netwerk, geen toegang)
- When: `gh pr merge` wordt aangeroepen
- Then: er verschijnt een luide waarschuwing dat de CI-controle is
  overgeslagen
- And: het commando wordt toegestaan

---

## Skills-infrastructuur

### S19 — `adopt.sh` installeert per-skill symlinks
**Covers:** F9
- Given: een geadopteerd project en een gevulde `skills/`-map in dit repo
- When: `adopt.sh` draait
- Then: `.claude/skills/<naam>` bestaat per skill als symlink naar dit repo
- And: `.claude/skills` zelf is een echte map, geen symlink

### S20 — Verweesde symlinks worden opgeruimd, echte mappen niet
**Covers:** F9
- Given: `.claude/skills/oude-naam` wijst naar een niet meer bestaande skill in
  dit repo, en `.claude/skills/eigen-skill` is een echte map van het project
- When: `adopt.sh` draait
- Then: `oude-naam` is verwijderd
- And: `eigen-skill` is onaangeroerd

### S21 — Het `.gitignore`-blok wordt beheerd, niet gestapeld
**Covers:** F9
- Given: een `.gitignore` met de twee bestaande losse regels `CLAUDE.md` en
  `.claude/settings.json`
- When: `adopt.sh` draait
- Then: die regels staan precies één keer, binnen het beheerde blok
- And: regels buiten het blok blijven onaangeroerd

### S22 — `adopt.sh` is idempotent
**Covers:** F9
- Given: een geadopteerd project
- When: `adopt.sh` twee keer achter elkaar draait
- Then: de bestandsboom is na de tweede run identiek aan na de eerste
- And: `.gitignore` is byte-identiek

### S23 — `adopt.sh` is een no-op zonder `skills/`
**Covers:** F9
- Given: een checkout van dit repo van vóór deze release, zonder `skills/`-map
- When: `adopt.sh` draait
- Then: de adoptie slaagt zonder foutmelding
- And: er wordt geen lege `.claude/skills/` achtergelaten

---

## Skills en review

### S24 — Elke skill in het register bestaat en is vindbaar
**Covers:** F10
- Given: het skill-register uit `PRD.md` F10
- When: `./check` draait
- Then: elke genoemde skill heeft een `SKILL.md` met een `name` en `description`
  in de frontmatter

### S25 — De user-level skill staat op userniveau
**Covers:** F10
- Given: een niet-geadopteerd git-project
- When: `adopt.sh --user` is gedraaid en een sessie start
- Then: `adopt-workflow` is beschikbaar zonder dat `.claude/skills/` in dat
  project bestaat

### S68 — `tdd-seams` benoemt de discipline concreet, niet aansporend
**Covers:** F10
- Given: `skills/tdd-seams/SKILL.md`
- When: hij gelezen wordt
- Then: hij noemt "seam", "rood" én "groen" (rood-vóór-groen), en de drie
  anti-patronen met naam: implementatie-gekoppeld, tautologisch, en
  horizontaal slicen tegenover verticale slices

### S69 — `diagnose-bug` beschrijft de dwingende volgorde
**Covers:** F10
- Given: `skills/diagnose-bug/SKILL.md`
- When: hij gelezen wordt
- Then: reproductie, hypotheses en regressietest staan er alle drie in, in die
  volgorde vóór de fix
- And: het staat er expliciet bij dat hypotheses getoond worden vóórdat ze
  getest worden

### S70 — `CONTEXT.md` wordt gescaffold zodra de rij op `yes`/`ja` staat
**Covers:** F10
- Given: een project waarvan `WORKFLOW-ADOPTION.md` (of, pre-migratie
  W42/#114, `WORKFLOW-ADOPTIE.md`) `process-context-document`
  respectievelijk `proces-context-document` op `yes`/`ja` heeft staan
- When: `adopt.sh` draait
- Then: `CONTEXT.md` wordt aangemaakt vanuit `templates/CONTEXT.md`, als het
  nog niet bestaat
- And: een al bestaand `CONTEXT.md` wordt nooit overschreven
- And: staat de rij op `nee` of ontbreekt ze, dan scaffoldt `adopt.sh` niets

### S26 — De reviewscope volgt de beantwoorde `spec-*`-rijen
**Covers:** F11
- Given: een project waarvan `WORKFLOW-ADOPTIE.md` alleen `spec-security` en
  `spec-data-integriteit` op `ja` heeft
- When: `pre-merge-review` draait
- Then: de scope bevat complexiteit en dependencies plus precies die twee NFR's
- And: NFR's die op `nee` of onbeantwoord staan komen niet in de scope

### S27 — Ontbrekende ankers degraderen, ze blokkeren niet
**Covers:** F11
- Given: een project-PRD zonder de door F4 geplaatste ankers
- When: `pre-merge-review` draait
- Then: de skill valt terug op de kopnamen
- And: hij meldt expliciet dat de ankers ontbreken

### S28 — De review plaatst een machineherkenbare marker
**Covers:** F11
- Given: een PR waarop `pre-merge-review` zijn bevindingen plaatst
- When: de merge-guard die PR daarna beoordeelt
- Then: de marker wordt gevonden en de merge wordt toegestaan

### S29 — De Wegwijzer lost elk verplaatst onderwerp in één sprong op
**Covers:** F12
- Given: de vijf termen uit R7 (branching, kwaliteitsreview, onderbouwingsplicht,
  deploy-guards, adoptieregistratie)
- When: `WORKFLOW.md` op elk van die termen wordt gegrept
- Then: voor kwaliteitsreview, onderbouwingsplicht, deploy-guards en
  adoptieregistratie — die zíjn verplaatst — levert elke term een Wegwijzer-rij
  op die naar precies één bestaande skill verwijst
- And: twee termen die in dezelfde skill landen krijgen twee eigen rijen
- And: branching is niet verplaatst (F12 houdt branchstrategie in de kern) en
  lost dus op zoals R7 dat toestaat: direct in het bestand, zonder
  Wegwijzer-rij

---

## Traceability

### T1 — Volledige keten, alles gedekt
**Covers:** F13
- Given: `PRD.md` met `F1`; `TEST-SCENARIOS.md` met `S1` (`Covers: F1`) en `S2`
  (`Covers: F1`); een issue dat `S1` en `S2` noemt; een PR die naar dat issue verwijst
- When: de controle draait
- Then: geen fouten, exit 0

### T2 — Functionaliteit zonder scenario
**Covers:** F13
- Given: `PRD.md` met `F2`, geen enkel scenario met `Covers: F2`
- When: de controle draait
- Then: faalt met een melding die expliciet `F2` noemt

### T3 — Scenario zonder issue
**Covers:** F13
- Given: `S3` bestaat, geen enkel issue noemt `S3` in het daarvoor bestemde veld
- When: de poort in `pre-merge-review` draait
- Then: de bevinding noemt expliciet `S3`

### T4 — PR zonder gelinkt issue
**Covers:** F13
- Given: een PR zonder `Closes #<n>` en zonder gelinkt issue
- When: de CI-check op de PR draait
- Then: de check faalt en noemt de betreffende PR

### T5 — Vals-positief voorkomen
**Covers:** F13
- Given: een issue-tekst die `S1` noemt in een zin die geen verwijzing is
  (bijv. "we hebben inmiddels s1 varianten getest")
- When: de controle draait
- Then: dit telt **niet** mee als schakel — alleen het daarvoor bestemde veld telt
- And: een token als `S2b` telt wél, mits het in het veld staat

### S30 — Dubbele en onbekende ID's worden gemeld
**Covers:** F13
- Given: een `TEST-SCENARIOS.md` met twee scenario's die hetzelfde ID dragen, en
  een `Covers:`-token dat nergens oplost
- When: de offline controle draait
- Then: beide problemen worden apart gemeld, met ID
- And: een `PRD.md` zonder enig `F<n>` levert een **waarschuwing** op, geen harde fout

### S62 — Zonder dekkingsvelden waarschuwt de controle, en handhaaft niet
**Covers:** F13
- Given: een project waarvan geen enkel scenario een `**Covers:**`-veld draagt —
  alle vier de bestaande projecten zijn dit geval op de dag van invoering
- When: de offline controle draait
- Then: er verschijnt een waarschuwing en exit 0
- And: er wordt geen enkel ongedekt item gemeld. Zonder die uitzondering klaagt
  de controle bij invoering in één klap over álles, en dat is de retrofit die
  het ontwerp juist vermijdt
- And: zodra het eerste `**Covers:**`-veld er staat, handhaaft hij wél — anders kan
  één verwijzing de rest ongestraft laten liggen

### S63 — De controle wordt gescaffold en draait in een vers project
**Covers:** F13
- Given: een project dat `adopt.sh` voor het eerst draait
- When: de adoptie klaar is
- Then: `check-traceability.sh` staat er, uitvoerbaar
- And: hij draait daar zonder te falen — een scaffold die meteen rood staat,
  wordt bij de eerste aanraking uitgezet
- And: een eigen versie van dat bestand wordt niet overschreven

### S71 — Bestaande projecten krijgen de schakel-3-vraag alsnog voorgelegd
**Covers:** F13
- Given: een project met een `package.json` en een al bestaande `ci.yml` die
  `check-pr-issue-link.sh` niet aanroept (W19b's `scaffold_if_missing` laat
  zo'n bestand ongemoeid — het sjabloon repareren helpt alleen nieuwe
  projecten, zelfde patroon als `ci-op-pr-en-main` bij W24)
- When: `pending-changes.sh` draait
- Then: een nieuwe entry verschijnt als openstaand
- And: een project zonder `package.json` krijgt die vraag niet

---

## Issue-templates en release

### S31 — Blocking-edges staan in beide issue-templates
**Covers:** F14
- Given: `templates/ISSUE_TEMPLATE/work-item.md` en `epic.md`
- When: een issue vanuit het sjabloon wordt aangemaakt
- Then: beide bevatten een `**Blocked by:**`- en een `**Blocks:**`-veld, aan
  regelbegin en in de `**Veld:**`-vorm die de bestaande issues gebruiken
- And: een variant als `- Blocked by:` telt niet — die leest voor een mens
  hetzelfde en is voor een grep iets anders, en dan levert de conventie geen
  graaf op maar een gevoel
- And: een project met een verouderd sjabloon krijgt het nieuwe bij de
  eerstvolgende adoptie

### S60 — Acceptatiecriteria in het sjabloon heten `AC<n>`
**Covers:** F13
- Given: `templates/ISSUE_TEMPLATE/work-item.md`
- When: een issue vanuit het sjabloon wordt aangemaakt
- Then: de acceptatiecriteria zijn `AC<n>` genummerd, niet `S<n>`
- And: zolang een issue zijn eigen criteria `S1` noemt, raakt elke `grep` naar
  scenarioverwijzingen het issue zelf — dan is schakel 2 niet controleerbaar
- And: dit scenario hoort bij W18 en wacht op de uitkomst van W17; valt die
  hernoeming anders uit, dan verandert dit scenario mee
- And: dit dekt **F13**, niet F14. De ongesplitste S31 droeg `Dekt: F14` voor
  beide claims, maar F13 punt a is de plek waar de `AC<n>`-hernoeming besloten
  wordt; F14 gaat uitsluitend over de blocking-edges
- And: `S<n>` mag in het sjabloon alleen nog voorkomen als verwijzing naar
  `TEST-SCENARIOS.md`, niet als eigen nummering

### S61 — Het scenariosjabloon draagt het dekkingsveld en de grammatica
**Covers:** F13
- Given: `templates/TEST-SCENARIOS.md`
- When: een project ermee scaffoldt
- Then: elk voorbeeldscenario toont een `**Covers:**`-veld direct onder de kop
- And: de tokengrammatica `^[A-Z]{1,2}[0-9]+[a-z]?$` staat er expliciet bij, met
  `S2b` als voorbeeld — een sjabloon dat de vorm voordoet zonder hem te benoemen
  leert de uitzondering niet aan, en dan strandt de eerste `S2b` op een
  handhaving die niemand had zien aankomen
- And: het sjabloon toont het veld met een placeholder, niet met een verzonnen
  ID dat nergens op slaat

### S32 — Elke actieve entry heeft een PR-linkback
**Covers:** F15
- Given: `CHANGES.md` met een entry zonder `**PR:**`-veld
- When: `./check` draait
- Then: exit ≠ 0, met het ID van die entry in de melding

### S33 — De CHANGELOG noemt de vereiste handmatige acties
**Covers:** F15
- Given: de eerste `CHANGELOG.md`-entry van deze release
- When: hij gelezen wordt
- Then: hij noemt zowel `adopt.sh` per project als `adopt.sh --user` per machine

### S35 — `check` meldt wat hij niet heeft kunnen controleren
**Covers:** F1
- Given: een bestand dat `check` zou moeten onderzoeken maar niet kan lezen
  (bijvoorbeeld een script zonder leesrechten)
- When: `./check` draait
- Then: er verschijnt een waarschuwing die het bestand noemt
- And: het bestand verdwijnt niet stilzwijgend uit de controle — stille
  degradatie is de faalmodus die dit repo het duurst betaalt

---

## Issue-templates en release (vervolg)

### S34 — De README beschrijft de nieuwe structuur
**Covers:** F16
- Given: `README.md` na deze release
- When: de inhoudstabel gelezen wordt
- Then: er staan rijen voor `skills/`, `hooks/`, `lib/`, `nfr/`, `test/`, `check`
  en `CHANGES-ARCHIEF.md`
- And: het aantal niet-functionele vragen staat op vijftien, niet vijf

---

## Dekking buiten de agentic loop

### S48 — Het CI-sjabloon valideert pull requests en `main`
**Covers:** F17
- Given: een project dat met `templates/ci.yml` scaffoldt
- When: er een pull request wordt geopend en er naar `main` wordt gepusht
- Then: de workflow draait in beide gevallen
- And: hij roept nog steeds uitsluitend `check` aan — de CI-conventie zelf
  verandert niet, alleen wanneer hij afgaat

### S49 — Een eigen `ci.yml` wordt niet overschreven
**Covers:** F17
- Given: een project met een handgeschreven `ci.yml` die afwijkt van het sjabloon
- When: `adopt.sh` opnieuw draait
- Then: dat bestand blijft ongemoeid — `scaffold_if_missing` schrijft alleen wat
  ontbreekt
- And: de afwijking blijft niet onzichtbaar. De adoptieregistratie stelt de vraag
  `ci-op-pr-en-main`, en blijft die stellen tot het project hem beantwoordt. Dat
  is het mechanisme, niet een melding in `adopt.sh` die één keer voorbijkomt en
  daarna weg is

### S50 — De guard geldt ook buiten Claude om
**Covers:** F17
- Given: een geadopteerd project met `main` uitgecheckt en de git-hooks
  geïnstalleerd
- When: `git commit` of `git push origin main` rechtstreeks in een shell wordt
  aangeroepen, dus zonder tussenkomst van Claude
- Then: het wordt geweigerd, met dezelfde melding als de `PreToolUse`-guard
- And: de *regel* staat maar op één plek — welke branch beschermd is en wat de
  melding zegt, komt uit dezelfde bron als de `PreToolUse`-guard. De inleeslaag
  verschilt noodzakelijk: een native `pre-commit` krijgt geen commandostring om
  te tokeniseren

### S51 — Een bestaande git-hook wordt niet stilzwijgend vervangen
**Covers:** F17
- Given: een project met een eigen `pre-commit`-hook die niet van dit repo komt
- When: `adopt.sh` draait
- Then: die hook wordt niet overschreven zonder melding
- And: twee keer draaien geeft een identieke boom — hooks stapelen niet

### S52 — Een commit op `main` buiten een PR om wordt gemeld
**Covers:** F17
- Given: een commit die rechtstreeks naar `main` is gepusht
- When: de CI-workflow draait
- Then: hij faalt, met de betreffende commit in de melding
- And: een merge-commit die wél uit een pull request komt laat hij door
- And: de controle geldt zowel in `spec-driven-guardrails` zelf als in elk project dat
  met `templates/ci.yml` scaffoldt — een regel die dit repo aan anderen oplegt
  maar zelf ontloopt, is geen regel

### S53 — De controle beoordeelt de push, niet de historie
**Covers:** F17
- Given: eerdere commits op `main` die niet aan de eis voldoen
- When: de workflow op een nieuwe push draait
- Then: alleen die push wordt beoordeeld
- And: de controle staat dus niet op dag één rood — een retrofit die altijd
  faalt leert je precies één ding, en dat is de melding negeren

### S58 — Een git-hook die zijn oordeel niet kan vellen, laat door
**Covers:** F17
- Given: een geadopteerd project waarin de git-hook zijn beslislogica niet kan
  uitvoeren — het bronscript ontbreekt, of de vereiste interpreter is er niet
- When: `git commit` of `git push` wordt aangeroepen
- Then: er verschijnt een luide waarschuwing die zegt dat de controle níét is
  uitgevoerd
- And: het commando gaat door, net als bij S14 — een kapotte guard mag nooit het
  werk blokkeren, en zeker niet buiten Claude om, waar geen agent meekijkt die
  de melding kan duiden

### S59 — Een CI-controle die zijn oordeel niet kan vellen, faalt
**Covers:** F17
- Given: de workflow uit S52 kan de herkomst van een push naar `main` niet
  vaststellen (geen API-antwoord, ontbrekende rechten)
- When: de controle draait
- Then: hij faalt, met de reden erbij
- And: dat is bewust het omgekeerde van S58. Een lokale hook die faalt houdt
  werk tegen dat allang legitiem kan zijn; een CI-controle die stil groen wordt
  meldt dat er niets aan de hand is terwijl hij niets weet — en dat is precies
  de stille degradatie die dit repo het duurst betaalt

### S72 — Bestaande projecten krijgen de main-via-PR-vraag alsnog voorgelegd
**Covers:** F17
- Given: een project met een `package.json` en een al bestaande `ci.yml` die
  `check-main-via-pr.sh` niet aanroept (`scaffold_if_missing` laat zo'n
  bestand ongemoeid — zelfde patroon als `ci-schakel-3-hard-slot` bij W19b)
- When: `pending-changes.sh` draait
- Then: een nieuwe entry verschijnt als openstaand
- And: een project zonder `package.json` krijgt die vraag niet

### S80 — De check-job heeft leestoegang tot pull requests en issues
**Covers:** F17
- Given: `templates/ci.yml` en dit repo's eigen `.github/workflows/ci.yml`
- When: op beide bestanden gecontroleerd wordt welke tokenscope de `check`-job
  krijgt
- Then: `pull-requests: read` geldt voor die job, op job- of workflow-niveau
- And: zonder die scope draait `check-pr-issue-link.sh` (schakel 3) en
  `check-main-via-pr.sh` onder het default, minimale tokenscope, en falen
  beide — niet incidenteel, zoals issue #83 en #85 allebei lieten zien
- And: `issues: read` geldt óók — een apart gat: `closingIssuesReferences`
  (waar `check-pr-issue-link.sh` op leest) gaat over het gekoppelde issue
  zelf, niet over de PR, en `pull-requests: read` alleen bleek daar niet
  genoeg voor. Zonder `issues: read` levert de opvraging stilzwijgend een
  lege lijst op, ook als de koppeling echt bestaat (ontdekt op PR #105 voor
  dit repo's eigen workflow, issue #99; hetzelfde gat gold voor
  `templates/ci.yml`, issue #106)

### S83 — Schakel 3 draait ook in dit repo's eigen CI
**Covers:** F17
- Given: `.github/workflows/ci.yml`
- When: een pull request tegen dit repo wordt geopend
- Then: `check-pr-issue-link.sh` draait, met zowel `pull-requests: read`
  (S80) als `issues: read` — dat laatste is een apart gat: zonder is levert
  `closingIssuesReferences` stilzwijgend een lege lijst op, ook als de
  koppeling echt bestaat (ontdekt op PR #105, run 34234378780)
- And: een PR zonder `Closes #N` (of een gelijkwaardige koppeling) in de
  PR-body faalt zichtbaar in CI, terwijl de PR nog open staat — niet pas
  achteraf zichtbaar via `pending-changes.sh` of een handmatige
  `pre-merge-review`, zoals bij PR's #96/#97 (2026-09-08) gebeurde

---

## Zelf-adoptie

### S81 — spec-driven-guardrails kan zichzelf adopteren
**Covers:** F7, F8
- Given: een sandboxkopie van dit repo, gebruikt als zowel
  `SPEC_DRIVEN_GUARDRAILS_DIR` als adoptiedoel
- When: `adopt.sh` daartegen draait
- Then: hij adopteert daadwerkelijk — `CLAUDE.md` en `.claude/settings.json`
  zijn symlinks naar zijn eigen `WORKFLOW.md` en
  `settings/session-hooks.json` — in plaats van de weigering "geen adoptie
  nodig" te tonen
- And: geen enkel bestaand, gecommit bestand (`PRD.md`, `TEST-SCENARIOS.md`,
  `check`, ...) verandert
- And: de git-guardrails-hook is daarna functioneel: een gefabriceerde
  `PreToolUse`-aanroep die een directe `git push origin main` voorstelt,
  wordt geweigerd — dezelfde controle die geadopteerde projecten krijgen
- And: de native git-hooks zijn ook geïnstalleerd en weigeren een directe
  `git push origin main` buiten Claude Code om (zelfde patroon als S50)
- And: een tweede `adopt.sh`-aanroep is idempotent — geen fouten, geen
  dubbele `.gitignore`-regels

### S82 — Een verse WORKFLOW-ADOPTIE.md noemt de juiste repo-naam
**Covers:** F3
- Given: een vers geadopteerd project
- When: `adopt.sh` `WORKFLOW-ADOPTIE.md` aanmaakt
- Then: de header verwijst naar `spec-driven-guardrails`
- And: niet naar `claude-workflow` — de naam van vóór de W32-hernoeming (#56)

---

## Installatie

### S84 — install.sh installeert een gepinde versie, niet de actuele main
**Covers:** F17
- Given: een kloon van dit repo met een tag op een oudere staat, gevolgd door
  een nieuwere commit
- When: `install.sh <tag>` daartegen draait
- Then: de checkout staat na afloop op de gepinde commit, niet op de nieuwere
  inhoud
- And: een vieze werkmap (niet-gecommitte wijzigingen) wordt geweigerd, zonder
  iets uit te checken — anders zou `git checkout` ze stilzwijgend weggooien
- And: een onbekende tag faalt met een duidelijke melding
- And: zonder argument wordt de laatste tag gebruikt, expliciet gemeld op
  stdout — nooit stilzwijgend

---

## Werk veiligstellen zonder sessie-einde

### S54 — Sessiestart meldt dat `main` is uitgecheckt
**Covers:** F18
- Given: een geadopteerd project met `main` uitgecheckt
- When: een sessie start
- Then: er verschijnt een melding die `main` noemt en `git checkout -b` voorstelt
- And: dat is vóór er werk is — de commit-blokkade uit F7 grijpt pas erna, als
  vertakken niet meer gratis voelt

### S55 — Op een feature-branch meldt de sessiestart niets
**Covers:** F18
- Given: hetzelfde project op `feature/<naam>`
- When: `pending-changes.sh` draait
- Then: er verschijnt geen melding over de branch
- And: exit 0 en niets op stderr, conform S43 — een hook die ruis produceert
  wordt weggeklikt en daarmee waardeloos

### S56 — Een geslaagde commit is meteen gepusht
**Covers:** F18
- Given: een feature-branch met een nieuwe commit
- When: de commit slaagt
- Then: de huidige branch staat op `origin`
- And: het werk is daarmee veilig zodra het is vastgelegd, in plaats van pas bij
  een nette afsluiting — waarvoor `SessionEnd` geen garantie geeft

### S57 — Een mislukte commit of ontbrekend netwerk pusht niets
**Covers:** F18
- Given: een `git commit` die faalt (niets te committen, afgebroken editor), of
  een omgeving zonder verbinding of zonder `origin`
- When: de hook draait
- Then: er wordt niet gepusht, en op `main` gebeurt sowieso niets
- And: de hook meldt het en houdt het werk niet op — een push die niet lukt mag
  nooit een commando blokkeren

### S85 — Een project op het pre-migratieformaat wordt per rij gemeld, met een issue
**Covers:** F6
- Given: een project met een `WORKFLOW-ADOPTIE.md` (geen `WORKFLOW-ADOPTION.md`)
  met rijen op het oude `ja`/`nee`-formaat
- When: `pending-changes.sh` draait
- Then: elke rij op het oude formaat wordt individueel gemeld, zonder dat een
  al beantwoorde rij ten onrechte als openstaande vraag telt
- And: er wordt een issue aangemaakt op de eigen repo van het project, met een
  machineherkenbare marker
- And: draait `pending-changes.sh` nogmaals terwijl dat issue al open staat,
  dan wordt er geen tweede issue aangemaakt (idempotent, marker-gestuurd)
- And: is `project_dir` geen eigen git-root (bijvoorbeeld een map binnen een
  ánder repo, zoals de bevroren nulmeting-fixtures), dan wordt `gh` helemaal
  niet aangeroepen — nooit schrijven naar het verkeerde repo

### S86 — De SessionStart/SessionEnd-hooks werken onafhankelijk van de toevallige cwd
**Covers:** F6, F18
- Given: `settings/session-hooks.json`'s `SessionStart`- en `SessionEnd`-commando's,
  aangeroepen vanuit een andere map dan het project zelf, met `CLAUDE_PROJECT_DIR`
  correct gezet — de PreToolUse/PostToolUse-hooks lossen dit al zo op (S44), maar
  `SessionStart`/`SessionEnd` deden dat niet: een relatieve `readlink
  .claude/settings.json` respectievelijk kale `git`-aanroep zonder `-C` levert dan
  stilzwijgend niets op, zonder enige melding — gevonden tijdens W42/#114's
  uitrol naar tennis-admin, waar precies dit de openstaand-melding en de
  migratiemelding allebei liet uitblijven
- When: `git fetch origin`, de `pending-changes.sh`-aanroep, en `git push origin
  HEAD` (op een niet-`main`-branch) draaien vanuit die andere map
- Then: alle drie doen precies hetzelfde alsof ze vanuit de projectmap zelf
  draaiden — de fetch/push raken de juiste remote, en de melding verschijnt
- And: de oorspronkelijke, cwd-afhankelijke vorm van elk commando faalt
  aantoonbaar hetzelfde scenario (stil niets doen), ter bevestiging dat dit
  een echte regressie was en geen toeval

### S87 — Een achtergebleven Dekt:-veld verdwijnt niet stilzwijgend
**Covers:** F13
- Given: een `TEST-SCENARIOS.md` of `PRD.md` met een `**Dekt:**`-veld van
  vóór de Covers:-cutover (W42/#114) — het token dat `check-traceability.sh`
  vóór deze migratie zelf gebruikte
- When: `check-traceability.sh` op dat project draait
- Then: het meldt expliciet welk bestand nog een pre-migratie Dekt:-veld
  draagt en hoeveel, met een verwijzing naar #114
- And: dat veld wordt niet stilzwijgend als geldige Covers:-verwijzing
  geparsed, en telt ook niet mee als "dit project gebruikt de conventie nog
  niet" — beide zouden het achtergebleven token onzichtbaar maken

### S88 — Geen Nederlands buiten laag C
**Covers:** F13
- Given: dit repo, ná W38–W42, met `check-no-dutch.sh`'s vaste
  woordenlijst en zijn twee gescheiden uitsluitingslijsten — permanent
  (laag C, historisch, epic #65, `USER-CLAUDE.md`) en tijdelijk-openstaand
  (getrackt in #136/#137/#138, bedoeld om te krimpen zodra die sluiten)
- When: `check-no-dutch.sh` draait
- Then: geen enkel bestand buiten die twee lijsten bevat nog een woord uit
  de woordenlijst
- And: `./check` roept dit script zelf aan (stap 3c) en faalt hard als het
  iets vindt — niet fail-open, want dit is een repo-eigen controle zonder
  netwerkafhankelijkheid
- And: het script sluit zichzelf uit van zijn eigen scan — de woordenlijst
  die het bevat is geen onvertaald proza
