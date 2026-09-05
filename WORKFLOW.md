# Werkwijze — Git/GitHub-workflow

Dit project wordt vanaf meerdere computers ontwikkeld. Volg deze workflow in elke sessie, ongeacht op welke machine je werkt. Deze tekst wordt in geadopteerde projecten gesymlinkt als `CLAUDE.md` — zie `README.md` in dit repo voor de adoptieprocedure.

## Branchstrategie: GitHub Flow

- `main` is altijd stabiel/werkend. **Nooit rechtstreeks naar `main` committen of pushen** — dit is een workflow-afspraak, geen technisch afgedwongen regel (GitHub branch protection op private repo's vereist een betaald plan).
- Al het werk gebeurt op een kortlevende branch vanaf de actuele `main`:
  - `feature/<kebab-case-omschrijving>` voor nieuwe functionaliteit/epics
  - `fix/<kebab-case-omschrijving>` voor bugfixes (ook triviale, zoals documentatiecorrecties)

## Bij het starten van een sessie

1. `git fetch origin` (gebeurt ook automatisch via een `SessionStart`-hook, zie `settings/session-hooks.json`).
2. Ga na of je verder werkt aan bestaand werk (bestaande feature-branch) of iets nieuws begint.
   - Bestaand werk: `git checkout <branch> && git pull origin <branch>`.
   - Nieuw werk: `git checkout main && git pull origin main && git checkout -b feature/<naam>` (of `fix/<naam>`).
3. Bekijk de recente historie voor context: `git log --oneline -10` — vooral nuttig als je op de andere computer verdergaat en wilt zien wat er sinds de laatste keer is gebeurd.

## Tijdens het werk

- Commit logische stappen op de feature-branch.
- Push regelmatig naar `origin/<branch>` — nooit naar `main`. Dit gebeurt ook automatisch: een `SessionEnd`-hook pusht bij het afsluiten van een sessie de huidige branch, met een guard die dit overslaat wanneer toevallig `main` is uitgecheckt (extra vangnet, want er is geen branch protection — zie hieronder).
- Commitberichten bevatten geen "Co-Authored-By"-trailer — afgedwongen via `attribution.commit: ""` in `settings/session-hooks.json`, niet afhankelijk van of de uitvoerende sessie zich dat herinnert.

## Afronden

1. Zodra de wijziging klaar en getest is (en, waar van toepassing, handmatig geverifieerd): open een PR met `gh pr create`.
2. **Draai een kwaliteitsreview** vóór de merge — zie de skill `pre-merge-review`.
3. **Wacht op expliciete bevestiging van Ties** dat de test geslaagd is en er geen regressie is, vóór je merget. Merg nooit automatisch zonder die bevestiging.
4. Merge daarna met `gh pr merge --squash --delete-branch` — dit houdt de historie op `main` overzichtelijk en ruimt de branch (lokaal en remote) direct op.

## Wegwijzer

Dit bestand houdt wat élke sessie nodig heeft. Voor de rest: onderstaande tabel
lost elk verplaatst onderwerp op in één sprong.

| Situatie | Skill |
|---|---|
| Kwaliteitsreview vóór de merge | `pre-merge-review` |
| Specificeren van werk (PRD, testscenario's, issues), `Dekt:`-conventie | `write-spec` |
| Onderbouwingsplicht | `adoption-registry` |
| Adoptieregistratie (per project bijhouden welke wijzigingen van toepassing zijn) | `adoption-registry` |
| `check`/`deploy`-naamconventie, CI | `check-convention` |
| Deploy-voorwaarden per omgeving | `deploy-guards` |
| Complexiteit, technical debt, refactoring | `refactoring-triggers` |
| Nieuw (gerelateerd) project opzetten | `adopt-workflow` (user-level) |

## Waarom

Zonder deze afspraak ontstaan conflicten en kan werk van de ene computer per ongeluk overschreven worden door werk van de andere. Er is geen technische blokkade tegen directe pushes naar `main` — volg deze workflow dus bewust, ook wanneer een directe push technisch zou lukken.
