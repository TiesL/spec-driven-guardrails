---
name: adoption-registry
description: >
  Adoptieregistratie en de onderbouwingsplicht: hoe een project per wijziging
  in WORKFLOW-ADOPTIE.md vastlegt wat het toepast, en hoe je een openstaande
  of nog te onderbouwen rij afhandelt (spec-rakend vs. puur procesmatig).
  Gebruik dit wanneer een sessie openstaande workflow-wijzigingen meldt, of
  bij het opstellen/herzien van PRD.md of ARCHITECTUUR.md.
---

## Waarom: per wijziging een keuze per project

Niet elke afspraak uit `spec-driven-guardrails` past bij elk project. Daarom legt elk
geadopteerd project in `WORKFLOW-ADOPTIE.md` vast wélke wijzigingen het
toepast — zodat afwijken een geregistreerde, onderbouwde uitzondering is in
plaats van stille drift.

## Hoe een wijziging ontstaat

Elke PR op `spec-driven-guardrails` die iets toevoegt waarover een project een eigen
keuze moet maken, **voegt een entry toe aan `CHANGES.md`** — met een gesloten
vraag, een `Standaard` (`ja`/`vraag`), een "van toepassing als"-conditie en wat
"ja" concreet betekent. Geen entry betekent geen vraag, en dus een vals gevoel
van dekking; let hier bij review op.

`Standaard: ja` vs. `Standaard: vraag` bepaalt alleen het startpunt, niet of
onderbouwing nodig is. Bij adoptie van een nieuw project zet `adopt.sh` elke op
dat moment toepasselijke `Standaard: ja`-wijziging op "ja — vereist
onderbouwing" (een voorlopige stempel, geen besluit); `Standaard: vraag`-
wijzigingen worden nooit automatisch beantwoord. Een ontbrekende rij betekent
"(nog) niet van toepassing": wordt de conditie later alsnog waar — een project
krijgt bijvoorbeeld een deploycommando — dan verschijnt de vraag vanzelf. Een
`nee`-rij is een bewuste, onderbouwde uitzondering en blijft staan tot je hem
handmatig weghaalt.

## Wanneer de vraag verschijnt

Bij sessiestart meldt een hook welke wijzigingen voor dít project van
toepassing zijn en nog geen antwoord hebben (of nog "vereist onderbouwing"
zeggen).

## Hoe je hem afhandelt

Hoe je een openstaande of nog te onderbouwen rij afhandelt, hangt af van het
soort entry:

- **Raakt de entry `PRD.md`/`ARCHITECTUUR.md`** (de meeste `spec-*`-entries en
  de NFR's): dit is de **onderbouwingsplicht**, en geldt voor élke rij die
  hierbij hoort, niet alleen de NFR's uit "Niet-functionele kenmerken" — ook
  `proces-prd` of `architectuurdocument` zelf verdient een echte reden, geen
  automatisme.
  - Een rij die nog **"vereist onderbouwing"** zegt: vervang die door een
    objectieve, op dít project gegronde redenering waarom `ja` geldt — of, als
    die redenering niet standhoudt, zet de rij om naar `nee` met de reden.
  - Een nog onbeantwoorde **`Standaard: vraag`**-rij: geen blanco vraag. Doe
    een beargumenteerd voorstel, gegrond in de daadwerkelijke inhoud van dit
    project, en leg dat ter bevestiging voor aan Ties.
  - Een auto-geseede `ja` die nooit onderbouwd wordt, is in de praktijk niet
    anders dan de stille drift die deze hele voorziening moest voorkomen.
- **Puur procesmatig, raakt geen specificatie** (bijv. `ci-conventie`,
  `deploy-guards`): een gewone **gesloten ja/nee-vraag** volstaat, meerdere
  tegelijk in één keuzeprompt; bij meer dan vier vragen in rondes.

## Vastleggen

Schrijf elk antwoord als rij in `WORKFLOW-ADOPTIE.md`:
`| <wijziging-id> | ja/nee | <datum> | <toelichting> |`. De toelichting is bij
elk antwoord de redenering, niet alleen bij "nee" — dat is precies het punt van
de onderbouwingsplicht.

Voer bij "ja" uit wat de entry onder "Ja betekent" beschrijft. Is dat meer dan
een handeling van niets (bijvoorbeeld projectcode aanpassen), maak er dan een
GitHub-issue voor in plaats van het meteen in diezelfde sessie te doen.

Het antwoordbestand wordt gecommit: of een project een afspraak toepast is een
eigenschap van het project, niet van de machine waarop je toevallig werkt.
