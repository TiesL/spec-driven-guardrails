---
name: pre-merge-review
description: >
  Hoe de kwaliteitsreview vóór een merge draait: verse context, een ander
  (bij voorkeur zwaarder) model, scope proportioneel aan de PR, bevindingen in
  de PR zelf. Gebruik dit vóór je een PR merget, of wanneer iemand vraagt hoe
  de kwaliteitsreview werkt.
---

## Kwaliteitsreview vóór de merge

Ties kan de technische output niet zelf volledig beoordelen. De review moet dus
*leesbaar bewijs* opleveren in plaats van een geruststelling.

**Hoe hij draait.** Met verse context en op een ander model dan dat de code
schreef, bij voorkeur een zwaarder model. Verse context is de grootste winst: een
reviewronde zonder het verhaal "ik heb dit net gebouwd en het werkt" in zijn
context ziet meer. Andere modelgewichten helpen daarbovenop, want blinde vlekken
zitten deels in het model zelf — wie bij het schrijven niet aan een race
condition dacht, ziet hem bij het teruglezen vaak ook niet.

**Waarop.** Proportioneel aan wat de PR raakt; een documentatiewijziging vraagt
geen securityreview.

- **Altijd**, ongeacht welke NFR's dit project heeft gekozen: complexiteit (is
  dit de eenvoudigste vorm die werkt?) en dependencies (is een nieuwe
  afhankelijkheid nodig, onderhouden, veilig?) — basishygiëne, niet optioneel.
- **Daarbovenop**: precies de NFR's waarvoor de bijbehorende `spec-*`-vraag in
  dit project met "ja" is beantwoord (zie `WORKFLOW-ADOPTIE.md`) — er wordt niet
  gereviewd op iets wat niet eens gespecificeerd is. Het prefix `spec-` staat
  één-op-één voor de vijftien subsecties onder "Niet-functionele kenmerken" in
  `templates/PRD.md`; `proces-`- en `test-`-entries vallen hier dus niet onder.

**Wat ermee gebeurt.** De bevindingen komen in de PR te staan, niet alleen in de
chat: leesbaar, blijvend, achteraf terug te vinden. Elke bevinding wordt daarna
óf opgelost, óf vastgelegd onder *Technical debt* in de PRD met een reden. Niets
verdwijnt stilzwijgend.

**De grens ervan.** Modellen delen veel trainingsdata, dus ook een ander model
heeft deels overlappende blinde vlekken. Dit verhoogt de bodem; het vervangt geen
ervaren engineer die met andere ogen kijkt.
