# Nulmeting — de vastgelegde uitgangstoestand

Dit is het vangnet van de release "Van proza naar mechanisme". Hier staat, per
geadopteerd project, **wat `pending-changes.sh` meldde vóórdat er iets aan de
scripts veranderde**. Elke latere refactor moet exact dezelfde uitkomst blijven
geven; wijkt hij af, dan is dat een gedragswijziging die uitgelegd moet worden —
niet iets om de gouden set even op aan te passen.

Vastgelegd voor werkitem W2 (#13). Regressiescenario R9 leunt hierop.

## Wat er per project staat

| Bestand | Wat het is |
|---|---|
| `bron.txt` | Herkomst: pad, project-HEAD, `claude-workflow`-commit, datum |
| `WORKFLOW-ADOPTIE.md` | Verbatim overgenomen — dit is het antwoordregister |
| `package.json` | Verbatim overgenomen — de predicaten kijken hiernaar |
| `verwacht-openstaand.txt` | De gouden set: openstaande ID's, alfabetisch |

`CHANGES.md.momentopname` en `nfr.momentopname/` staan één niveau hoger. Die
horen erbij: de openstaand-set is een functie van **drie** invoeren — de
projecttoestand, `CHANGES.md` én het `nfr/`-register (zie "Bijgewerkt in W28"
hieronder). Zonder die laatste twee is een gouden set niet te interpreteren.

## De uitgangstoestand zelf

| Project | `WORKFLOW-ADOPTIE.md` | `package.json` | `deploy`-script | Openstaand |
|---|---|---|---|---|
| `a2t-emails` | **geen** | ja | nee | 26 |
| `tennis-admin` | ja (3 antwoorden) | ja | ja | 25 |
| `tennis-registration` | ja (1 antwoord) | nee | n.v.t. | 24 |
| `tennis-invoicing` | ja (1 antwoord) | nee | n.v.t. | 24 |

De twee projecten zonder `package.json` melden **exact dezelfde** 24 ID's als
`tennis-admin` vóór W24, ondanks een verschillend aantal antwoorden. Dat is geen toeval en geen fout:

- `prd-testscenarios-issue-templates` is geretireerd en wordt sowieso nooit
  gevraagd — dat antwoord telt dus nergens mee.
- `tennis-admin` beantwoordde daarnaast `ci-conventie` en `deploy-guards`, maar
  juist die twee zijn voor de andere twee projecten **niet van toepassing** (geen
  `package.json`, dus geen van beide predicaten is waar).

Netto vallen aan beide kanten dezelfde twee vragen weg, om verschillende redenen.

## Bijgewerkt in W24 (#45)

De aantallen hierboven waren bij het invriezen 25 / 24 / 24 / 24. W24 voegde de
entry `ci-op-pr-en-main` toe met predicaat `heeft-package-json`, en dat raakt
precies de twee projecten die er een hebben: `a2t-emails` (25 naar 26) en
`tennis-admin` (24 naar 25). De twee geneste projecten hebben geen
`package.json` en blijven op 24.

Dat is de tweede soort afwijking uit "Bijwerken — alleen bewust" hieronder: een
legitiem gewijzigde vraagset, niet een gedragswijziging.

`CHANGES.md.momentopname` is in dezelfde PR ververst. Die verversing haalt meer
op dan alleen deze entry: de momentopname stond stil sinds W2, terwijl W4, W5 en
W6 `CHANGES.md` intussen hadden verbouwd. Nagerekend welke ID's dat verschil
maakt: de vijftien `spec-*`-entries zijn naar `nfr/` verhuisd (W5),
`prd-testscenarios-issue-templates` is naar `CHANGES-ARCHIEF.md` gegaan (W6), en
de sectiekoppen werden `###` (W4/W6). Geen van die drie voegde een vraag toe of
haalde er een weg, dus de gouden sets bleven al die tijd kloppen — maar het is
wel stilzwijgend meegelift en hoort hier vermeld.

**Dit gat is gedicht in W28** — zie hieronder. Ter geschiedenis, hoe het gat
ontstond: de vraagset komt sinds W5 uit twee bronnen, `CHANGES.md` én `nfr/`,
terwijl de gouden sets vol `spec-*`-ID's staan die uit de tweede komen. Tussen
W5 en W28 was alleen de eerste bron ingevroren; wie de nulmeting in die periode
wilde interpreteren, had het `nfr/`-register nodig zoals dat op dat moment was
— versiebeheerd en door `check` bewaakt op interne consistentie
(`nfr_drift`), dus terug te vinden, maar niet ingevroren zoals `CHANGES.md`
dat wel was.

## `a2t-emails` is bewust niet gerepareerd

Dit project heeft **helemaal geen** `WORKFLOW-ADOPTIE.md`, dus staat alles open —
26, want zijn `package.json` maakt zowel `ci-conventie` als `ci-op-pr-en-main`
van toepassing.

Dat bestand is hier bewust niet aangemaakt. Een fixture hoort de toestand vast te
leggen zoals die was, niet de reparatie ervan; anders meet R9 straks tegen een
bewerkte werkelijkheid. Het aanvullen zelf is niet in W12b (#28) gebeurd maar
apart, op 5 september 2026 in TiesL/a2t-emails#11 tijdens de uitrol van W8 — de
echte checkout heeft inmiddels dus wél een `WORKFLOW-ADOPTIE.md`, met de
adoptiedatum van dat moment, niet een verzonnen historisch besluit. Deze
fixture blijft bewust op de oudere, "alles openstaand"-toestand staan.

## Wat deze nulmeting **niet** dekt

De vier bevroren projecten raken samen niet elke tak van de predicaatlogica. Eén
gat is bekend en gemeten:

**`heeft-deploy-script` is nergens tegelijk waar én onbeantwoord.** Alleen
`tennis-admin` heeft een `package.json` mét `"deploy"`-script, en juist dat
project heeft `deploy-guards` al beantwoord. Daardoor landt dat predicaat in geen
enkele gouden set, en zou een te streng geworden versie ervan — bijvoorbeeld door
een fout tijdens de verhuizing naar `lib/changes.sh` (F3) — hier ongemerkt
doorglippen. Aangetoond met een mutatie: `heeft-deploy-script` altijd onwaar maken
laat S4 gewoon slagen. De omgekeerde fout (predicaat te ruim) wordt wél gevangen,
net als beide fouten in `heeft-package-json`.

Dat gat wordt gesloten door **R6** in W3 (#14), waarvan de scenariotekst hierop is
aangescherpt: die eist per predicaat minstens één geval dat waar én onbeantwoord
is, en expliciet vastgelegde uitkomsten in plaats van alleen onderlinge
vergelijking — twee identiek kapotte predicaten zijn het namelijk met elkaar eens.

Vertrouw deze nulmeting dus voor wat hij is: een vangnet voor de
**antwoordregistratie**, niet voor de volledige predicaatwaarheidstabel.

## Controleren

```bash
./check          # scenario S4 draait deze fixtures
```

## Bijgewerkt in W19 (#31)

`traceability-schakel-1` is toegevoegd aan `CHANGES.md`, met
`Van toepassing als: altijd`. Elk van de vier projecten krijgt die vraag erbij,
dus elke gouden set groeit met exact dat ene ID: a2t-emails 27, tennis-admin 26,
tennis-registration en tennis-invoicing elk 25. `CHANGES.md.momentopname` is in
dezelfde PR ververst.

Wat níét verandert: geen bestaande ID is hernoemd of verdwenen, en geen predicaat
is aangepast. De toename is overal precies één.

## Bijgewerkt in W28 (#51)

Het gat hierboven ("wat de momentopname sinds W5 niet meer dekt") is gedicht:
`nfr.momentopname/` bevat nu een verbatim kopie van `nfr/` op het moment van
invriezen (`cp -r nfr test/fixtures/nulmeting/nfr.momentopname`). Geen
aparte generator: een directe kopie is proportioneel voor vijftien bestanden,
en S66 controleert drie dingen: elk `spec-*`-ID uit elke gouden set vindt een
ingevroren bestand terug, de kopie zelf is nog een geldig register
(`nfr_valideer` — een corrupte freeze mag het vangnet niet stil laten
leeglopen), én de kopie is nog exact gelijk aan het huidige `nfr/`. Die derde
controle is de bewuste rookmelder: hij hoort **op een dag te gaan afgaan**,
namelijk zodra `nfr/` legitiem wijzigt zonder dat de freeze meeverst — precies
het moment waarop deze procedure hierboven van toepassing wordt.

Geen enkele gouden set veranderde door dit werkitem: het bevriest alleen de
tot dan toe niet-ingevroren bron, het verandert niets aan wat die bron zegt.
S67 toont met een mutatie aan dat een latere, wél vraagset-rakende wijziging
in `nfr/` (elk bestand daar draagt `van-toepassing-als: altijd`, dus raakt
alles alle vier de fixtures) door R9 wordt opgevangen — en herinnert er via
`LEESMIJ.md`'s "Bijwerken — alleen bewust" aan dat `nfr.momentopname/` in dat
geval bewust mee moet verversen, net als `CHANGES.md.momentopname`.

## Bijgewerkt in W14 (#24), W15 (#25) en W16b (#26)

Dit keer wél: drie nieuwe `CHANGES.md`-entries in één bundel-PR, alle drie
`Van toepassing als: altijd`. `test-tdd-seams` en `proces-diagnose-bug` zijn
`Standaard: ja` en worden dus bij adoptie geseed (niet als openstaand
getoond); `proces-context-document` is `Standaard: vraag` en verschijnt wél
als openstaand. Netto effect op de vier gouden sets: elk +3 (twee geseede
entries tellen niet mee in de openstaand-set, maar de derde — als open
vraag — wel; alle drie tellen mee waar het gaat om wélke ID's een gouden set
bevat, want een geseede `ja`-rij hoort net zo goed in de set van "ID's die nu
bestaan" als een openstaande). Concreet: a2t-emails 27→30, tennis-admin
26→29, tennis-registration en tennis-invoicing elk 25→28.
`CHANGES.md.momentopname` is in dezelfde PR (drie keer, per commit) ververst.

## Bijgewerkt voor issue #74 (ci-schakel-3-hard-slot)

W19b (#32) voegde `check-pr-issue-link.sh` toe, gescaffold via `adopt.sh` en
verwerkt in `templates/ci.yml` — maar `scaffold_if_missing` laat een al
bestaande `ci.yml` ongemoeid, dus bestaande `package.json`-projecten kregen
de stap nooit vanzelf. Nieuwe entry `ci-schakel-3-hard-slot`
(`heeft-package-json`, zelfde predicaat als `ci-conventie`/`ci-op-pr-en-main`)
maakt dat zichtbaar. Raakt `a2t-emails` en `tennis-admin` (beide hebben een
`package.json`); `tennis-registration` en `tennis-invoicing` niet. Elk +1:
a2t-emails 30→31, tennis-admin 29→30. `CHANGES.md.momentopname` ververst.

## Bijgewerkt in W27 (#48)

Zelfde patroon, ditmaal proactief in plaats van achteraf gerepareerd:
`check-main-via-pr.sh` (schakel tegen commits op `main` buiten een PR om)
krijgt meteen een eigen `CHANGES.md`-entry, `ci-detecteert-main-buiten-pr`
(`heeft-package-json`), zodat `a2t-emails` en `tennis-admin` — die al een
eigen `ci.yml` hadden vóór dit werkitem — de vraag alsnog voorgelegd krijgen.
Elk +1: a2t-emails 31→32, tennis-admin 30→31. `CHANGES.md.momentopname`
ververst.

## Bijgewerkt voor W42 (#114)

Geen toename of afname, maar wel een naamswijziging: de laag-B-migratie
hernoemt twee entry-ID's van Nederlands naar Engels —
`proces-context-document` wordt `process-context-document`,
`kwaliteitsreview-voor-merge` wordt `quality-review-before-merge`. Beide
stonden in alle vier de gouden sets als openstaand (nooit beantwoord door
een van de vier projecten), dus de tel blijft ongewijzigd; alleen de
letterlijke ID-string in `verwacht-openstaand.txt` verandert, met een
herberekende alfabetische positie (`process-` sorteert ná alle `proces-*`,
`quality-` ná `proces(s)-` en vóór `spec-*`). `CHANGES.md.momentopname`
ververst.

Dit is tegelijk het eerste échte gebruik van dit soort golden-set-fixture
voor een gedragswijziging in plaats van alleen een vraagset-uitbreiding:
`pending-changes.sh` behandelt een project met de pre-migratie
`WORKFLOW-ADOPTIE.md` (geen `WORKFLOW-ADOPTION.md`) nu ook als een project
dat per rij gemeld moet worden (zie S85) — maar dat raakt uitsluitend de
nieuwe migratiemelding, niet de openstaand-lijst die `openstaande_ids()`
uitleest (bewust een ander regelprefix, zodat de twee elkaar niet kunnen
verwarren). De vier bevroren projecten missen allemaal een
`WORKFLOW-ADOPTION.md`, dus die melding verschijnt voortaan bij elke R9-run
— dat is verwacht en onderdeel van S85, niet van R9's eigen contract.

## Bijgewerkt voor #156

Vijf `nfr/`-bestandsnamen (en dus hun `spec-*`-ID) zijn van Nederlands naar
Engels hernoemd: `spec-data-integriteit` → `spec-data-integrity`,
`spec-documentatie` → `spec-documentation`, `spec-kostenbeheersing` →
`spec-cost-management`, `spec-performance-schaal` →
`spec-performance-scale`, `spec-backup-herstel` → `spec-backup-recovery`.
Zelfde soort wijziging als W42 (#114) hierboven, nu toegepast op de
`nfr/`-bron in plaats van op `CHANGES.md`: geen van de vier bevroren
projecten had een van deze vijf ooit beantwoord, dus de tel blijft
ongewijzigd — alleen de letterlijke ID-string in elke
`verwacht-openstaand.txt` verandert, met een herberekende alfabetische
positie. `nfr.momentopname/` is ververst (`rm -rf` + `cp -r nfr`), zoals
deze procedure hieronder voorschrijft voor elke wijziging die de vijftien
`nfr/`-bestanden raakt.

Nieuw ten opzichte van W42: `lib/nfr.sh` kreeg `nfr_huidig_id`/`nfr_oude_id`
— een permanente alias tussen elk hernoemd paar, zodat een project dat al
onder de oude naam heeft geantwoord (dit repo zelf deed dat, zie
`WORKFLOW-ADOPTION.md`, en mogelijk een van de drie externe projecten)
dat antwoord niet kwijtraakt. Geen van de vier bevroren fixtures oefent dat
pad uit (zij hadden geen van de vijf ooit beantwoord), dus deze nulmeting
bewijst niets over de alias zelf — dat bewijs levert een aparte, gerichte
test (zie `test/cases/`).

## Bijwerken — alleen bewust

Een afwijking betekent één van twee dingen:

1. **Het gedrag is veranderd.** Dat is wat R9 moet vangen. Onderzoeken, niet
   wegpoetsen.
2. **De vraagset is legitiem gewijzigd** — bijvoorbeeld doordat een werkitem een
   nieuwe entry aan `CHANGES.md` toevoegt (W14, W15 en W16b doen dat), of een
   nieuw `nfr/`-bestand toevoegt/weghaalt/retireert. Dan hoort de gouden set
   bijgewerkt te worden, mét toelichting in de PR wélke ID's erbij komen of
   verdwijnen en waarom. **Ververs in dat geval ook `CHANGES.md.momentopname`
   én `nfr.momentopname/`**:

   ```
   rm -rf test/fixtures/nulmeting/nfr.momentopname
   cp -r nfr test/fixtures/nulmeting/nfr.momentopname
   ```

   De `rm -rf` eerst is geen voorzichtigheid maar noodzaak: `nfr.momentopname/`
   bestaat al na deze PR, en `cp -r nfr <bestaande-map>` nest de bron dan
   ín de map (`nfr.momentopname/nfr/*.md` naast de oude bestanden) in plaats
   van hem te vervangen. Verbatim, geen selectie: laat je die achter, dan verwijst de nulmeting naar
   een bron die de nieuwe gouden set niet meer verklaart — precies de
   interpreteerbaarheid die de momentopname moest garanderen. Alle vijftien
   `nfr/`-bestanden dragen `van-toepassing-als: altijd`, dus raakt elke
   toevoeging, verwijdering of retirement per definitie alle vier de fixtures
   (S67) — een vergeten `nfr.momentopname`-ververs is dus nooit een geval waarin
   toevallig niets verandert.

**Ook een zuivere prozawijziging in `CHANGES.md`** (geen ID, predicaat of
`Van toepassing als` geraakt — bijvoorbeeld een verwijzing die naar een skill in
plaats van naar `WORKFLOW.md` gaat wijzen, zoals in W30) verandert de vraagset
niet en dwingt dus geen gouden-set-update af. `CHANGES.md.momentopname` was tot
dan toe byte-identiek aan `CHANGES.md`; ververs hem in zo'n geval toch, puur om
die identiteit te behouden en te voorkomen dat een latere `diff` tussen de twee
bestanden eruitziet als onopgemerkte drift in plaats van een bewuste, inhoudsloze
verversing.

Een stille wijziging in de vraagset is nooit acceptabel, ook niet als
"opschoning".

## Bijgewerkt voor #160

Bovenstaande regel ("ververs `CHANGES.md.momentopname` ook bij een zuivere
prozawijziging") bleek in de praktijk niet afgedwongen: de snapshot was
sinds #127 (W42) niet meer ververst, terwijl drie latere PR's
(#136/#137/#138) `CHANGES.md`'s hele proza naar het Engels vertaalden — een
drift van 562 regels, gevonden tijdens de review van #159. Niets testte de
twee bestanden tegen elkaar, dus niets sloeg alarm.

`test/cases/s90_changes_momentopname_frozen.sh` (S90) sluit dat gat: een
`diff` tussen `CHANGES.md` en `CHANGES.md.momentopname`, faalt hard bij elk
verschil — dezelfde rookmelder-behandeling die S66 al aan `nfr.momentopname/`
geeft, nu ook hier. Vanaf nu is "ververs de snapshot" geen conventie meer die
op discipline leunt, maar een check die het afdwingt.
