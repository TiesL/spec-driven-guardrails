---
name: check-convention
description: >
  De vaste, platform-neutrale commandonamen check en deploy, en hoe CI die
  aanroept zonder eigen checks te verzinnen. Gebruik dit bij het opzetten of
  aanpassen van CI, of bij twijfel over waar een projectspecifieke check hoort.
---

## Testen en deployen automatiseren

Voor projecten met buildbare/testbare code gelden twee vaste, platform-
neutrale commandonamen:

1. **`check`** — alles wat bepaalt of een wijziging goed is (typecheck,
   lint, tests, build). De GitHub Actions-workflow (zie `templates/ci.yml`,
   automatisch gescaffold door `adopt.sh` als het project een
   `package.json` heeft) roept dit commando aan en verzint zelf geen
   losse checks — één bron van waarheid, geen drift tussen lokaal en CI.
2. **`deploy`** — rolt daadwerkelijk uit naar een doelomgeving. Blijft altijd
   een bewuste, handmatig gestarte stap: geen automatische uitrol bij een
   merge — dezelfde soort regie als bij de afspraak dat een merge pas gebeurt
   na expliciete bevestiging van Ties (zie "Afronden" in `WORKFLOW.md`).
   Zie de skill `deploy-guards` voor de voorwaarden waaronder `deploy` mag
   draaien.

Projectspecifieke checks (een eigen lintregel, een domeinspecifieke
validatie) horen thuis in het `check`-script van het project zelf, niet in
`claude-workflow`.

Dit sjabloon veronderstelt npm. Voor een project op een andere stack geldt
hetzelfde principe (vaste `check`/`deploy`-namen, CI roept alleen `check`
aan), toegepast met de eigen tooling van die stack — `adopt.sh` scaffoldt
`ci.yml` alleen wanneer een `package.json` aanwezig is.
