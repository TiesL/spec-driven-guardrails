# Gedeelde workflow — adoptievraag

Dit bestand wordt gesymlinkt als `~/.claude/CLAUDE.md` (userbreed, laadt in elke sessie/project). Het bevat alleen de trigger-instructie voor het aanbieden van de gedeelde workflow uit `claude-workflow` — de workflow-inhoud zelf staat in `WORKFLOW.md`.

## Instructie

Check bij het starten van een sessie in een directory die een git-repository is:

1. Is dit repo zelf `claude-workflow`? Zo ja: sla deze check over.
2. Heeft dit project al een `CLAUDE.md` die een symlink is naar `claude-workflow/WORKFLOW.md`? Zo ja: al geadopteerd, sla deze check over.
3. Is er al een bekende keuze voor dit project vastgelegd in het geheugensysteem (eerder "ja" of "nee" beantwoord)? Zo ja: volg die keuze zonder opnieuw te vragen.
4. Anders: vraag Ties eenmalig of dit project de gedeelde persoonlijke workflow (`claude-workflow`) moet gebruiken.
   - **Ja** → voer `claude-workflow/adopt.sh` uit vanuit de root van dit project (vereist dat `CLAUDE_WORKFLOW_DIR` als omgevingsvariabele is ingesteld — zie `claude-workflow/README.md` als dat nog niet zo is).
   - **Nee** → laat het project ongemoeid: eigen conventies van het project blijven leidend, of geen specifieke workflow-afspraak.
   - Leg de keuze (ja/nee, en voor welk project) vast als geheugen, zodat niet elke sessie opnieuw gevraagd wordt.

Deze vraag is bewust *niet* stilzwijgend/automatisch afgedwongen — team- of werkprojecten die niet van Ties alleen zijn, horen deze workflow niet ongevraagd te krijgen.

## Openstaande workflow-wijzigingen

Meldt de `SessionStart`-hook dat er openstaande wijzigingen zijn (zie
`CHANGES.md` in `claude-workflow`), doe dan het volgende — niet ongevraagd
toepassen:

1. Leg ze aan Ties voor als **gesloten ja/nee-vragen**, meerdere tegelijk in één
   keuzeprompt; bij meer dan vier in rondes.
2. Schrijf elk antwoord als rij in `WORKFLOW-ADOPTIE.md` van dat project:
   `| <wijziging-id> | ja/nee | <datum> | <toelichting> |`. Noteer bij "nee"
   altijd waaróm — dat is precies de waarde van die registratie.
3. Voer bij "ja" uit wat de entry onder "Ja betekent" beschrijft. Is dat meer dan
   een handeling van niets (bijvoorbeeld projectcode aanpassen), maak er dan een
   GitHub-issue voor in plaats van het meteen in deze sessie te doen.

Het antwoordbestand wordt gecommit: of een project een afspraak toepast is een
eigenschap van het project, niet van de machine waarop je toevallig werkt.
