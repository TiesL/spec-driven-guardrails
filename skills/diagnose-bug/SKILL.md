---
name: diagnose-bug
description: >
  Reproductie → hypotheses → regressietest, in die dwingende volgorde, vóór er
  ook maar aan een fix begonnen wordt. Gebruik dit bij het diagnosticeren van
  een bug, vóór je een `fix/<naam>`-branch opent.
---

## De dwingende volgorde

**1. Reproductie.** Bouw eerst een deterministische, zelf uitvoerbare
reproductie — een commando of test die de bug betrouwbaar laat zien, zonder
menselijke tussenstap. Zonder dat weet je aan het eind niet zeker of je de bug
hebt opgelost of alleen even niet meer ziet.

**2. Hypotheses — getoond vóór ze getest worden.** Formuleer falsifieerbare
hypotheses over de oorzaak, en laat ze aan Ties zien vóórdat je ze test. Niet
achteraf samenvatten wat je hebt geprobeerd: hypotheses die pas na afloop
gedeeld worden zijn niet meer te corrigeren door iemand die de code niet zelf
leest. Een hypothese die je zelf niet met een concreet experiment kunt
weerleggen, is geen hypothese maar een gok.

**3. Regressietest — vóór de fix.** Schrijf de test die de bug vastlegt vóór je
de fix schrijft, en bevestig dat hij rood staat op de reproductie uit stap 1.
Een fix zonder voorafgaande falende test bewijst niets: hij kan toevallig
werken, of een symptoom verhelpen zonder de oorzaak te raken.

**4. Fix.** Pas nu de daadwerkelijke wijziging toe, en bevestig dat de
regressietest uit stap 3 groen wordt.

## Waarom deze volgorde, niet een andere

Elke stap is een controle op de vorige. Reproductie zonder hypotheses leidt tot
gokken-en-proberen. Hypotheses zonder ze eerst te tonen zijn niet corrigeerbaar.
Een fix zonder voorafgaande regressietest laat geen bewijs achter dat de bug
ooit weg was — alleen dat de code er nu anders uitziet.

## Verhouding tot `tdd-seams`

Stap 3 volgt dezelfde rood-vóór-groen-discipline als `tdd-seams`, toegepast op
één specifiek scenario: de regressietest ís de seam waarop deze bug zich
voordeed, niet een interne implementatiestap.
