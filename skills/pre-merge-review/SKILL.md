---
name: pre-merge-review
description: >
  Hoe de kwaliteitsreview vóór een merge draait: verse context, een ander
  (bij voorkeur zwaarder) model, scope proportioneel aan de PR, bevindingen in
  de PR zelf. Gebruik dit vóór je een PR merget, of wanneer iemand vraagt hoe
  de kwaliteitsreview werkt.
context: fork
model: opus
allowed-tools: Read, Grep, Glob, Bash
---

## Kwaliteitsreview vóór de merge

Ties kan de technische output niet zelf volledig beoordelen. De review moet dus
*leesbaar bewijs* opleveren in plaats van een geruststelling.

**Hoe hij draait.** `context: fork` geeft de verse, geïsoleerde context — geen
"ik heb dit net gebouwd en het werkt" in de context — en `model: opus` pint een
ander, zwaarder model dan waarschijnlijk de code schreef. `allowed-tools` sluit
`Edit`/`Write`/`NotebookEdit` uit: deze skill kan de werkkopie niet met een
editortool wijzigen. `Bash` staat wél toe (nodig voor `scope.sh`, `gh pr diff`,
het bevindingen-comment plaatsen) en is dus geen technisch afgedwongen
schrijfverbod — gebruik het uitsluitend om te lezen en om het comment te
plaatsen, nooit om bestanden te wijzigen. Deze skill levert bevindingen, geen
fixes.

## De scope

**Altijd**, ongeacht welke NFR's dit project heeft gekozen: complexiteit (is
dit de eenvoudigste vorm die werkt?) en dependencies (is een nieuwe
afhankelijkheid nodig, onderhouden, veilig?) — basishygiëne, niet optioneel.

**Daarbovenop**: precies de NFR's waarvoor de bijbehorende `spec-*`-vraag in
dit project met "ja" is beantwoord (`WORKFLOW-ADOPTIE.md`) — er wordt niet
gereviewd op iets wat niet eens gespecificeerd is.

Bereken die scope niet uit het hoofd — draai:

```
.claude/skills/pre-merge-review/scope.sh .
```

Dat print, één per regel: `complexiteit`, `dependencies`, en daarna per
beantwoorde NFR `<id>: <kopnaam>` — waarbij `<kopnaam>` de `###`-sectie in
`PRD.md` is die bij het gegenereerde anker (`<!-- nfr: <id> -->`, uit F4)
hoort. Ontbreekt dat anker, dan valt het script terug op de kopnaam uit het
`nfr/`-register van `claude-workflow` en meldt dat op stderr — een project
zonder ankers blokkeert de review dus niet, hij degradeert.

Een NFR-regel die eindigt op `[vereist onderbouwing]` betekent: die
`WORKFLOW-ADOPTIE.md`-rij draagt nog de voorlopige stempel uit F6, geen echt
"ja". Behandel dat als reviewbevinding (zie hieronder) — niet als een gewone
scoperegel om op te reviewen.

Het lezen van de diff zelf wordt gedelegeerd aan de bestaande
`code-review`-skill, met deze scope als invoer.

## Onderbouwingsgat als bevinding

Raakt de PR een onderwerp waarvan de scope-regel `[vereist onderbouwing]`
draagt, dan is dat zelf een expliciete bevinding in de PR: de bijbehorende
`WORKFLOW-ADOPTIE.md`-rij moet vóór de merge een echt antwoord krijgen (zie de
skill `adoption-registry`) — dit is de eerste poort van de gefaseerde
onderbouwingsplicht (F6).

## De marker

Plaats in het bevindingen-comment op de PR, op een eigen regel, letterlijk:

```
<!-- pre-merge-review:done -->
```

Machineherkenbaar en vast — nooit parafraseren. De merge-guard (F8, W10b)
zoekt hier straks op.

## Wat ermee gebeurt

De bevindingen komen in de PR te staan, niet alleen in de chat: leesbaar,
blijvend, achteraf terug te vinden. Elke bevinding wordt daarna óf opgelost,
óf vastgelegd onder *Technical debt* in de PRD met een reden. Niets verdwijnt
stilzwijgend.

## De grens ervan

Modellen delen veel trainingsdata, dus ook een ander model heeft deels
overlappende blinde vlekken. Dit verhoogt de bodem; het vervangt geen ervaren
engineer die met andere ogen kijkt.
