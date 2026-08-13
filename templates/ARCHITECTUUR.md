# Architectuurafweging — <onderwerp van het besluit>

Dit document legt vast *waarom* het systeem is zoals het is. `PRD.md` beschrijft
wat het moet doen; hier staat welke structurele keuzes daaronder liggen, welke
alternatieven zijn afgewogen, en wanneer een keuze opnieuw tegen het licht moet.

Niet elk besluit hoort hier. Wel: platformkeuzes, de indeling in lagen of
componenten, waar gegevens eigenaar van zijn, en het toevoegen van een
substantiële dependency. Niet: hoe één functie is geschreven.

---

## Het besluit

**Besloten op <datum>: <de keuze in één zin>.**

<Twee tot vijf zinnen: wat is er gekozen, en wat betekent dat concreet voor hoe
het systeem eruitziet.>

---

## Beoordelingscriteria

<Waarop zijn de opties beoordeeld, en waarom die criteria? Noem ze vóór de
opties — anders kies je achteraf de criteria die de gewenste uitkomst
rechtvaardigen.>

| Criterium | Waarom dit telt |
|---|---|
| | |

---

## Afgewogen opties

### Optie 1 — <naam>
<Wat het is, en hoe het scoort op de criteria. Voor- en nadelen.>

### Optie 2 — <naam>
<Idem.>

---

## Vergelijking en keuze

<Waarom de gekozen optie wint. Benoem expliciet wat je ervoor inlevert — een
keuze zonder nadelen is meestal een keuze die niet goed genoeg is onderzocht.>

---

## Architectuureisen die hieruit volgen

Genummerde, toetsbare eisen waar de code zich aan houdt. Deze zijn de meetlat
voor de refactoring-trigger uit `CLAUDE.md`: bouw je iets dat een eis hier
schendt, dan is dat een signaal om te herontwerpen, niet om een uitzondering te
maken.

### A1 — <naam van de eis>
<Wat de eis inhoudt, en waaróm — welk probleem voorkomt hij? Hoe zie je of hij
geschonden wordt?>

---

## Systeemgrenzen en eigenaarschap

<Welke componenten zijn er, en wat is de afspraak tussen die componenten? Wie is
eigenaar van welke gegevens? Wat mag wél en niet rechtstreeks bij elkaar naar
binnen kijken?>

---

## Dependencies

Een bibliotheek toevoegen is een architectuurbesluit, geen implementatiedetail.
Per substantiële dependency:

| Dependency | Waarvoor | Onderhoud en volwassenheid | Licentie | Waarom niet zelf bouwen |
|---|---|---|---|---|
| | | | | |

---

## Wanneer we deze keuze zouden herzien

<Concrete, herkenbare signalen — geen "als het niet meer bevalt". Bijvoorbeeld:
een limiet die in zicht komt, een aanname die niet blijkt te kloppen, een
functionaliteit die er structureel niet in past.>

-

---

## Openstaand na dit document

<Wat is bewust nog niet besloten, en wanneer moet dat wel?>

-
