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

Vijftien subsecties, één per kenmerk uit het register in `nfr/`. **Beantwoord
elke subsectie met een objectieve redenering voor dít project — niet met de
generieke aanname vanuit `Standaard`.** "N.v.t. omdat …" is een geldig antwoord,
mits onderbouwd: het punt is dat de vraag serieus gesteld en beargumenteerd is,
niet dat elk project overal evenveel op moet doen.

<!-- nfr-blok:begin — gegenereerd door ./genereer-prd-blok, niet met de hand bewerken -->

### Security
<!-- nfr: spec-security -->
<Wie mag wat? Welke rechten zijn minimaal nodig? Waar staan secrets, en hoe
komen ze niet in git terecht?>

### Data-integriteit
<!-- nfr: spec-data-integriteit -->
<Welke invarianten moeten altijd gelden? Welke schrijfacties moeten idempotent
zijn (twee keer uitvoeren = één keer effect)? Wat gebeurt er als twee dingen
tegelijk schrijven? Blijft de data ook over tijd correct — geen geleidelijke
drift, geen stille corruptie?>

### Failure modes
<!-- nfr: spec-failure-modes -->
<Wat kan er misgaan — onverwachte invoer, een afhankelijkheid die wegvalt, een
verlopen autorisatie? Wat is het gedrag dan, en hoe herstel je?>

### Observability
<!-- nfr: spec-observability -->
<Hoe merk je dát het stuk is? Expliciet voor achtergrondjobs en triggers: een
job die stil faalt, faalt onzichtbaar.>

### Performance en schaal
<!-- nfr: spec-performance-schaal -->
<Verwachte omvang van data en gebruik. Welke platformlimieten of quota komen
in zicht, en wat gebeurt er als je eroverheen gaat?>

### Deployability
<!-- nfr: spec-deployability -->
<Welke omgevingen zijn er (bijv. pre-productie/productie)? Hoe wordt
uitgerold? Hoe rol je terug? Zie ook `ci-conventie`/`deploy-guards` in
`CHANGES.md` voor de procesmatige kant hiervan.>

### Privacy
<!-- nfr: spec-privacy -->
<Welke persoonsgegevens worden verwerkt? Hoe lang worden ze bewaard, en wie
kan ze zien?>

### Compliance en auditeerbaarheid
<!-- nfr: spec-compliance -->
<Welke wettelijke of zelfopgelegde verplichtingen gelden (bijv. fiscale
bewaarplicht)? Hoe toon je achteraf aan dat eraan voldaan is?>

### Backup en herstel
<!-- nfr: spec-backup-herstel -->
<Wat gebeurt er bij dataverlies binnen een werkende omgeving? Wat gebeurt er
als de omgeving zelf wegvalt (disaster recovery) — een account, een
script-project?>

### Portability
<!-- nfr: spec-portability -->
<Wat gebeurt er als het gekozen platform verandert of stopt? Hoe groot is de
afhankelijkheid van platformspecifieke eigenaardigheden?>

### Maintainability
<!-- nfr: spec-maintainability -->
<Hoe is het systeem ingedeeld in modules/componenten? Wie moet dit later
kunnen begrijpen en wijzigen, en wat maakt dat mogelijk of juist moeilijk?>

### Testability
<!-- nfr: spec-testability -->
<Hoe is de code zo gebouwd dat hij te testen is — bijv. een domeinlaag zonder
externe afhankelijkheden (zie een architectuureis in `ARCHITECTUUR.md` als die
er is)?>

### Usability
<!-- nfr: spec-usability -->
<Voor wie is dit bruikbaar, en onder welke omstandigheden (bijv. mobiel,
direct na de les, zonder handleiding)?>

### Kostenbeheersing
<!-- nfr: spec-kostenbeheersing -->
<Welke quota of kosten komen in zicht (API-aanroepen, opslag, compute)? Wat
gebeurt er als je eroverheen gaat?>

### Documentatie
<!-- nfr: spec-documentatie -->
<Hoe blijven `PRD.md`/`ARCHITECTUUR.md` actueel bij implementatiewijzigingen?
Is een formele API-specificatie nodig, en zo ja, waar staat die?>
<!-- nfr-blok:eind -->

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
