# PRD — <Projectnaam> (<as-built | ontwerp>)

**Status:** <Documentatie van de huidige, werkende implementatie | Voorstel/ontwerp voor nog te bouwen functionaliteit>.

---

## Context
<Wie gebruikt dit, welk probleem lost het op, relevante achtergrond.>

---

## Architectuur
<Belangrijkste componenten/bestanden en hoe ze samenhangen.>

---

## Databron(nen)

### <Tabblad/tabel/bron X>

| Kolom | Veld | Notitie |
|---|---|---|
| | | |

---

## Functionaliteit

### F1 — <naam> (`functienaam`)
<Beschrijving van het gedrag.>

---

## Niet-functionele kenmerken

Beantwoord elk van deze vijf. **"N.v.t. omdat …" is een geldig antwoord** — het
punt is dat de vraag gesteld is, niet dat elk project overal iets op moet doen.

### Toegang en autorisatie
<Wie mag wat? Welke rechten zijn minimaal nodig? Waar staan secrets, en hoe komen
ze niet in git terecht?>

### Dataconsistentie
<Welke invarianten moeten altijd gelden? Welke schrijfacties moeten idempotent
zijn (twee keer uitvoeren = één keer effect)? Wat gebeurt er als twee dingen
tegelijk schrijven?>

### Failure modes
<Wat kan er misgaan — onverwachte invoer, een afhankelijkheid die wegvalt, een
verlopen autorisatie? Wat is het gedrag dan, en hoe herstel je?>

### Observability
<Hoe merk je dát het stuk is? Expliciet voor achtergrondjobs en triggers: een job
die stil faalt, faalt onzichtbaar.>

### Grenzen en schaal
<Verwachte omvang van data en gebruik. Welke platformlimieten of quota komen in
zicht, en wat gebeurt er als je eroverheen gaat?>

---

## Niet in scope
-

## Bekende beperkingen

Wat het systeem bewust niet doet of niet kan. Blijft zo tenzij de scope
verandert — geen actie nodig.

-

## Technical debt

Wat je anders zou bouwen als je opnieuw begon: toevallige complexiteit, bewuste
shortcuts, verouderde dependencies, ontbrekende tests. Hier landen ook
geaccepteerde reviewbevindingen. Zie *Complexiteit, technical debt en
refactoring* in `CLAUDE.md`.

| Wat | Waarom nu acceptabel | Trigger om aan te pakken |
|---|---|---|
| | | |

---

## Projectbestanden

| Bestand | Doel |
|---|---|
| | |
