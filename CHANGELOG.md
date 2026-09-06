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

**Vereiste actie na deze release, per project en per machine:**

- Draai `adopt.sh` opnieuw in elk geadopteerd project (`a2t-emails`,
  `tennis-admin`, `tennis-registration`, `tennis-invoicing`) — dat ververst de
  skill-symlinks, de sjablonen en de nieuwe `CHANGES.md`-vragen.
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
