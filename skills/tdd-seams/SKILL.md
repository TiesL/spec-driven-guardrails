---
name: tdd-seams
description: >
  Test-first werken op vooraf afgesproken seams: rood-vóór-groen-discipline en
  de drie met naam benoemde anti-patronen om te vermijden (implementatie-
  gekoppeld, tautologisch, horizontaal slicen). Gebruik dit bij het schrijven
  van tests, of wanneer je twijfelt of een test het juiste toetst.
---

## Seams, niet interne details

Een seam is het publieke grensvlak waarop een test mag aangrijpen — een
functiesignatuur, een CLI-aanroep, een API-response. Nooit een interne
implementatiestap. Spreek de seam vooraf af, niet achteraf tijdens het
schrijven van de test: wie eerst de implementatie schrijft en dan een seam kiest
die daar toevallig bij past, test de implementatie na in plaats van het gedrag.

## Rood-vóór-groen

De test staat eerst, en staat aantoonbaar rood vóór er ook maar één regel
implementatie bijkomt. Dat is niet een volgorde-voorkeur maar het enige bewijs
dat de test iets echt toetst: een test die je nooit hebt zien falen, kan ook
niet falen wanneer het gedrag breekt. Dit repo past dat op zichzelf toe (zie
"Rood vóór groen" in `TEST-SCENARIOS.md`) — elk nieuw scenario staat eerst rood,
op de regressiescenario's R1–R9 na, die juist groen horen te zijn.

## Drie anti-patronen, met naam

**Implementatie-gekoppeld.** De test kent interne details (een privé-functie,
een tussenliggende datastructuur, de volgorde van interne aanroepen) in plaats
van alleen de seam. Zo'n test breekt bij elke refactor die het gedrag intact
laat — en beloont dus code die nooit meer aangeraakt wordt, niet code die
correct is.

**Tautologisch.** De test herhaalt de implementatie in plaats van het gedrag te
toetsen — bijvoorbeeld een mock die precies teruggeeft wat de test verwacht, of
een assertie die letterlijk dezelfde berekening uitvoert als de code zelf. Zo'n
test kan per constructie niet rood staan, en bewijst dus niets.

**Horizontaal slicen in plaats van verticale slices.** Tests per laag (alle
repository-tests, dan alle service-tests, dan alle controller-tests) in plaats
van per gedrag, van seam tot seam. Horizontaal slicen laat een half werkend
scenario groen ogen omdat elke laag apart getest is, terwijl de lagen samen het
gedrag nog niet leveren — verticaal, één scenario tegelijk, voorkomt dat.

## Verhouding tot `test-unit`/`test-feature-gwt`

Die twee `CHANGES.md`-entries vragen alleen óf een project tests heeft. Deze
skill schrijft *hoe* — een aparte, aanvullende adoptievraag (`test-tdd-seams`),
zodat een project er een eigen onderbouwde keuze over maakt.
