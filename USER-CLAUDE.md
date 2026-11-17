# Gedeelde workflow — adoptievraag

Dit bestand wordt gesymlinkt als `~/.claude/CLAUDE.md` (userbreed, laadt in elke sessie/project). Het bevat alleen de trigger-instructie voor het aanbieden van de gedeelde workflow uit `spec-driven-guardrails` — de workflow-inhoud zelf staat in `WORKFLOW.md`.

## Instructie

Check bij het starten van een sessie in een directory die een git-repository is
of dit project de gedeelde workflow gebruikt (en zo nee, of het dat zou moeten).
Volg daarvoor de skill `adopt-workflow` — geïnstalleerd op userniveau door
`adopt.sh --user`.

Deze check is bewust *niet* stilzwijgend/automatisch afgedwongen — team- of
werkprojecten die niet van TiesL alleen zijn, horen deze workflow niet ongevraagd
te krijgen. Precies dáárom staat de trigger hier onvoorwaardelijk, in het altijd
geladen bestand, in plaats van alleen in een skill die pas laadt wanneer hij
toevallig relevant lijkt.

## Openstaande workflow-wijzigingen

Meldt de `SessionStart`-hook dat er openstaande wijzigingen zijn (zie
`CHANGES.md` in `spec-driven-guardrails`), volg dan de skill `adoption-registry` — niet
ongevraagd toepassen.
