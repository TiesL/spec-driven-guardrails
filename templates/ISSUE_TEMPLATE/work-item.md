---
name: Work item
about: Concreet, testbaar stuk werk (onderdeel van een epic)
title: ""
labels: ""
---

## Beschrijving
<!-- Wat moet er gebouwd/gewijzigd worden, en waarom -->

## Acceptatiecriteria
<!-- Given/When/Then — zelfde notatie als TEST-SCENARIOS.md -->

### S1: <naam scenario>
- Given ...
- When ...
- Then ...

## Gerelateerd
<!--
  Blocked by / Blocks maken het werk leesbaar als afhankelijkheidsgraaf in
  plaats van als platte lijst. Vul ze aan beide kanten in: staat de edge maar
  op een plek, dan klopt de volgorde vanuit het andere issue gezien niet, en
  precies daar wordt hij gelezen.

  Bewust dit platte veld en geen native sub-issues: `gh issue view` toont
  blocked-by/blocking al, en native relaties binden de conventie aan GitHub
  Projects.
-->
**Epic:** #
**Blocked by:** #
**Blocks:** #
<!--
  W18 voegt hier `**Dekt:**` toe, tussen Epic en Blocked by — dat is de volgorde
  die de bestaande issues gebruiken. De twee regels hieronder vervallen dan.
-->

PRD-sectie (indien van toepassing):
TEST-SCENARIOS.md-scenario('s):
