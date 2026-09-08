---
name: Work item
about: Concreet, testbaar stuk werk (onderdeel van een epic)
title: ""
labels: ""
---

## Beschrijving
<!-- Wat moet er gebouwd/gewijzigd worden, en waarom -->

## Acceptatiecriteria
<!--
  Given/When/Then, dezelfde notatie als TEST-SCENARIOS.md.

  Nummer ze `AC<n>`, niet `S<n>`. Die laatste is de nummering van
  TEST-SCENARIOS.md, en als een issue zijn eigen criteria zo noemt, raakt elke
  zoekactie naar scenarioverwijzingen het issue zelf — dan valt niet meer vast
  te stellen welk scenario werkelijk een issue heeft.

  `S<n>` hoort hier dus alleen thuis als verwijzing naar een scenario, in het
  veld **Dekt:** hieronder.
-->

### AC1: <naam van het criterium>
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
**Dekt:** <F1, S2>
**Blocked by:** #
**Blocks:** #
<!--
  **Dekt:** noemt wat dit werkitem realiseert: functionaliteit uit PRD.md en
  scenario's uit TEST-SCENARIOS.md, komma-gescheiden, bijvoorbeeld `F3, S7, S8`.
  Eén veldnaam voor beide richtingen — het prefix van het token zegt al welke
  kant het op wijst.

  Elk token matcht `^[A-Z]{1,2}[0-9]+[a-z]?$`. Die letter aan het eind is geen
  slordigheid maar bestaand gebruik (`S2b`); twee beginletters ook (`OP4`).
  Alleen dit veld telt — een ID dat in lopende tekst voorkomt is geen
  verwijzing.

  Het prefix ligt niet vast: `F`/`S` is gebruikelijk, maar een project dat zijn
  scenario's `R`/`A`/`B`/`P` nummert werkt ongewijzigd. De controle toetst dat
  het token oplost naar een bestaande kop, niet welke letter ervoor staat.
-->
