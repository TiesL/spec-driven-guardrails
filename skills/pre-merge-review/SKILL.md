---
name: pre-merge-review
description: >
  Hoe de kwaliteitsreview vóór een merge draait: verse context, een model dat
  minstens zo vaardig is als wie de code schreef, scope proportioneel aan de
  PR, bevindingen in de PR zelf. Gebruik dit vóór je een PR merget, of
  wanneer iemand vraagt hoe de kwaliteitsreview werkt.
context: fork
allowed-tools: Read, Grep, Glob, Bash
---

## Kwaliteitsreview vóór de merge

Ties kan de technische output niet zelf volledig beoordelen. De review moet dus
*leesbaar bewijs* opleveren in plaats van een geruststelling.

**Hoe hij draait.** `context: fork` geeft de verse, geïsoleerde context — geen
"ik heb dit net gebouwd en het werkt" in de context. Het model is bewust niet
vastgepind in de frontmatter — zie **Modelkeuze** hieronder. `allowed-tools`
sluit `Edit`/`Write`/`NotebookEdit` uit: deze skill kan de werkkopie niet met
een editortool wijzigen. `Bash` staat wél toe (nodig voor `scope.sh`, `gh pr
diff`, het bevindingen-comment plaatsen) en is dus geen technisch afgedwongen
schrijfverbod — gebruik het uitsluitend om te lezen en om het comment te
plaatsen, nooit om bestanden te wijzigen. Deze skill levert bevindingen, geen
fixes.

## Modelkeuze

Geen vast model — dat zou niet meewegen wat de PR daadwerkelijk vraagt, en
Ties wil bewust variëren in modelgebruik in plaats van reflexmatig overal het
zwaarste model in te zetten. Kies per aanroep een model dat **minstens zo
vaardig is als het model dat de gereviewde wijziging schreef**, en binnen die
ondergrens het meest kosteneffectieve. Een eenvoudige wijziging van een licht
model mag met een licht model gereviewd worden; een wijziging van een zwaar
model verdient nooit een lichtere reviewer.

Wijkt de gekozen keuze af van wat voor de hand ligt, maak dat dan zichtbaar —
in de PR of het bevindingen-comment — zodat een lezer achteraf ziet welk
model reviewde en waarom. De rest van deze procedure (geïsoleerde context,
`scope.sh`, `scenario-poort.sh`, de marker) verandert niet mee met de
modelkeuze: dat is een aparte knop, geen package deal — een afwijkende
modelkeuze is geen vrijbrief om ook de rest van de procedure over te slaan.

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
`nfr/`-register van `spec-driven-guardrails` en meldt dat op stderr — een project
zonder ankers blokkeert de review dus niet, hij degradeert.

Een NFR-regel die eindigt op `[vereist onderbouwing]` betekent: die
`WORKFLOW-ADOPTIE.md`-rij draagt nog de voorlopige stempel uit F6, geen echt
"ja". Behandel dat als reviewbevinding (zie hieronder) — niet als een gewone
scoperegel om op te reviewen.

Het lezen van de diff zelf wordt gedelegeerd aan de bestaande
`code-review`-skill, met deze scope als invoer.

## De PR-poort (schakel 2 en 3, W20)

Naast de NFR-scope hierboven controleert deze skill ook de traceabilityketen
richting issues, met `gh` en netwerk die hij toch al gebruikt:

**Schakel 2 — wordt elk scenario door een issue genoemd?** Draai:

```
.claude/skills/pre-merge-review/scenario-poort.sh .
```

Dat print, één per regel, elk scenario-ID uit `TEST-SCENARIOS.md` dat door
geen enkel issue in zijn `**Dekt:**`-veld genoemd wordt. Alleen dat veld telt
— een ID dat toevallig in een zin voorkomt (bijvoorbeeld "we hebben inmiddels
s1 varianten getest") is geen verwijzing. Elke gemelde regel is een bevinding.

**Schakel 3 — verwijst déze PR naar een issue?** Eén aanroep:

```
gh pr view --json closingIssuesReferences --jq '.closingIssuesReferences | length'
```

Is dat `0`, dan is dat een bevinding: de PR mist `Closes #<issue>` of een
gelinkt issue. Dezelfde controle staat als hard slot in CI (W19b,
`check-pr-issue-link.sh`) — deze skill draait hem daarnaast al vóór de merge,
met de bevinding in de PR zelf.

Beide controles falen open zonder `gh` of netwerk: een waarschuwing, geen
blokkade — dezelfde grondregel als de deploy-guards en de merge-guard (W10b).

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
