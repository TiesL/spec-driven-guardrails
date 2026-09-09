---
name: deploy-guards
description: >
  De voorwaarden waaronder deploy naar pre-productie of productie mag draaien
  (schone werkmap, check slaagt, main gelijk aan origin/main, groene CI), en
  waarom. Gebruik dit bij het bouwen of aanpassen van een deploy-script, of
  wanneer een deploy geweigerd wordt.
---

## `deploy` weigert te draaien vanuit een ongeverifieerde toestand

`deploy` controleert zelf of de toestand deugt en stopt als dat niet zo is.
Welke voorwaarden gelden, hangt af van de doelomgeving.

**Pre-productie (acceptatie) — mag vanaf elke branch.** De omgeving waarin de
acceptatietest gebeurt, vóór de merge. Voorwaarden: de werkmap is schoon (wat je
uitrolt is herleidbaar tot één commit — anders weet je niet wát je getest hebt);
`check` slaagt (`deploy` draait hem zelf, in plaats van erop te vertrouwen dat je
eraan dacht); de commit is gepusht (zodat CI hem ziet, en terug te vinden is wat
er in acceptatie stond). Een groene CI-run is hier bewust géén voorwaarde —
`check` is net lokaal gedraaid, en wachten bij elke iteratie maakt de lus traag.

**Productie — alleen vanaf `main`.** Alles hierboven, plus: je staat op `main`
(alleen dan is de code via een PR gegaan en gereviewd); lokale `main` is gelijk
aan `origin/main` (anders rol je iets uit dat CI nooit gezien heeft, of juist
iets verouderds); de laatste CI-run op `main` is geslaagd.

Heeft een project meer dan één doelomgeving, dan is er **geen impliciete
standaard** — de omgeving wordt elke keer expliciet meegegeven. Een
standaardwaarde die je kunt vergeten is precies het mechanisme dat hier wordt
afgeschaft.

Controles die het netwerk nodig hebben (CI-status, actualiteit van de remote)
waarschuwen en gaan door als tooling of verbinding ontbreekt; de puur lokale
controles blokkeren hard. Er is één bewuste uitweg (`--force` of gelijkwaardig)
die luid meldt wélke controles worden overgeslagen en naar wélke omgeving het
gaat — een guard zonder uitweg wordt op den duur omzeild door het script aan te
passen, en dat is erger dan een guard die je expliciet uitzet.

### De volgorde in de praktijk

1. Werk op een feature-branch; commit en push.
2. Deploy die branch naar **pre-productie**; doe daar de acceptatietest.
3. Gaat die goed: Ties initieert de merge naar `main` (zie "Wrapping up" in
   `WORKFLOW.md`).
4. Deploy `main` naar **productie**, na expliciete goedkeuring van Ties.

Zonder pre-productieomgeving bijten stap 2 en de afspraak uit "Wrapping up" elkaar:
verifiëren kan dan alleen in productie, maar daar mag je pas ná de merge komen.
Laat die spanning niet sluimeren — kies bewust: gebruik de ontsnappingsroute voor
die ene uitrol en zeg hardop dat je dat doet, óf richt een pre-productieomgeving
in. Het tweede is de bedoeling.

### Waarom deze regels bestaan

Een `deploy` die niet naar git kijkt, rolt uit wat er toevallig in de werkmap
ligt — ongeacht branch, commit of CI. Draait er daarna een periodieke trigger op
die code, dan voert ongereviewde code zichzelf uit; een bevestigingsstap in een
UI beschermt alleen de handmatige route, niet de automatische. Dit is in
`tennis-admin` één keer misgegaan, en de enige beveiliging tot dat moment was dat
degene die deployde eraan dacht. Dat is geen beveiliging. Uitgewerkt voorbeeld:
`scripts/deploy.mjs` in `tennis-admin`.
