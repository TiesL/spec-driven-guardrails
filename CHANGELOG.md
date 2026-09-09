# Changelog

Releasepunten: momenten waarop een tag het mergepunt vastlegt als menselijk
referentiepunt. Geadopteerde projecten volgen `main` live via symlink, dus dit
is geen pinbare versie — zie "Waarom lokale symlinks i.p.v. gecommitte
symlinks" in `README.md`. Voor de doorlopende lijst van adopteerbare
wijzigingen per project: `CHANGES.md`.

## van-proza-naar-mechanisme — 2026-09-06

Epic [#11](https://github.com/TiesL/claude-workflow/issues/11): de conventies
van dit repo verplaatsen van proza (tekst die onthouden moet worden) naar
mechanisme (hooks, scripts, `check`, skills), overal waar handhaving mogelijk
is. Aanleiding: over vier projecten en 27 gemergede PR's verwees **nul** PR's
naar een issue, had **nul** een kwaliteitsreview, en was
`kwaliteitsreview-voor-merge` door geen enkel project ooit beantwoord — terwijl
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
eruit werd afgeleid.

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
  consument aan de duplicatie toevoegde.
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
implementatie ervan.

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
