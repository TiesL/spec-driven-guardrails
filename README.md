# claude-workflow

Eén, versiebeheerde bron van waarheid voor de persoonlijke Git/GitHub-workflow die Ties met Claude Code gebruikt in al zijn solo-projecten (niet in team-/werkprojecten). Voorheen stond deze workflow gedupliceerd in elk project (`CLAUDE.md` + `.claude/settings.json`), wat tot drift leidde — dit repo lost dat op.

## Inhoud

| Bestand | Doel |
|---|---|
| `WORKFLOW.md` | De workflow-tekst zelf (GitHub Flow, branch+PR, sessie-stappen). Wordt in geadopteerde projecten gesymlinkt als `CLAUDE.md`. |
| `settings/session-hooks.json` | `SessionStart`/`SessionEnd`-hooks + `attribution.commit`-instelling. Wordt gesymlinkt als `.claude/settings.json`. |
| `USER-CLAUDE.md` | Korte trigger-instructie voor de automatische adoptievraag bij nieuwe projecten. Wordt gesymlinkt als `~/.claude/CLAUDE.md`. |
| `adopt.sh` | Script dat de symlinks hierboven lokaal aanmaakt. |

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

## Nieuw project opzetten

```bash
gh repo create <naam> --private --source=. --remote=origin
"$CLAUDE_WORKFLOW_DIR/adopt.sh"
```

## Toekomstig: test/deploy-automatisering

Dit repo is de aangewezen plek voor gedeelde automatiseringsscripts zodra dat aan de orde is — bijvoorbeeld een `clasp`-gebaseerd deploy-script voor de Google Apps Script-projecten (`tennis-registration`, `tennis-invoicing`), ter vervanging van de huidige handmatige copy-paste-naar-de-editor-stap. Nog niet gebouwd; dit repo bestaat zodat het straks een logische plek heeft.
