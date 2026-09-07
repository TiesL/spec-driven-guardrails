# claude-workflow

Eén, versiebeheerde bron van waarheid voor de persoonlijke Git/GitHub-workflow die Ties met Claude Code gebruikt in al zijn solo-projecten (niet in team-/werkprojecten). Voorheen stond deze workflow gedupliceerd in elk project (`CLAUDE.md` + `.claude/settings.json`), wat tot drift leidde — dit repo lost dat op.

## Inhoud

| Bestand | Doel |
|---|---|
| `WORKFLOW.md` | De workflow-tekst zelf (GitHub Flow, branch+PR, sessie-stappen, specificatieproces) plus een Wegwijzer die elk verplaatst onderwerp naar zijn skill doorverwijst. Wordt in geadopteerde projecten gesymlinkt als `CLAUDE.md`. |
| `settings/session-hooks.json` | `SessionStart`/`SessionEnd`-hooks + `attribution.commit`-instelling. Wordt gesymlinkt als `.claude/settings.json`. |
| `hooks/` | `git-guardrails` — de `PreToolUse`-guard tegen destructieve git-commando's én (W10b) de merge-guard op `gh pr merge` zonder review-marker of met niet-groene CI. Faalt altijd open (geen `gh`/netwerk, ontbrekend hulpprogramma) — een kapotte guard mag nooit het werk blokkeren. Aangeroepen vanuit `settings/session-hooks.json`. |
| `skills/` | De negen Claude Code skills (`pre-merge-review`, `deploy-guards`, `check-convention`, `adoption-registry`, `write-spec`, `refactoring-triggers`, `tdd-seams`, `diagnose-bug`, `adopt-workflow`) — zie de Wegwijzer in `WORKFLOW.md`. `adopt.sh` symlinkt ze per skill naar `.claude/skills/` van elk geadopteerd project. |
| `USER-CLAUDE.md` | Korte trigger-instructie voor de automatische adoptievraag bij nieuwe projecten. Wordt gesymlinkt als `~/.claude/CLAUDE.md`. |
| `templates/PRD.md`, `templates/TEST-SCENARIOS.md`, `templates/ARCHITECTUUR.md` | Generieke sjablonen voor het specificeren van een project (zie "Specificeren van werk" in `WORKFLOW.md`). De PRD dwingt vijftien niet-functionele vragen af en scheidt *Bekende beperkingen* van *Technical debt*; de testscenario's vragen naast happy paths ook failure paths; `ARCHITECTUUR.md` legt structurele besluiten en hun herzieningstrigger vast. Worden bij adoptie **gekopieerd**, maar alleen als het bestand daar nog niet bestaat — een al ingevuld exemplaar wordt nooit overschreven. |
| `templates/ISSUE_TEMPLATE/` | GitHub issue-templates (`epic.md`, `work-item.md`, `config.yml`), qua notatie afgestemd op `PRD.md`/`TEST-SCENARIOS.md`. Worden bij elke adoptie **gekopieerd** (ververst) naar `.github/ISSUE_TEMPLATE/` van het project. |
| `templates/CONTEXT.md` | Optioneel begrippenkader (projectjargon → betekenis), los van `ARCHITECTUUR.md` dat over structurele besluiten gaat. Wordt alleen gescaffold als het project `proces-context-document` in `CHANGES.md` met `ja` beantwoordde. |
| `templates/ci.yml` | Generieke GitHub Actions-CI die alleen `npm run check` aanroept (zie "Testen en deployen automatiseren" in `WORKFLOW.md`). Wordt bij adoptie gescaffold, maar alleen als het project een `package.json` heeft. |
| `CHANGES.md` | Lijst van adopteerbare wijzigingen: per PR-grote wijziging een gesloten vraag, een "van toepassing als"-conditie en wat "ja" betekent. Projecten leggen hun antwoord vast in hun eigen `WORKFLOW-ADOPTIE.md`. |
| `CHANGES-ARCHIEF.md` | Geretireerde `CHANGES.md`-entries, met hun ID ongewijzigd zodat een project dat ooit antwoordde nog kan terugvinden waar die rij vandaan komt. |
| `nfr/` | Het NFR-register: vijftien bestanden, één per niet-functioneel kenmerk (security, data-integriteit, failure modes, …). Enige bron voor zowel de `spec-*`-vragen in `CHANGES.md` als de ingevulde subsecties in `templates/PRD.md` — geen van beide meer los bijgehouden. |
| `lib/` | Gedeelde bash-bibliotheken: `changes.sh` (de `CHANGES.md`-parser en predicaten, gebruikt door `adopt.sh` én `pending-changes.sh`) en `nfr.sh` (leest/valideert het `nfr/`-register). |
| `pending-changes.sh` | Bepaalt welke wijzigingen uit `CHANGES.md` en `nfr/` voor een project van toepassing zijn en nog geen antwoord hebben. Wordt aangeroepen door de `SessionStart`-hook. |
| `adopt.sh` | Script dat de symlinks en kopieën hierboven lokaal aanmaakt/ververst, en de adoptietabel van een nieuw project seedt. |
| `check` | Het enige commando dat dit repo's eigen CI aanroept: bash-syntaxis, JSON-validatie, NFR-registerdrift, PR-linkbacks, shellcheck (niet-blokkerend), dan de testsuite. Dezelfde `check`/`deploy`-naamconventie die dit repo aan geadopteerde projecten voorschrijft, hier op zichzelf toegepast. |
| `test/` | De eigen testsuite van dit repo: `run.sh` (draait alles onder `cases/`), `lib.sh` (sandbox- en assert-hulpfuncties) en `fixtures/nulmeting/` (de bevroren nulmeting, zie het `LEESMIJ.md` daar). |
| `PRD-MULTI-AGENT-WIP.md` | **WIP** — verkennend PRD voor multi-agent softwareontwikkeling in een latere release, gekoppeld aan epic [#65](https://github.com/TiesL/claude-workflow/issues/65). Geen onderdeel van de gedeelde workflow-machinerie hierboven en niet goedgekeurd: richtinggevend, met open ontwerpvragen bewust als **TBD**. |

## Waarom lokale symlinks i.p.v. gecommitte symlinks

De projectmappen staan niet op dezelfde plek op elke computer (bijv. `~/Projects` op de ene, `~/Documents/ClaudeCodeZandbak` op de andere). Een symlink die je commit naar git (relatief of absoluut) kan dus nooit op beide machines tegelijk kloppen. Daarom worden de symlinks **niet gecommit**: `adopt.sh` maakt ze lokaal aan, met een pad dat via de omgevingsvariabele `CLAUDE_WORKFLOW_DIR` per machine correct is.

## Eenmalige setup per machine

1. Clone dit repo ergens naar keuze op de machine.
2. Zet in je shell-profiel (`~/.zshrc` of `~/.bashrc`) één keer:
   ```bash
   export CLAUDE_WORKFLOW_DIR="/volledig/pad/naar/claude-workflow"
   ```
   Herstart je shell (of `source ~/.zshrc`) zodat de variabele actief is.
3. Zet de userbrede adoptievraag-trigger op:
   ```bash
   "$CLAUDE_WORKFLOW_DIR/adopt.sh" --user
   ```
   Vanaf nu vraagt Claude Code automatisch, bij het starten van een sessie in een nog niet-geadopteerd git-project, of dat project deze workflow moet gebruiken.

## Een project handmatig adopteren

```bash
cd /pad/naar/project
"$CLAUDE_WORKFLOW_DIR/adopt.sh"
```

Dit zet `CLAUDE.md` en `.claude/settings.json` als lokale symlinks, en voegt ze toe aan `.gitignore` van dat project (het zijn machine-specifieke verwijzingen, geen project-artefacten). Bestaande bestanden op die paden worden — als het geen symlinks zijn — hernoemd naar `*.bak` in plaats van overschreven.

### Bekende valkuil: branches die ouder zijn dan de adoptie

Git overschrijft een lokale (ongetrackte) symlink zonder waarschuwing zodra je overschakelt naar een branch die `CLAUDE.md`/`.claude/settings.json` nog als gewoon, getrackt bestand bevat (bijv. een feature-branch die vóór de adoptie van dit project is aangemaakt). Na het terugschakelen naar zo'n branch zijn de symlinks dus weg. Oplossingen:
- **Voorkeur:** merge/rebase `main` in die branch zodra dit project geadopteerd is — daarna verdwijnt het conflict permanent voor die branch.
- **Alternatief:** draai `adopt.sh` opnieuw na elke keer dat dit gebeurt (idempotent, geen risico).

## Sjablonen: kopie i.p.v. symlink

In tegenstelling tot `CLAUDE.md`/`.claude/settings.json` (lokale symlinks,
nooit gecommit) worden de bestanden onder `templates/` **gekopieerd** naar
elk geadopteerd project, met twee verschillende gedragingen:

- **`PRD.md`/`TEST-SCENARIOS.md`** — scaffold: alleen aangemaakt als het
  bestand in het project nog niet bestaat. Dit zijn project-eigen, in te
  vullen documenten; een al ingevuld exemplaar wordt nooit overschreven.
- **`ISSUE_TEMPLATE/*`** — altijd ververst bij elke `adopt.sh`-run. Dit is
  meta-configuratie (GitHub-issueformulieren), geen invulbare inhoud.

Een symlink werkt hier sowieso niet voor de issue-templates: GitHub rendert
die server-side vanuit de repo-inhoud zelf, niet via lokale
bestandssysteem-symlinks. Gevolg van "kopie": na een wijziging aan een
canoniek sjabloon in dit repo moet `adopt.sh` opnieuw gedraaid worden in elk
project om de issue-template-kopie daar te verversen (idempotent, geen
risico — zelfde soort afspraak als bij de bekende valkuil hierboven).

## Adoptieregistratie

Elk geadopteerd project houdt in `WORKFLOW-ADOPTIE.md` bij welke wijzigingen uit
`CHANGES.md` het toepast. Een `SessionStart`-hook meldt wat er nog openstaat;
Claude stelt die vragen als gesloten ja/nee-keuzes en legt het antwoord vast.
Zie "Adoptieregistratie" in `WORKFLOW.md` voor het volledige verhaal.

Handmatig nakijken kan ook:

```bash
"$CLAUDE_WORKFLOW_DIR/pending-changes.sh" /pad/naar/project
```

De hook lokaliseert dit repo overigens via de symlink
(`readlink .claude/settings.json`) en niet via `CLAUDE_WORKFLOW_DIR` — een
niet-interactieve shell laadt je `~/.zshrc` niet, dus op die variabele kan een
hook niet rekenen.

## Nieuw project opzetten

```bash
gh repo create <naam> --private --source=. --remote=origin
"$CLAUDE_WORKFLOW_DIR/adopt.sh"
```

## Testen en deployen automatiseren

Zie "Testen en deployen automatiseren" in `WORKFLOW.md` voor de conventie
(vaste `check`/`deploy`-commandonamen, CI die alleen `check` aanroept,
deploy als bewuste losse stap) en hierboven in deze tabel voor
`templates/ci.yml`, het bijbehorende sjabloon.
