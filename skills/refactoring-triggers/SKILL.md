---
name: refactoring-triggers
description: >
  Complexiteit, technical debt en refactoring als één lus, en de drie
  concrete triggers om af te lossen (ontwerp tegengesproken, code met een
  debt-regel aangeraakt, register dat blijft groeien). Gebruik dit wanneer je
  twijfelt of iets nu gerefactored moet worden of als schuld vastgelegd.
---

## Complexiteit, technical debt en refactoring

Deze drie zijn geen losse aandachtspunten maar één lus: bouwen voegt
complexiteit toe → wat daarvan blijft zitten wordt technical debt → refactoring
is hoe je die afbetaalt. Zonder expliciete triggers gebeurt dat laatste nooit, en
groeit er alleen maar code bovenop code.

**Niet alle complexiteit is gelijk.** Essentiële complexiteit komt uit het domein
zelf en is niet weg te refactoren — die beheers je met structuur. Toevallige
complexiteit komt voort uit hoe iets nu eenmaal gebouwd is, en is wél
reduceerbaar. Alleen de tweede soort is af te betalen; jagen op de eerste is
verspilde moeite.

**Technical debt is breder dan complexiteit alleen** — ook bewuste shortcuts,
verouderde dependencies en ontbrekende tests horen erbij. Het register staat in
de PRD, met per regel waarom het nu acceptabel is en wat de trigger is om het aan
te pakken.

**Refactoring is de aflossing.** Drie triggers, van hard naar zacht:

1. **Het vastgelegde ontwerp wordt tegengesproken.** Merk je bij een work item
   dat het alleen gebouwd kan worden door een architectuureis uit
   `ARCHITECTUUR.md` te schenden, bouw het dan niet alsnog via een omweg. Dat is
   het signaal dat óf het ontwerp herzien moet worden, óf de functionaliteit
   anders ontworpen moet worden — als eigen work item, zodat het zichtbaar
   gebeurt in plaats van als uitzondering weg te zakken in de code. Zo begint
   architectuurerosie: één uitzondering per keer, tot niemand de structuur meer
   herkent.
2. **Je raakt code aan waar al een debt-regel op staat.** Dat is het goedkoopste
   moment om hem af te betalen — je zit er toch al in.
3. **Het register groeit terwijl er niets uit verdwijnt.** Een signaal om te
   kijken wat er structureel misgaat, geen harde regel.
