---
name: adopt-workflow
description: >
  De adoptievraag: of een project de gedeelde workflow uit claude-workflow
  moet gebruiken, en hoe je een nieuw (gerelateerd) project opzet. User-level
  skill, geïnstalleerd door `adopt.sh --user`. Gebruik dit bij sessiestart in
  een git-project dat nog niet geadopteerd is, of bij het opzetten van een
  nieuw project.
---

## De adoptievraag

Check bij het starten van een sessie in een directory die een git-repository is:

1. Is dit repo zelf `claude-workflow`? Zo ja: sla deze check over.
2. Heeft dit project al een `CLAUDE.md` die een symlink is naar
   `claude-workflow/WORKFLOW.md`? Zo ja: al geadopteerd, sla deze check over.
3. Is er al een bekende keuze voor dit project vastgelegd in het
   geheugensysteem (eerder "ja" of "nee" beantwoord)? Zo ja: volg die keuze
   zonder opnieuw te vragen.
4. Anders: vraag Ties eenmalig of dit project de gedeelde persoonlijke
   workflow (`claude-workflow`) moet gebruiken.
   - **Ja** → voer `claude-workflow/adopt.sh` uit vanuit de root van dit
     project (vereist dat `CLAUDE_WORKFLOW_DIR` als omgevingsvariabele is
     ingesteld — zie `claude-workflow/README.md` als dat nog niet zo is).
   - **Nee** → laat het project ongemoeid: eigen conventies van het project
     blijven leidend, of geen specifieke workflow-afspraak.
   - Leg de keuze (ja/nee, en voor welk project) vast als geheugen, zodat niet
     elke sessie opnieuw gevraagd wordt.

Deze vraag is bewust *niet* stilzwijgend/automatisch afgedwongen —
team- of werkprojecten die niet van Ties alleen zijn, horen deze workflow niet
ongevraagd te krijgen.

## Nieuw (gerelateerd) project opzetten

1. `gh repo create <naam> --private --source=. --remote=origin` — maakt in één
   stap een lege GitHub-repo aan, initialiseert git lokaal (`git init`) en
   koppelt de remote (`git remote add origin <URL>`). Gebruik `git init` +
   `git remote add origin <URL>` los van elkaar alleen als de GitHub-repo al
   bestaat of buiten `gh` om is aangemaakt.
2. Deze gedeelde workflow adopteren via `adopt.sh` in dit repo
   (`claude-workflow`) — zie de adoptievraag hierboven en `README.md`.
