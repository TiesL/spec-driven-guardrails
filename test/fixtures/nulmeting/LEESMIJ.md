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

`CHANGES.md.momentopname` staat één niveau hoger. Die hoort erbij: de
openstaand-set is een functie van **twee** invoeren — de projecttoestand én
`CHANGES.md`. Zonder die tweede is een gouden set niet te interpreteren.

## De uitgangstoestand zelf

| Project | `WORKFLOW-ADOPTIE.md` | `package.json` | `deploy`-script | Openstaand |
|---|---|---|---|---|
| `a2t-emails` | **geen** | ja | nee | 25 |
| `tennis-admin` | ja (3 antwoorden) | ja | ja | 24 |
| `tennis-registration` | ja (1 antwoord) | nee | n.v.t. | 24 |
| `tennis-invoicing` | ja (1 antwoord) | nee | n.v.t. | 24 |

De drie projecten met een tabel melden **exact dezelfde** 24 ID's, ondanks een
verschillend aantal antwoorden. Dat is geen toeval en geen fout:

- `prd-testscenarios-issue-templates` is geretireerd en wordt sowieso nooit
  gevraagd — dat antwoord telt dus nergens mee.
- `tennis-admin` beantwoordde daarnaast `ci-conventie` en `deploy-guards`, maar
  juist die twee zijn voor de andere twee projecten **niet van toepassing** (geen
  `package.json`, dus geen van beide predicaten is waar).

Netto vallen aan beide kanten dezelfde twee vragen weg, om verschillende redenen.

## `a2t-emails` is bewust niet gerepareerd

Dit project heeft **helemaal geen** `WORKFLOW-ADOPTIE.md`, dus staat alles open —
25, want zijn `package.json` maakt `ci-conventie` van toepassing.

Dat bestand is hier bewust niet aangemaakt. Een fixture hoort de toestand vast te
leggen zoals die was, niet de reparatie ervan; anders meet R9 straks tegen een
bewerkte werkelijkheid. Het aanvullen zelf is apart belegd in W12b (#28), met de
uitdrukkelijke eis dat het geen verse seed met de datum van vandaag wordt — dat
zou vervalsen wanneer een keuze daadwerkelijk gemaakt is.

## Controleren

```bash
./check          # scenario S4 draait deze fixtures
```

## Bijwerken — alleen bewust

Een afwijking betekent één van twee dingen:

1. **Het gedrag is veranderd.** Dat is wat R9 moet vangen. Onderzoeken, niet
   wegpoetsen.
2. **De vraagset is legitiem gewijzigd** — bijvoorbeeld doordat een werkitem een
   nieuwe entry aan `CHANGES.md` toevoegt (W14, W15 en W16b doen dat). Dan hoort
   de gouden set bijgewerkt te worden, mét toelichting in de PR wélke ID's erbij
   komen of verdwijnen en waarom.

Een stille wijziging in de vraagset is nooit acceptabel, ook niet als
"opschoning".
