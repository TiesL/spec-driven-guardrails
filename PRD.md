# PRD — claude-workflow, release "Van proza naar mechanisme"

**Status:** As-built voor epic #11 (gesloten, uitgeleverd 2026-09-06 — zie
`CHANGELOG.md`); "Besloten in W29 (#53)" hieronder stuurt het lopende epic #52.

Vervangt en integreert de drie afzonderlijk aangemaakte epics
[#7](https://github.com/TiesL/claude-workflow/issues/7),
[#8](https://github.com/TiesL/claude-workflow/issues/8) en
[#9](https://github.com/TiesL/claude-workflow/issues/9). Die drie hadden
overlappende doelen en tegenstrijdige volgorde-eisen; dit document is het
geïntegreerde plan, met nieuwe inzichten uit de validatie erin verwerkt.

---

## Context

`spec-driven-guardrails` (voorheen `claude-workflow`, hernoemd in W32/#56) is de
gedeelde bron van waarheid voor Ties' persoonlijke Git/GitHub-workflow,
geadopteerd door vier projecten via lokale symlinks.

Aanleiding is de kwaliteitsreview op PR #6 — de eerste PR waarop de eigen
reviewregel is toegepast. Die vond vier structurele problemen (→ #7) plus een
traceability-gat (→ #8). #9 kwam later, vanuit een vergelijking met
`mattpocock/skills`.

**De rode draad**: dit repo schrijft conventies voor die het zelf niet
controleert. De NFR-lijst staat op twee plekken en wordt met de hand synchroon
gehouden. De predicaatlogica staat twee keer, de predicaatlijst zelfs drie keer.
"Nooit rechtstreeks naar `main`" is een afspraak zonder slot. De
onderbouwingsplicht is proza dat geen script kan zien. De traceabilityvelden zijn
vrije tekst die niemand leest.

Het meetbare gevolg, over vier projecten en 27 gemergede PR's: **nul** PR's
verwijzen naar een issue, **nul** hebben een review, **nul** scenario's hebben een
dekkingsveld, en `kwaliteitsreview-voor-merge` is door geen enkel project ooit
beantwoord. De conventies bestaan; de naleving is nihil.

Deze release verplaatst die conventies van proza naar mechanisme.

### Bewuste afwijking van de afgesproken volgorde

#7 en #8 zijn geblokkeerd op "één echt work item end-to-end". Dat is geverifieerd
**niet gehaald**: de beste kandidaat (tennis-admin PR #5) mist het issue vooraan,
de review in het midden en de acceptatietest vóór de merge, en dateert van vóór de
helft van de regels die hij zou moeten aantonen.

Ties heeft besloten de blokkade te overrulen, **met twee mitigaties**:

1. De veldformaten uit #8 worden eerst samen doorgenomen (W17) — menselijke review
   vervangt daar het ontbrekende praktijkbewijs.
2. De nulmeting wordt vastgelegd als uitvoerbare tests vóór er iets verandert
   (W1–W3). Refactoren tegen aannames is precies wat de blokkade moest voorkomen;
   tests zijn het alternatieve vangnet.

---

## Architectuur

Vier lagen, van hard naar zacht afdwingbaar. **Waar handhaving mogelijk is, geen proza.**

| Laag | Mechanisme | Dwingt af? | Wat er ligt |
|---|---|---|---|
| 1 | **Hooks** (`settings/session-hooks.json`) | Ja, hard | Git-guardrails (`PreToolUse`), merge-guard, fetch/push, melding openstaande wijzigingen |
| 2 | **Scripts + `check`** | Ja, in CI | Predicaten, NFR-consistentie, traceability, regressietests |
| 3 | **Skills** (`skills/<naam>/SKILL.md`) | Nee — laadt op maat | Deploy, adoptieprotocol, review, TDD, bugdiagnose |
| 4 | **Proza** (`WORKFLOW.md` → `CLAUDE.md`) | Nee | Alleen wat élke sessie nodig heeft |

### Correctie op de aanname in #9

#9 stelt: *"Prozabeleid verwatert; een aangeroepen skill niet."* Dat is half waar,
en het onderscheid bepaalt wat deze release kan beloven.

Geverifieerd in de documentatie: **een hook kan een skill niet aanroepen.** Hij kan
er via `systemMessage` naar verwijzen, maar Claude mag dat negeren. Skills geven
**lokaliteit en lagere tokenkosten** — de tekst laadt vers op het moment dat hij
telt — maar **geen handhaving**. De handhavingswinst komt van laag 1 en 2.

### Twee harde randvoorwaarden

**Bash 3.2.** macOS levert `/bin/bash` 3.2.57, en hooks draaien non-interactief met
een minimale `PATH`. Geen `declare -A`, geen `mapfile`, geen `${var,,}`. Set-
vergelijkingen dus via gesorteerde tempfiles en `diff`/`comm`, niet via
associatieve arrays.

**`settings/session-hooks.json` mag niet verplaatsen.** De SessionStart-hook
lokaliseert dit repo via `dirname(dirname(readlink .claude/settings.json))`. Dat
pad verplaatsen breekt elk geadopteerd project stil — die symlinks zijn lokaal,
ongetrackt, en de keten eindigt op `|| true`.

Daaruit volgt een ontwerpregel die de hele release raakt: **wat gesymlinkt is,
is direct live in alle vier de projecten na een `git pull`; wat `adopt.sh`
installeert, niet.** Elke wijziging aan `session-hooks.json` moet dus veilig zijn
in een project dat `adopt.sh` nog niet opnieuw draaide.

---

## Databron(nen)

N.v.t., onderbouwd. Dit repo heeft geen datalaag; zijn "bronnen" zijn getrackte
markdown-bestanden (`CHANGES.md`, straks `nfr/*.md`) die door bash-scripts
geparseerd worden. De parseerbaarheid daarvan is een functionele eis (F3), geen
databron in de zin van dit sjabloon.

---

## Functionaliteit

### F1 — Testharnas en eigen `check`

Pure bash, geen framework. `./check` draait `bash -n` over alle scripts,
valideert `settings/session-hooks.json` als JSON (`jq empty`, anders
`python3 -m json.tool` — het bestand is gesymlinkt, dus één typefout is per
direct kapot in vier projecten en `bash -n` ziet het niet), draait `shellcheck`
als die er is (waarschuwen, niet eisen), dan `test/run.sh`. Elke test draait in
een `mktemp -d`-sandbox met geïnjecteerde `HOME` en `CLAUDE_WORKFLOW_DIR`, met
een harde weigering te draaien als `HOME` na sandboxopzet nog de echte home is.

Maakt R1–R9 en T1–T5 uitvoerbaar in plaats van proza-vinkjes in een PR-body.
Levert tevens het `check`-commando dat dit repo zelf voorschrijft maar niet heeft.

**Geen `package.json` toevoegen** om `templates/ci.yml` te kunnen hergebruiken:
dat zou het eigen `heeft-package-json`-predicaat omzetten en veranderen wat de
scripts over dit repo zeggen. CI roept `./check` rechtstreeks aan — precies het
"andere stack"-geval dat de skill `check-convention` al beschrijft.

### F2 — Vastgelegde nulmeting als fixtures

De huidige uitkomst voor alle **vier** adopters, ingevroren in
`test/fixtures/nulmeting/` als gouden sets, vóór er iets verandert.

Een handmatige dry run tegen kopieën is niet herhaalbaar; invriezen als fixture
maakt R9 een permanente regressietest. De bronnen staan alle vier lokaal —
`tennis-registration` en `tennis-invoicing` als volwaardige git-repo's (eigen
`.git`, eigen remote, eigen `WORKFLOW-ADOPTIE.md`) genest in `tennis-admin/`.

`a2t-emails` is de vierde en heeft **helemaal geen** `WORKFLOW-ADOPTIE.md`. Zijn
nulmeting is dus "alles openstaand" — vastleggen zoals gevonden, niet eerst
repareren, anders legt de fixture de reparatie vast in plaats van de toestand.

**W28:** de vraagset komt sinds W5 uit twee bronnen, `CHANGES.md` én `nfr/`, en
tot W28 was alleen de eerste ingevroren (`CHANGES.md.momentopname`).
`nfr.momentopname/` (verbatim kopie van `nfr/`, één `cp -r`) sluit dat gat —
zie `test/fixtures/nulmeting/LEESMIJ.md`.

### F3 — Gedeelde parser én predicaten (`lib/changes.sh`)

Niet alleen de predicaten zijn gedupliceerd — de hele `CHANGES.md`-parser is dat
(`## `-koppen, `${regel##*\*\* }`, de `case`-skeletten). Beide verhuizen.

```
predicaat_waar <predicaat> <project_dir>   # de enige predicaatlogica
itereer_entries <bron> <callback>          # callback <id> <standaard> <predicaat>
```

De **bewuste asymmetrie** (`adopt.sh` slaat `Standaard: vraag` over,
`pending-changes.sh` negeert `Standaard`) komt in de callback bij de aanroeper te
liggen, met aan beide kanten een comment dat naar de ander verwijst. Beter dan een
`--negeer-standaard`-vlag, die het verschil in de bibliotheek verstopt en het op
een ongelukje laat lijken.

De prozalijst in `CHANGES.md` verwijst voortaan naar de bibliotheek in plaats van
de predicaten een derde keer op te sommen.

### F4 — Eén bron van waarheid voor de NFR's: een `nfr/`-register

De NFR's staan nu op **twee canonieke plekken** in dit repo: als `spec-*`-entries
in `CHANGES.md` (de adoptievraag) en als `###`-subsecties in `templates/PRD.md` (de
invulhulp). Geen van beide is logisch de eigenaar; het zijn twee consumenten van
dezelfde vijftien begrippen. De juiste oplossing is dus niet "koppel A aan B", maar
**abstraheer naar C en laat A en B ernaar verwijzen**.

```
nfr/spec-security.md
nfr/spec-data-integriteit.md
…  (vijftien bestanden)
```

Elk bestand draagt alles wat over die ene NFR bekend is:

```markdown
---
id: spec-security
kop: Security
standaard: ja
van-toepassing-als: altijd
productie-poort: ja
status: actief
---

## Vraag
Is Security relevant genoeg voor dit project om te specificeren (toegang,
autorisatie, secrets)?

## Ja betekent
`PRD.md` beantwoordt de subsectie "Security" — wie mag wat, welke rechten zijn
minimaal nodig, waar staan secrets.

## Invulhulp
Wie mag wat? Welke rechten zijn minimaal nodig? Waar staan secrets, en hoe komen
ze niet in git terecht?
```

Wat daarmee verdwijnt:

- **Het naamgevingsprobleem lost op in plaats van te worden opgevangen.** `id` en
  `kop` staan in hetzelfde bestand, dus `spec-compliance` ↔ "Compliance en
  auditeerbaarheid" vraagt geen normalisatie, geen stopwoordregel, geen aliastabel.
- **`CHANGES.md` krimpt van 27 naar 12 entries.** De scripts itereren `CHANGES.md`
  én `nfr/*.md`. Dat dient de groeiende leeslast directer dan het archief alleen:
  vijftien van de zevenentwintig entries verlaten het bestand dat elk project bij
  elke sessie langsloopt.
- **Retirement wordt een veld** (`status: geretireerd`) in plaats van een
  bestandsverhuizing, voor deze vijftien.

Het veld `productie-poort` draagt de tweede poort van F6: welke NFR's vóór de
eerste productie-uitrol onderbouwd moeten zijn, is hier een vastgelegd besluit in
plaats van een lijstje in een script.

**`templates/PRD.md` wordt gegenereerd** — alleen het NFR-blok, uit `kop` +
`Invulhulp`, met het `id` als HTML-commentaar erin. `check` faalt als het
ingecheckte blok niet overeenkomt met wat de generator produceert. Dat de PRD een
build-artefact wordt, is de prijs; hij is het waard omdat de generator meteen ook
het anker plaatst waarop F11 leunt.

**Alleen de vijftien NFR's verhuizen.** De twaalf overige entries (`proces-*`,
`test-*`, `ci-conventie`, `deploy-guards`) hebben geen tweede consument en dus geen
duplicatieprobleem.

### F5 — Retirement met archief (`CHANGES-ARCHIEF.md`)

Voor de twaalf entries die in `CHANGES.md` blijven. Geretireerde entries verhuizen
mét ID en reden, zodat een project dat de entry ooit beantwoordde hem via `grep`
over beide bestanden terugvindt.

Tegelijk de **sectiescheidingen ontdubbelzinnigen**: `## Proces en ontwerpdiepte`
en `## Niet-functionele kenmerken (NFR's)` worden `###` of vet. Nu is een
sectiescheiding voor de parser niet te onderscheiden van een geretireerde entry.
Daarna betekent `## ` in `CHANGES.md` onvoorwaardelijk "entry", en kan de gedeelde
parser waarschuwen bij een entry zonder `Van toepassing als`.

Beide bestaande retirementvormen worden expliciet benoemd:
verwijderen-als-nooit-beantwoord versus bevriezen-als-wel-beantwoord.

### F6 — De onderbouwingsplicht wordt zichtbaar — zonder R9 te breken

`beantwoord()` in `pending-changes.sh` kijkt nu alleen *of er een rij is*, nooit
wat erin staat. Een vers geadopteerd project meldt dus niets openstaand terwijl
alle zeventien geseede rijen nog "vereist onderbouwing" dragen.

**Niet `beantwoord()` aanpassen.** Dat zou de openstaand-set veranderen en
daarmee R9 breken — de belangrijkste regressietest van de release. In plaats
daarvan een **tweede, aparte melding**:

```
17 rij(en) in WORKFLOW-ADOPTIE.md wachten nog op onderbouwing.
Volg de skill `adoption-registry`.
```

Geteld door het antwoordbestand te grepen, niet door te veranderen wat "beantwoord"
betekent. R9-neutraal per constructie.

Hierbij ook de **verouderde-adoptie-melding**: mist het project skills die in
`$CLAUDE_WORKFLOW_DIR/skills` wél bestaan, dan meldt de hook dat `adopt.sh`
opnieuw moet draaien. Zonder dat landt deze release en houden drie van de vier
projecten stilzwijgend de oude wereld.

**Besloten: gefaseerd onderbouwen, geborgd met drie poorten.** Zeventien rijen
in één keer wegwerken is onrealistisch huiswerk; het signaal alleen wordt dan
chronische ruis. Daarom onderbouwen bij eerste aanraking, met voor elke rij een
uiterste moment:

1. **Per PR** — raakt een PR een onderwerp waarvan de rij nog "vereist
   onderbouwing" zegt, dan is dat een reviewbevinding in `pre-merge-review` en
   wordt de rij vóór de merge beantwoord (F11).
2. **Vóór de eerste productie-deploy** — de deploy-guards eisen dat geen rij met
   `productie-poort: ja` nog "vereist onderbouwing" zegt (F4).
3. **Elke sessie** — het signaal hierboven blijft; gefaseerd betekent niet
   onzichtbaar.

Aangeraakt → beantwoord bij die PR; nooit aangeraakt maar kritiek → uiterlijk bij
de eerste productie-uitrol; de rest → zichtbaar tot je eraan toekomt.

### F7 — Git-guardrails als `PreToolUse`-hook

Blokkeert `reset --hard`, `clean -f[d]`, `branch -D`, `checkout .`/`restore .`,
`commit` **op `main`** en `push` **naar `main`**.

**`commit` op `main` blokkeren is een bewuste uitbreiding**, op verzoek van Ties
toegevoegd nadat bleek dat alleen de push blokkeren een slecht moment oplevert:
je werkt een hele sessie door, commit alles op `main`, en loopt pas aan het eind
tegen de muur. Erger nog — de `SessionEnd`-hook slaat zijn push over op `main`,
dus dat werk bereikt de remote helemaal niet meer, terwijl je vóór deze guard
nog handmatig had kunnen pushen. De blokkade zet dat moment naar voren; F18
sluit de keerzijde ervan.

De melding moet daarom de uitweg noemen (`git checkout -b`) én dat de
wijzigingen meegaan. Zonder dat blijft het werk *ongecommit*, en dat is
onveiliger dan de lokale commit die je net tegenhield. Uitzondering: een repo
zonder commits — de allereerste commit van een nieuw project staat per definitie
op `main`.

Dat laatste is **tweeledig**: expliciete refspecs die `main` raken
(`git push origin main`, `git push origin HEAD:main` — vanaf welke branch dan
ook) én de toestandsafhankelijke kale push (`git push origin HEAD` terwijl `main`
is uitgecheckt, dus `git rev-parse --abbrev-ref HEAD` raadplegen). Alleen op de
huidige branch keyen mist de eerste categorie. `mattpocock`'s versie blokkeert
*alle* `git push` — hier overnemen zou de verplichte feature-branch-pushes én de
bestaande `SessionEnd`-hook breken.

Wat deze hook per definitie *niet* ziet, is alles buiten de agentic loop: een
commando dat Ties zelf in zijn terminal typt komt er nooit langs. Dat gat is
geen detail van de implementatie maar een eigenschap van `PreToolUse`, en het
wordt apart geadresseerd in F17.

JSON-parsing: `jq` als aanwezig (staat in `/usr/bin` op macOS 26), anders
`python3`; ontbreken beide, dan luid waarschuwen en toestaan.

**Geen `sed`-vangnet.** Een eerdere versie noemde die als derde laag. Bij nader
inzien is dat schadelijker dan nuttig: een `sed`-benadering van JSON leest
strings met escapes verkeerd, en een guard die het commando verkeerd leest kan
zowel iets onschuldigs blokkeren als iets destructiefs doorlaten — precies de
twee uitkomsten die hij moet voorkomen. Niets kunnen lezen en dat luid melden
is eerlijker dan een gok.

De hookregel moet `if [ -x … ]; then exec …; fi; exit 0` zijn, **niet**
`[ -x … ] && … || exit 0` — die tweede vorm slikt exit 2 in en zet de guard stil
uit terwijl hij geïnstalleerd lijkt.

### F8 — Merge-guard: geen merge zonder review-bewijs én groene CI

Dezelfde `PreToolUse`-mechaniek, tweede case: `gh pr merge` wordt geblokkeerd als
de PR geen machineherkenbare review-marker draagt (zie F11). De merge is hét
choke point van de workflow, en de nulmeting (0 reviews op 27 PR's) bewijst dat
een verplichting zonder slot daar niet werkt — waarschuwen in plaats van
blokkeren zou dat faalpatroon herhalen.

**Uitgebreid met een CI-controle (issue #81).** Zes CI-runs op rij faalden
onopgemerkt na PR #76 — PR #76, #78 en (initieel) #80 zijn allemaal rood
gemerged, omdat niets in de merge-flow ernaar keek: dit repo heeft geen branch
protection (privé, geen betaald plan) en `gh pr merge` waarschuwt zelf niet bij
falende checks. Dezelfde poort die de review-marker controleert, controleert nu
ook `gh pr checks` op de PR: elke check die niet `pass` of `skipping` is
(faalt, of loopt nog) blokkeert de merge, met de naam van die check in de
melding.

Randvoorwaarden, voor beide controles: **faal-open** zonder `gh` of netwerk
(luid melden, toestaan) — inclusief wanneer een project geen CI heeft
geadopteerd (geen checks gerapporteerd is geen rode vlag, CI is optioneel, zie
F6); een onderbouwde `nee`-rij voor `kwaliteitsreview-voor-merge` in
`WORKFLOW-ADOPTIE.md` schakelt beide controles voor dat project uit (lokale
grep, geen netwerk); en er is een expliciete overrule die luid meldt wat wordt
overgeslagen — dezelfde filosofie als bij de deploy-guards.

### F9 — Skills-infrastructuur in `adopt.sh`

**Per-skill symlinks in een echte `.claude/skills/`-map**, plus het opruimen van
verweesde workflow-eigen symlinks.

Eén map-symlink (`.claude/skills -> $CLAUDE_WORKFLOW_DIR/skills`) is verleidelijk —
één regel, en nieuwe skills liften mee op een `git pull`. Toch afgewezen: het maakt
de **hele skills-namespace van het project eigendom van `claude-workflow`**.
`tennis-admin` kan dan nooit een eigen skill hebben zonder te de-adopteren. Dat is
precies de koppeling die dit repo bestaat om te vermijden. Bovendien is alleen de
per-skill-vorm gedocumenteerd.

Het opruimen is het deel dat telt: skills worden hernoemd, en een verweesde
`.claude/skills/oude-naam/` is niet inert — Claude Code meldt er elke sessie een
laadfout op, in vier projecten tegelijk. Regel: verwijder alleen symlinks die naar
`$CLAUDE_WORKFLOW_DIR` wijzen én niet meer bestaan. Echte mappen (een projecteigen
skill) nooit aanraken.

`.gitignore` krijgt een **beheerd blok** in plaats van losse regels: de lijst gaat
churnen en de huidige append-only functie kan niets verwijderen. Migratie moet de
twee bestaande losse regels weghalen, anders staan ze dubbel.

### F10 — Het skill-register

Namen in het Engels, body en beschrijving in het Nederlands. De naam is een
identifier die in dezelfde platte namespace staat als `code-review` en
`security-review`; `kwaliteitsreview-voor-merge` daarnaast leest als een ongelukje.
Alles wat Ties leest en onderhoudt blijft Nederlands.

| Skill | Aanroep | Wat erin gaat |
|---|---|---|
| `pre-merge-review` | model + user | "Kwaliteitsreview vóór de merge" (40 regels) + scoping + de PR-poort uit F13 |
| `deploy-guards` | model | Deploy-voorwaarden per omgeving (~52 regels) + de productie-poort uit F6 |
| `check-convention` | model | `check`/`deploy`-naamconventie + CI (~22 regels) |
| `adoption-registry` | model | Adoptieregistratie (35) + onderbouwingsplicht (15) + protocol uit `USER-CLAUDE.md` |
| `write-spec` | model + user | Specificeren van werk + `Dekt:`-conventie + `CONTEXT.md`-glossarium |
| `refactoring-triggers` | model | Complexiteit/debt/refactoring (32 regels) |
| `tdd-seams` | model + user | Nieuw: seams, rood-vóór-groen, drie anti-patterns |
| `diagnose-bug` | model | Nieuw: reproductie → hypotheses → regressietest vóór fix |
| `adopt-workflow` | **user-level** | Adoptievraag + nieuw project opzetten |

**Drie keuzes die uitleg verdienen:**

*De onderbouwingsplicht gaat naar `adoption-registry`, niet `write-spec`.* Hij
staat nu onder "Specificeren van werk", maar gáát over het beantwoorden van
`WORKFLOW-ADOPTIE.md`-rijen — hetzelfde onderwerp als de registratiesectie, die
hem al samengevat herhaalt, en `USER-CLAUDE.md` een derde keer. Eén skill vouwt
drie kopieën samen.

*`adopt-workflow` is de enige user-level skill.* `USER-CLAUDE.md` hangt op
`~/.claude/CLAUDE.md` en laadt in **niet-geadopteerde** projecten, waar
`.claude/skills/` niet bestaat. Elke skill waarnaar `USER-CLAUDE.md` verwijst moet
dus in `~/.claude/skills/` staan, geïnstalleerd door `adopt.sh --user`. Die
asymmetrie is makkelijk fout te doen en levert een dode verwijzing op in precies de
projecten waar je het niet merkt.

*`CONTEXT.md` krijgt géén eigen skill.* Het is een sjabloon plus een conventie:
`templates/CONTEXT.md`, een `CHANGES.md`-entry, en twee zinnen in `write-spec`.
Negen skills is al de grens van wat samenhangend blijft.

### F11 — `pre-merge-review` als uitvoerbare skill

De sterkste post. `WORKFLOW.md` *vraagt in proza* om een review "met verse context
en op een ander model". Frontmatter drukt dat letterlijk uit: `context: fork` geeft
de verse, geïsoleerde context, `model:` pint een ander/zwaarder model,
`allowed-tools` houdt hem read-only.

De skill leest `WORKFLOW-ADOPTIE.md` → `ja`-beantwoorde `spec-*` → het anker in de
project-PRD → de reviewscope. Het lezen van de diff wordt gedelegeerd aan de
bestaande `code-review`-skill; deze skill bezit de *scoping*, de context/model-eis,
en de "bevindingen in de PR, dan opgelost of onder Technical debt"-stap.

Twee toevoegingen uit de merge-guard en het onderbouwingsbesluit: de skill plaatst
een **machineherkenbare marker** in zijn bevindingen-comment (waar F8 op keyt), en
hij behandelt een geraakt onderwerp waarvan de `WORKFLOW-ADOPTIE.md`-rij nog
"vereist onderbouwing" zegt als reviewbevinding — die rij wordt vóór de merge
beantwoord (de eerste poort van F6).

### F12 — De kern: `WORKFLOW.md` + Wegwijzer

`WORKFLOW.md` krimpt van 250 naar ~85 regels en houdt wat élke sessie nodig heeft:
branchstrategie, sessiestart, tijdens het werk, de vierstapsvolgorde van Afronden,
en het slot.

Nieuw en dragend: een **Wegwijzer** — een tabel situatie → skill. Dat is het
R7-bewijsstuk ("direct in het bestand, óf via een expliciete, direct volgbare
verwijzing"). Hij moet élk verplaatst onderwerp noemen; R7's vijf termen
(branching, kwaliteitsreview, onderbouwingsplicht, deploy-guards,
adoptieregistratie) moeten elk in één sprong oplossen. Twee ervan landen in
dezelfde skill — dan twee rijen, niet stilzwijgend samengevoegd.

### F13 — Traceability, herontworpen op de werkelijkheid

De oorspronkelijke opzet ging uit van `F<n>`/`S<n>` overal. De werkelijkheid:

| Project | PRD-ids | Scenario-ids | Issues gebruikt? |
|---|---|---|---|
| tennis-admin (vlaggenschip) | F1–F26 | **R(44) / A(24) / B(22) / P(6)** | 1 ooit, nog open |
| a2t-emails | F1–F8 | S1–S20 (+ `S2b`) | 6, **allemaal open** |
| tennis-registration | F1–F7 | S1–S16 | nooit |
| tennis-invoicing | **geen `F<n>`** | S1–S29, **S26/S27/S28 dubbel** | nooit |

**Besloten in W17 (#29)**, de ontwerpreview met Ties die de blokkade "eerst één
work item end-to-end" vervangt. Alle vier de besluiten hieronder zijn bevestigd,
met één toevoeging: besluit c krijgt een expliciete beperking, zie daar. De
onderbouwing is vóór het besluit opnieuw tegen de vier projecten geverifieerd —
twee claims bleken onvolledig en staan hieronder gecorrigeerd.

Vier ontwerpbesluiten die het ontwerp redden van deze werkelijkheid. De letters
**a** tot en met **d** hieronder zijn prozalabels, geen ID's: alleen `F13` is een
functionaliteitsitem. De collector uit besluit c verzamelt daarom uitsluitend
ID-tokens uit **koppen** — schrijfwijzen als "F13a" in lopende tekst, en ID's van
andere projecten zoals de `F1–F26` in de tabel hierboven, tellen niet mee.

**a. `AC<n>` in `work-item.md`.** Dat sjabloon nummert zijn eigen
acceptatiecriteria `### S1:` — dezelfde namespace als `TEST-SCENARIOS.md`, dus elke
`grep` op `S<n>` raakt gegarandeerd het issue zelf. Niet `A<n>`, en die botsing is
scherper dan hij op het eerste gezicht lijkt: `templates/ARCHITECTUUR.md` gebruikt
`A1` voor architectuureisen, en tennis-admin heeft 24 `A<n>`-scenario's. Zou
tennis-admin dat sjabloon scaffolden, dan betekent `A1` twee dingen binnen één
project — geen botsing tussen projecten, maar binnen één. Geverifieerd: `AC` komt
in geen van de vier projecten voor.

**b. Eén veldnaam, `**Dekt:**`**, in beide richtingen; het prefix van het token
zegt welke schakel het is. Strikt: regelbegin, komma-gescheiden tokens die matchen
op `^[A-Z]{1,2}[0-9]+[a-z]?$`. Beide kwantoren komen uit de werkelijkheid, niet uit
smaak. De `[a-z]?` is er om `a2t-emails`' `S2b`; de `{1,2}` om tennis-admins
`OP<n>` — dat project gebruikt `OP` voor open punten in zowel `PRD.md` als
`ARCHITECTUUR.md`, en `O<n>` voor afgewogen architectuuropties. Een grammatica die
één van beide afwijst is op dag één onbruikbaar in een van de vier projecten.
Alleen het veld telt; dat voorkomt vals-positieven per constructie.

**c. Geen `F`/`S` hardcoderen — link-integriteit controleren.** Verzamel de
ID-tokens uit de koppen van `PRD.md` en `TEST-SCENARIOS.md`, en controleer dat elk
`Dekt:`-token in de andere set oplost. Dan werkt tennis-admins `R/A/B/P`
ongewijzigd (de B-serie werd in een eerdere inventarisatie over het hoofd gezien —
precies het soort fout waar een hardcoded prefixlijst op stukloopt), worden
tennis-invoicings dubbele ID's een **gemelde fout** (een echte latente bug die het
oorspronkelijke ontwerp niet zag), en levert een PRD zonder `F<n>` een
**waarschuwing** op, geen harde fout. Een check die op dag één faalt in een van de
vier projecten, staat op dag twee uit.

*Wat deze keuze kost*: zie "Bekende beperkingen" hieronder (het OP5-geval).

De reikwijdte is wel begrensd door besluit c zelf: de collector leest alleen
koppen uit `PRD.md` en `TEST-SCENARIOS.md`. Tennis-admins `O1`–`O5` — afgewogen
architectuuropties waarvan er vier verworpen zijn — staan uitsluitend in
`ARCHITECTUUR.md` en worden dus niet verzameld. `Dekt: O2` lost daarom júist niet
op en wórdt gemeld. Alleen wat in de twee gescande bestanden staat, kan dit
probleem geven.

Dat is bewust geaccepteerd in W17. Een verwijzing naar een verkeerd maar bestaand
doel is een documentatiefout die een mens in de review ziet; een hardcoded
`F`/`S`-lijst maakt de controle onbruikbaar in twee van de vier projecten. Drie
alternatieven zijn afgewogen en afgevallen, elk op dezelfde grond — ze vragen
per-projectconfiguratie die stilzwijgend veroudert:

- **Uitsluitlijst per prefix.** Veroudert zodra een project een nieuw prefix gaat
  gebruiken.
- **Filteren op bestand.** Sluit `ARCHITECTUUR.md` uit, maar dat doet besluit c al;
  het `OP<n>`-geval zit in de PRD zelf en blijft staan.
- **Filteren op sectie binnen de PRD**, bijvoorbeeld alleen koppen onder
  `## Functionaliteit`. Aantrekkelijk, en daarom nagerekend: van de vier projecten
  gebruikt alleen tennis-admin een sectie `## Open punten`; de andere drie hebben
  helemaal geen open-puntensectie, en `templates/PRD.md` evenmin — dit repo zelf
  gebruikt `## Open vragen`. De sectienamen lopen dus al uiteen vóór er iets op
  gebouwd is, en filteren daarop verplaatst de veroudering van prefixen naar
  kopteksten in plaats van hem weg te nemen.

Zie *Bekende beperkingen*.

**d. Splitsen op netwerkafhankelijkheid.** Schakel 1 (functionaliteit → scenario)
is offline en gaat in `templates/check-traceability.sh`, gescaffold zoals `ci.yml`,
aangeroepen vanuit het eigen `check` van het project. Schakels 2 en 3 (scenario →
issue → PR) zijn **geen audit-script**, maar een **poort in `pre-merge-review`**:
die skill draait precies op het moment vóór de merge, heeft al `gh` en netwerk, en
schrijft zijn bevindingen al in de PR. "Verwijst *deze* PR naar een issue" is één
`gh pr view --json closingIssuesReferences`.

Schakel 3 krijgt daarnaast een **hard slot in CI**: een skill blijft vrijwillig, en
de nulmeting bewijst wat daarvan komt. Op GitHub Actions is `GITHUB_TOKEN` gratis
beschikbaar — het gh-auth-argument dat schakel 2/3 uit het lokale `check` houdt,
geldt daar niet — en de check beoordeelt alleen de huidige PR, dus hij is even
retrofit-vrij als de poort.

Daarmee verdwijnt het retrofitprobleem: een audit over 27 issueloze PR's zou eeuwig
blijven falen; een poort geldt vanaf de volgende merge.

### F14 — Blocking-edges in de issue-templates

`**Blocked by:** #` / `**Blocks:** #` in `work-item.md` en `epic.md`. Bewust het
platte veld, want `gh issue view` toont `blocked-by`/`blocking` al; native
sub-issues zouden de conventie aan GitHub Projects binden.

### F15 — Releasemechaniek

Dit repo heeft geen tags, releases, `CHANGELOG.md` of versieveld. Deze release
voegt `CHANGELOG.md` toe, tagt het mergepunt, en herstelt de stilgevallen
`**PR:**`-verwijzing — die geldt nu in 3 van 27 entries, want de conventie viel
direct na invoering stil. Plus een test die dat permanent afdwingt.

Geadopteerde projecten volgen `main` live via symlink, dus een tag is een menselijk
referentiepunt, geen pinbare versie. *(Herzien voor consumenten buiten Ties'
eigen gebruik: W37 (#79) bouwt op dit tagmechanisme een pinbaar
consumentenpad, zie "Besloten in W29 (#53)", besluit 5. Dit — main live via
symlink volgen — blijft Ties' eigen model.)* De eerste CHANGELOG-entry documenteert de
vereiste actie: **`adopt.sh` opnieuw draaien in elk project op elke machine, én
`adopt.sh --user` één keer per machine** — zonder dat laatste ontbreekt de
user-level skill en verwijst de bijgewerkte `USER-CLAUDE.md` naar iets dat er niet
is (dezelfde asymmetrie als onder F10 beschreven).

### F16 — Achterstallig onderhoud

- `a2t-emails`: geen `WORKFLOW-ADOPTIE.md` (aanvullen, niet vers seeden met de
  datum van vandaag — dat zou vervalsen wanneer een keuze gemaakt is).
- `a2t-emails`: ongetrackte `AGENTS.md`, een 15 KB **kopie** van `WORKFLOW.md` —
  een tweede, driftende bron van waarheid die de nieuwe slanke kern actief gaat
  tegenspreken. Verwijderen.
- `README.md`: "**vijf** niet-functionele vragen" — het zijn er vijftien sinds
  `4821bac`.
- `tennis-registration`: achtergebleven branch `chore/sessionend-push-hook`.
- Alle vier: ankers in de project-PRD's bijwerken (companion, geen blocker —
  `pre-merge-review` valt terug op kopnamen en méldt dat de ankers ontbreken).

### F17 — Dekking buiten de agentic loop

De guard uit F7 is een `PreToolUse`-hook, en die ziet uitsluitend wat Claude zelf
uitvoert. De documentatie beschrijft het event als "before a tool call executes"
en kent geen ander aangrijpingspunt; commando's die Ties zelf in zijn terminal
typt zijn geen tool-aanroep en komen er dus nooit langs. Dat is een gevolgtrekking
uit de beschreven scope, niet een waarschuwing die de documentatie zelf geeft —
maar hij is dwingend: er ís geen mechanisme waarlangs die commando's de hook
zouden bereiken. Diezelfde `git reset --hard` in een eigen
terminalvenster, in een IDE, of op een tweede machine zonder `adopt.sh` gaat
onverkort door.

Serverzijdige branch protection zou de juiste plek zijn, maar die deur is dicht:
GitHub antwoordt op een private repo letterlijk *"Upgrade to GitHub Pro or make
this repository public"*. Zolang dat zo is, moet de dekking uit drie
lokaal-en-CI-gebaseerde lagen komen:

- **`templates/ci.yml` valideert pull requests en `main`** (W24). Het sjabloon
  gebruikte `on: push: branches-ignore: [main]` en valideerde dus *noch* PR's
  *noch* `main` — net als de workflow van dit repo zelf, die dezelfde vorm had. Elk nieuw project start daarmee zwakker dan `tennis-admin`, dat
  een met de hand geschreven `ci.yml` heeft met `on: pull_request` én
  `push: branches: [main]`. Het `pull_request`-event is bovendien nodig om een
  controle als *required check* te kunnen instellen — de vorm die een merge
  daadwerkelijk kan tegenhouden. Het sjabloon repareren helpt alleen nieuwe
  projecten, dus hoort er een `CHANGES.md`-entry bij (`ci-op-pr-en-main`,
  `heeft-package-json`): bestaande projecten houden anders hun zwakkere CI
  zonder dat iemand ernaar vraagt. Die entry staat los van `ci-conventie` —
  dát antwoord gaat over wát de workflow doet, dit over wannéér hij draait.
- **Git-hooks in het project** (W26). Een `pre-commit`- en `pre-push`-hook dekt
  élk gereedschap op die machine. Ze hergebruiken de beslislogica uit
  `hooks/git-guardrails`. Let op wát er te hergebruiken valt: een native
  `pre-commit` krijgt geen commandostring, dus de quote-bewuste tokenisatie uit
  `lees-commando.py` is per definitie `PreToolUse`-specifiek. Wat gedeeld kan
  worden zijn de *regels* — welke branch beschermd is, wat de melding zegt, welke
  uitweg hij noemt. Dat is smaller dan "hergebruik het script", en W26 moet dat
  onderscheid expliciet maken in plaats van een simpele hergebruikoefening aan te
  nemen. Beperking:
  git-hooks zijn machine-lokaal en reizen niet mee met een clone, dus een nieuwe
  machine heeft ze pas na `adopt.sh`. Dat is dezelfde beperking als bij de
  bestaande hooks, en de verouderde-adoptie-melding uit F6 maakt hem zichtbaar.
- **CI detecteert commits op `main` die niet uit een PR komen** (W27). Dit is
  detectie in plaats van preventie — het commando is dan al uitgevoerd — maar
  het is het enige mechanisme dat op elke machine en met elk gereedschap werkt.
  De controle beoordeelt alleen de binnenkomende push, niet de historie: een
  retrofit die op dag één rood staat leert je de melding te negeren.

De drie lagen zijn bewust niet uitwisselbaar. W24 en W26 voorkomen, W27 vangt op
wat er doorheen glipt.

### F18 — Werk veiligstellen zonder op het sessie-einde te leunen

De `SessionEnd`-hook is op dit moment de enige automatische push. Al het werk
sinds de vorige sessie hangt daarvan af. De documentatie van Claude Code zegt
alleen dat `SessionEnd` afgaat "when a session terminates", met een gedeeld
tijdsbudget van 1,5 seconde, en noemt als redenen `clear`, `resume`, `logout`,
`prompt_input_exit` en `other`. Over een crash, een gesloten terminalvenster of
stroomuitval staat er **niets** — er is dus geen toezegging dat de hook dan
draait, en het budget maakt bovendien niet uit hoeveel er nog te pushen valt.
Die stilte is geen bewijs dat het misgaat, maar wel reden om er niet het enige
vangnet van te maken.

De commit-blokkade uit F7 verscherpt dat zelfs: blokkeer je de commit op `main`
en wordt die melding genegeerd, dan blijft het werk *ongecommit* en heeft
`SessionEnd` niets te pushen. Twee aanvullingen sluiten dat gat aan beide
kanten:

- **Sessiestart meldt dat `main` is uitgecheckt** (W23). De commit-blokkade
  grijpt pas wanneer er al werk is; een melding bij sessiestart grijpt ervóór, op
  het moment dat vertakken nog gratis is. De guard blokkeert namelijk de commit,
  maar niet het bewerken van bestanden — Edit, Write, `git add` en `git stash`
  gaan gewoon door. Puur informatief: de hook muteert niets en blokkeert niets,
  en houdt zich aan dezelfde eis als het onderbouwingssignaal (exit 0, niets op
  stderr).
- **Pushen zodra er gecommit is** (W25). Een `PostToolUse`-hook pusht de huidige
  branch na een geslaagde `git commit`. Het is dezelfde handeling die
  `SessionEnd` al doet, alleen eerder en vaker — geen nieuwe branchnamen, geen
  mutatie die niemand vroeg. `WORKFLOW.md` schrijft "push regelmatig" al voor;
  dit maakt dat mechanisch in plaats van iets dat onthouden moet worden. Zonder
  netwerk of `origin` meldt hij het en houdt hij niets op.

---

## Niet-functionele kenmerken

### Security

Relevant, beperkt. De guardrails-hook (F7) is zelf een beveiligingsmaatregel.
`check-traceability.sh` parseert issue- en PR-tekst — invoer die niet volledig
onder eigen beheer staat — dus geen `eval`, net zoals de predicaten bewust een
`case` zijn. Geen secrets in dit repo.

### Data-integriteit

Sterk relevant. `WORKFLOW-ADOPTIE.md` is de duurzame vastlegging van besluiten en
mag nooit overschreven worden. F16 raakt dit direct: `a2t-emails` aanvullen mag
geen verse seed met de datum van vandaag worden. F6 is expliciet zo ontworpen dat
het de betekenis van "beantwoord" *niet* verandert. `adopt.sh` blijft idempotent —
"twee keer draaien geeft een identieke boom" wordt een test.

### Failure modes

Sterk relevant. Harde eis: een hook blokkeert nooit een sessie. De nieuwe
`PreToolUse`-hooks (F7, F8) zijn de uitzondering — die hóren te blokkeren, maar
moeten falen naar *toestaan* als ze zelf stuk zijn (en F8 ook zonder `gh` of
netwerk), en de `if/exec/fi`-vorm is daarvoor doorslaggevend.
`check-traceability.sh` waarschuwt en gaat door zonder `gh` of netwerk, conform de
bestaande regel bij de deploy-guards.

### Observability

Relevant. Stille degradatie is de belangrijkste faalmodus: de hookketen eindigt op
`|| true`, dus een kapotte symlink levert stilte op. `check` (F1) en de
verouderde-adoptie-melding (F6) zijn het tegengif — wat CI en de hook kunnen zien,
verwatert niet.

### Performance en schaal

Nauwelijks relevant, wel benoemd. `pending-changes.sh` herleest zijn bron één keer
per openstaand ID (O(n·m)); bij 27 entries verwaarloosbaar. F4 splitst de bron in
tweeën, dus de gedeelde parser mag daar niet trager van worden.

### Deployability

Sterk relevant, en ongebruikelijk van vorm. "Uitrollen" is: mergen naar `main`.
Consumenten volgen `main` live via symlink, dus elke merge is onmiddellijk actief
in vier projecten, zonder opt-in en zonder terugrolpad anders dan een revert. Er is
geen staging tussen merge en gebruik — dat verhoogt de eis aan F1. Wat `adopt.sh`
installeert loopt juist achter tot iemand hem opnieuw draait; F6 maakt dat
zelfmeldend.

### Privacy

N.v.t., onderbouwd. Geen persoonsgegevens buiten de git-auteurinformatie die er al
staat. Adoptietabellen bevatten besluiten.

### Compliance en auditeerbaarheid

N.v.t. als wettelijke eis; wél als zelfopgelegde. De adoptieregistratie bestáát om
aantoonbaar te maken welk project welke afspraak toepast en waarom. F4 en F5 mogen
die aantoonbaarheid niet breken: een verhuisde of gearchiveerde entry moet vindbaar
blijven vanuit een `WORKFLOW-ADOPTIE.md` die ernaar verwijst. Dat is R8, en na F4
geldt het ook voor de vijftien verhuisde NFR's.

### Backup en herstel

Relevant, laag risico. Alles van waarde staat in git. Het kwetsbare deel is wat
níét in git staat: de lokale, ongetrackte symlinks per machine. Herstellen door
`adopt.sh` opnieuw te draaien — idempotent, al gedocumenteerd als vangnet.

### Portability

Relevant, met een bewuste nieuwe binding. Tot nu toe was dit repo bash + `gh` +
markdown. Skills zijn een **Claude Code-specifiek** formaat; de frontmatter die F11
gebruikt (`context: fork`, `model:`) is niet door andere harnassen ondersteund.
Bewust aangegaan, hier vastgelegd zodat het een besluit is en geen ongeluk.
Daarbinnen nog een grens: die frontmatter is recent, en de twee machines kunnen
verschillende Claude Code-versies draaien — controleren vóór W13 erop leunt. Bash
3.2 is de tweede portabiliteitsgrens en beperkt het scriptidioom.

**Grens tussen kern en agent-gereedschap (W31, #55).** Niveau **a — alleen
benoemen**: deze tabel documenteert de grens die al impliciet bestaat, zonder
een adapterlaag of contract te bouwen (zie "Besloten in W29 (#53)", besluit 2).

| Agent-onafhankelijk | Claude Code-specifiek |
|---|---|
| Sjablonen (`PRD.md`, `TEST-SCENARIOS.md`, `ARCHITECTUUR.md`) | `settings/session-hooks.json` |
| Adoptieregistratie (`CHANGES.md`, `WORKFLOW-ADOPTIE.md`) | `hooks/` (`PreToolUse`, `SessionStart`, `SessionEnd`) |
| Het `nfr/`-register | `skills/` |
| Traceability (`Dekt:`, `AC<n>`) | `CLAUDE.md` als symlinknaam |
| Git-conventies, `check`, de testharnas | `.claude/`-mappenstructuur |

Twee dingen die geen nette laag zijn en dat ook niet kunnen worden: de
afdwinging zelf is agent-specifiek (een `PreToolUse`-hook bestaat bij de gratie
van Claude Code; een andere agent heeft een ander mechanisme of geen), en de
kern is niet gratis draagbaar (`check`, de testharnas en de scripts zijn bash
— platformafhankelijk, niet agent-afhankelijk).

`#55` specificeerde ook AC4 (een doorlopende `check`-test die de linkerkolom
tegen `.claude/`-, `SKILL.md`- en hooknaam-verwijzingen bewaakt) en AC5 (een
eenmalige meting van wat zonder `.claude/` nog werkt). Beide zijn **bewust
uitgesteld**: ze verdedigen tegen een claim die nog nergens gemaakt wordt — de
voorpagina die die claim zou kunnen maken (W35, #59) is er nog niet. Bouwen
tegen een belofte die niet bestaat is dezelfde speculatie die niveau b/c al
afwees (rule-of-three, zie hierboven). Trigger om alsnog te bouwen: zodra W35
een agent-neutraliteitsclaim naar buiten toe maakt.

### Maintainability

Sterk relevant — grotendeels waar de release over gaat. F3 haalt de parser- en
predicaatduplicatie weg, F4 de NFR-duplicatie, F5 de groeiende leeslast. Nieuwe
last die erbij komt: een `skills/`-boom, een `nfr/`-register met generator, een
testharnas en een derde script. Netto positief, niet gratis.

### Testability

Sterk relevant, en nu de grootste leemte: **nul** tests bij veertien
gespecificeerde scenario's. Ontwerpeis die eruit volgt: beide scripts moeten hun
invoer injecteerbaar maken. `pending-changes.sh` is er bijna; `adopt.sh` haalt
alles uit globals en vereist `.git`, dus fixtures moeten `git init`'d zijn.

### Usability

Relevant. De gebruiker is Ties plus de agent. De concrete faalmodus staat al in de
PR #6-review: zeventien rijen huiswerk per nieuw project, in één klap generiek
beantwoord. F6 maakt dat zichtbaar én besluit het: gefaseerd onderbouwen, geborgd
met drie poorten.

### Kostenbeheersing

Relevant, in tokens. `WORKFLOW.md` laadt volledig in élke sessie van élk project.
Circa 45% is voorwaardelijk relevant. Skillbeschrijvingen kosten één keer per
sessie een paar honderd tokens; de body pas bij aanroep. Meetpunt: regels in
`CLAUDE.md` vóór/ná, te vermelden in de PR van F12.

### Documentatie

Relevant. `README.md` is aantoonbaar verouderd (F16) en heeft rijen nodig voor
`skills/`, `hooks/`, `lib/`, `nfr/`, `test/`, `check` en `CHANGES-ARCHIEF.md`, plus
uitleg waarom skills gesymlinkt maar sjablonen gekopieerd worden. Elke skill draagt
zijn eigen uitleg; de kern verwijst er expliciet naar, zodat R7 blijft gelden.

---

## Volgorde en werkitems

De werkitem-ID's hieronder (`W<n>`) zijn de schakel tussen dit document en de
GitHub-issues: elk issue draagt zijn `W`-id in de titel en verwijst met `**Dekt:**`
naar de functionaliteit en scenario's die het realiseert.

**Rood vóór groen geldt voor elk werkitem**: het scenario dat het werkitem dekt
wordt eerst als test toegevoegd en aantoonbaar *rood* gezien, daarna pas volgt de
implementatie. W1–W3 zijn daar de bootstrap van — zonder harnas en nulmeting is
"rood" niet vast te stellen.

### Fase 0 — Fundament (geen gedragsverandering)

| # | Werkitem | Blokkeert |
|---|---|---|
| **W1** | Testharnas + `./check` + CI (F1) | alles |
| **W2** | Nulmeting-fixtures voor alle vier de projecten (F2) | W3 |
| **W3** | R1–R4, R6, R9 als tests tegen de **huidige** `main` | W4–W6 |
| W16 | Blocking-edges in issue-templates (F14) | W17 |
| W12b | Feitelijke correcties in `README.md`/`WORKFLOW.md` (F16, deels) | — |

W3 is de kern van de mitigatie: groen op ongewijzigde `main`, vóór er iets
verandert. Alle vier de bronnen staan lokaal, dus de nulmeting kan direct
ingevroren worden.

### Fase 1 — Refactors, aantoonbaar gedragsbehoudend

| # | Werkitem | Hangt af van |
|---|---|---|
| W4 | `lib/changes.sh`: gedeelde parser + predicaten (F3) | W3 |
| W5 | `nfr/`-register + generator + consistentiecheck (F4) | W1, W4 |
| W6 | `CHANGES-ARCHIEF.md` + sectiescheidingen ontdubbelzinnigen (F5) | W3, W4 |
| W7 | Onderbouwingssignaal + verouderde-adoptie-melding (F6) | W4 |
| W10 | Git-guardrails hook (F7) | W1 |
| W23 | Sessiestart meldt dat `main` is uitgecheckt (F18) | W1 |
| W24 | `templates/ci.yml` valideert PR's en `main` (F17) | W1 |

W4 vóór alles wat een derde script toevoegt, anders verdrievoudig je de duplicatie
in plaats van hem op te lossen. W5 haalt de duplicatie echt weg in plaats van hem
te overbruggen.

W10 hoort hier en niet later: de hookconfiguratie is gesymlinkt en dus live na
`git pull`, het guard-script arriveert via diezelfde pull en wordt gevonden via de
bestaande `readlink`-keten — `adopt.sh` speelt geen rol. Het is bovendien de
grootste directe veiligheidswinst van de release, dus alleen het testharnas (W1)
hoort hem te blokkeren.

### Fase 2 — De structurele wijziging (hoogste risico)

| # | Werkitem | Hangt af van |
|---|---|---|
| W8 | `adopt.sh` installeert skills + hooks, no-op als `skills/` ontbreekt (F9) | W4 |
| W9 | `WORKFLOW.md` → kern + Wegwijzer; `skills/` gevuld (F10, F12) | W3, W7, W8 |

**W8 vóór W9, niet andersom.** Landen de skills eerst, dan verwijst `WORKFLOW.md`
op elke machine die pullt naar skills die nergens geïnstalleerd zijn — R7 geschonden
in productie zolang dat venster duurt. Installer-eerst-met-no-op is strikt veiliger.
W7 vóór W9 zodat projecten zichzelf melden als verouderd.

### Fase 3 — Skills en guards

| # | Werkitem | Hangt af van |
|---|---|---|
| W13 | `pre-merge-review` met echte scoping (F11) | W5, W9 |
| W10b | Merge-guard op `gh pr merge` (F8) | W10, W13 |
| W14 | `tdd-seams` + `CHANGES.md`-entry (F10) | W9 |
| W15 | `diagnose-bug` + `CHANGES.md`-entry (F10) | W9 |
| W16b | `templates/CONTEXT.md` + entry (F10) | W9 |
| W25 | Pushen zodra er gecommit is (F18) | W10 |
| W26 | Git-hooks in het project, ook buiten Claude om (F17) | W8, W10 |

W14–W16b voegen elk een `CHANGES.md`-entry toe, dus elk laat alle vier de
projecten een nieuwe vraag stellen. Dicht bij elkaar landen, zodat die vragen in
één batch komen in plaats van over vier sessies te druppelen.

### Fase 4 — Traceability

| # | Werkitem | Hangt af van |
|---|---|---|
| **W17** | **Ontwerpreview mét Ties — geen code** | W16 |
| W18 | `Dekt:` + `AC<n>` in de sjablonen (F13, besluit a en b) | W17 |
| W19 | `templates/check-traceability.sh` offline + entry (F13, besluit c en d) | W18, W4 |
| W19b | CI-check "PR verwijst naar issue" in de PR-workflow (F13, besluit d) | W18 |
| W20 | PR-poort in `pre-merge-review` (F13, besluit d) | W13, W19 |
| W27 | CI detecteert commits op `main` buiten een PR om (F17) | W24 |

W17 is de afgesproken mitigatie voor het overrulen van de blokkade en moet een
zichtbaar item zijn met eigen afronding. Te bespreken: de `AC<n>`-hernoeming, één
`Dekt:` voor beide richtingen, de tokengrammatica inclusief `S2b`,
prefix-agnostische integriteit in plaats van verplichte `F`/`S`, en het verplaatsen
van schakel 2 en 3 naar `pre-merge-review` plus CI.

### Fase 5 — Release

| # | Werkitem | Hangt af van |
|---|---|---|
| W21 | `**PR:**`-linkbacks herstellen + test die het afdwingt (F15) | W6 |
| W22 | `CHANGELOG.md` + tag + `README.md` (F15, F16) | alles |

**Eigen verificatieronde verdienen:** W2 (onherhaalbaar als de nulmeting fout
wordt vastgelegd), W8 (schrijft in andermans repo's, migreert een *getrackte*
`.gitignore`), W9 (betekenisverlies dat geen `grep` ziet), W10 en W10b (een vals
positief blokkeert werk in elk project, en bereikt ze zónder her-adoptie omdat de
hookconfiguratie gesymlinkt is), en W26 (schrijft git-hooks in andermans repo's,
en een hook die te streng is blokkeert daar élk commando, niet alleen dat van
Claude).

### Uitbreiding na het doorlichten van de dekking

W23–W27 stonden niet in de oorspronkelijke opzet. Ze komen voort uit de vraag wat
de guard uit W10 nu precies dekt, gesteld nadat die af was. Het antwoord bleek
smaller dan de stelling die eromheen was gegroeid: de guard dekt wat Claude
uitvoert, niet wat er in een eigen terminal, een IDE of op een tweede machine
gebeurt (F17), en het veiligstellen van werk hangt aan een `SessionEnd`-hook
waarvoor geen garantie bestaat (F18).

Ze zijn ingevoegd op de plek waar hun afhankelijkheden ze toelaten, niet
achteraan: W23 en W24 hangen alleen van het testharnas af — W24 inhoudelijk van
niets, maar rood vóór groen geldt ook voor hem, dus W1 blijft de voorwaarde. Beide
horen daarmee in Fase 1. W25 en W26 hangen aan de guard zelf (en W26 daarnaast aan
`adopt.sh`), dus die volgen in Fase 3. W27 heeft het bijgewerkte CI-sjabloon
nodig en landt in Fase 4.

### Waarom deze volgorde afwijkt van de oorspronkelijk afgesproken

De afgesproken volgorde (a)-(b)-(c)-(d) stond op één plek: de body van #8. #7 bevat
geen letterlijst en verwijst naar "de discussie in #6" — en PR #6 heeft precies één
comment, nul reviews, nul inline-opmerkingen, en noemt geen volgorde. Het gesprek
stond in een chatsessie, niet op GitHub.

De wél opgeschreven rationales zijn smaller dan de volgorde die eruit is afgeleid.
"Refactoren tegen een ongebruikte workflow refactort tegen aannames" raakt de
skills-migratie en de veldformaten — niet het dedupliceren van een `case` of het
uitvoerbaar maken van tests. Die zijn intern en toetsbaar zonder praktijkbewijs.

---

## Niet in scope

- **De end-to-end doorloop zelf.** Blijft nodig, heeft nog steeds geen issue, epic
  of eigenaar — hij bestaat alleen als zin in twee andere issues. Aanbeveling: er
  een echt issue van maken, met `a2t-emails` PR #10 als waarschijnlijkste vehikel
  (dat heeft als enige al issues #3–#8 openstaan).
- **Retroactieve traceability** over 27 issueloze PR's.
- **De twaalf niet-NFR-entries naar `nfr/` verplaatsen** — geen tweede consument,
  dus geen duplicatieprobleem.
- **`mattpocock/skills`' grilling/to-spec-sjabloon overnemen.** De grilling-*techniek*
  als methode om NFR-secties in te vullen blijft een aparte verkenning.
- **Een pinbare versie voor consumenten.** *(Herzien: alsnog opgepakt in W37
  (#79), zie "Besloten in W29 (#53)", besluit 5 — deze uitsluiting gold voor
  epic #11, niet meer voor epic #52.)*

---

## Bekende beperkingen

- Skills geven geen handhaving; een hook kan er alleen naar verwijzen.
- De guardrails-hook is machine-lokaal: een nieuwe machine zonder `adopt.sh`-run
  heeft hem niet. Dat geldt ook voor de git-hooks uit F17 — die reizen niet mee
  met een clone.
- Serverzijdige branch protection is niet beschikbaar: GitHub vraagt daarvoor op
  een private repo om een betaald plan. W27 is daarom detectie achteraf, geen
  preventie; het commando is dan al uitgevoerd.
- Modellen delen trainingsdata, dus ook `pre-merge-review` verhoogt de bodem zonder
  blinde vlekken uit te sluiten — die kanttekening staat al in de skill `pre-merge-review`.
- Bash 3.2 beperkt het scriptidioom.
- De link-integriteitscontrole uit F13 toetst dát een `Dekt:`-verwijzing oplost,
  niet of het doel zinnig is. Een verwijzing naar een open punt dat als kop in de
  PRD staat — tennis-admins `OP5` — slaagt. Bewust geaccepteerd in W17 (#29): elk
  alternatief breekt de controle in twee van de vier projecten of vraagt
  configuratie per project die veroudert.
- Dezelfde controle gaat ervan uit dat een ID-token in hoogstens één van de twee
  gescande bestanden als kop voorkomt. Staat hetzelfde token als kop in zowel
  `PRD.md` als `TEST-SCENARIOS.md`, dan is niet meer te bepalen welke kant een
  `Dekt:`-verwijzing op wijst. Geen van de vier projecten heeft die overlap nu;
  het ontwerp beschermt er niet tegen.

---

## Technical debt

| Wat | Waarom nu acceptabel | Trigger om aan te pakken |
|---|---|---|
| Fase 4 ontworpen zonder praktijkbewijs | Bewust overruled; W17 vervangt bewijs door menselijke review | Zodra het eerste echte work item de keten doorloopt |
| `templates/PRD.md` wordt een build-artefact | Prijs voor het weghalen van de NFR-duplicatie; `check` bewaakt het | Als de generator meer kost dan hij bespaart |
| Schakel 2 (scenario → issue) blijft zonder hard slot | Poort in `pre-merge-review` dekt hem; alleen schakel 3 gaat ook in CI | Als scenario's structureel zonder issue blijven |
| Skills binden dit repo aan Claude Code | Bewust begrensd, niveau a — zie "Grens tussen kern en agent-gereedschap (W31, #55)" onder *Portability*; AC4/AC5 uit #55 zijn bewust uitgesteld tot W35 een neutraliteitsclaim maakt | Bij overstap naar een andere agent, of zodra W35 (#59) een claim maakt die AC4/AC5 dan wél nodig heeft |
| `templates/ci.yml` is npm-only ondanks "platformneutraal" | Bestond al; alle adopters zijn npm of hebben geen CI | Eerste adopter op een andere stack |
| Vier projecten hebben ~24 van 27 wijzigingen onbeantwoord | Tabellen dateren van vóór PR #6 | W7 maakt het zichtbaar; F6's drie poorten halen het gefaseerd in |
| Projecten die met het oude `templates/ci.yml` scaffoldden houden hun zwakkere CI | De entry `ci-op-pr-en-main` stelt de vraag, maar beantwoordt hem niet; tot dan blijft de zwakkere workflow staan | Zodra een project de vraag beantwoordt — de melding bij sessiestart houdt hem zichtbaar |
| Dit repo heeft zelf geen `WORKFLOW-ADOPTIE.md` | `adopt.sh` slaat zichzelf over; de conventies gelden hier per definitie | Als een conventie hier ooit *niet* zou moeten gelden |
| `CLAUDE_WORKFLOW_DIR` blijft werken als overgangsvorm naast `SPEC_DRIVEN_GUARDRAILS_DIR` (W32, #56, AC5) | Beide machines (Mac Mini, MacBook Air) migreren niet gelijktijdig; zonder fallback breekt de niet-gemigreerde machine stil. **Mac Mini: gemigreerd 2026-09-07** (repo hernoemd, lokale checkout + env var + `~/.claude/CLAUDE.md` + de drie lokaal aanwezige projecten `tennis-admin`/`tennis-invoicing`/`tennis-registration` wijzen naar `spec-driven-guardrails`; `a2t-emails` staat alleen op de MacBook Air). **MacBook Air: gemigreerd 2026-09-07** (repo hernoemd, lokale checkout + env var + `~/.claude/CLAUDE.md`; op deze machine bleken vier projecten geadopteerd: `a2t-emails`, `tennis-admin`, en genest daaronder `tennis-admin/tennis-invoicing` en `tennis-admin/tennis-registration` — alle vier wijzen nu naar `spec-driven-guardrails`. Git-remote bleef op HTTPS: deze machine had nog geen SSH-sleutel voor GitHub). | Zodra ook de MacBook Air bevestigd is gemigreerd: fallback-code in `adopt.sh` weghalen, `claude-workflow`-compatibiliteitssymlink op de Mac Mini opruimen, deze rij sluiten |

---

## Verificatie

1. **Nulmeting eerst.** W3 is groen op ongewijzigde `main` vóór W4 begint. Elke
   afwijking daarna staat expliciet toegelicht in de PR — een stille wijziging in
   de vraagset is nooit acceptabel, ook niet als "opschoning" (R9).
2. **Rood vóór groen per werkitem.** Het dekkende scenario wordt eerst toegevoegd
   en rood gezien; de PR toont beide toestanden.
3. **R1–R9, T1–T5 en S1–S63** draaien in `check`, tegen fixtures, nooit tegen de
   echte projecten.
4. **R7 mechanisch én met de hand.** De test grept `WORKFLOW.md` op vijf termen en
   controleert dat elke genoemde skill een `SKILL.md` heeft. Dat ziet geen
   betekenisverlies — dus daarnaast een sessie openen in `tennis-admin` na
   her-adoptie en elke Wegwijzer-rij daadwerkelijk volgen.
5. **Skill-discovery** aantonen in een echt geadopteerd project vóór W9–W15.
6. **`adopt.sh` twee keer draaien** geeft een identieke boom en een identieke
   `.gitignore`.
7. **Tokenmeting**: regels in `CLAUDE.md` vóór/ná, in de PR van W9.
8. **`bash -n`** op elk gewijzigd script — bestaande conventie uit alle zes PR's.
9. **Deze release past zijn eigen regel toe**: elke PR krijgt de kwaliteitsreview
   vóór de merge, mét bevindingen in de PR. Nul van de 27 PR's tot nu toe deden dat.

---

## Open vragen

1. **Wordt de end-to-end doorloop een echt issue?** De oorspronkelijke gedachte
   was hem ná Fase 3 en vóór Fase 4 te plannen, zodat praktijkbewijs W17's
   menselijke review zou vervangen. Die volgorde is achterhaald: W17 (#29) is
   afgerond en de vijf veldformaatbesluiten liggen vast. De doorloop blijft
   waardevol, maar nu als toets óf die besluiten in de praktijk houden — niet
   als vervanging van een review die al gedaan is.
2. **`kwaliteitsreview-voor-merge` is door geen enkel project beantwoord** en geen
   enkele PR had ooit een review. Moet W13 die entry meteen in alle vier de
   projecten voorleggen?
3. ~~Genereren of samenstellen?~~ Beantwoord: genereren — zie `genereer-prd-blok`
   en F4.

---

## Besloten in W29 (#53)

Ontwerpsessie met Ties, geen code (AC3 van dat werkitem) — vier beslissingen die
epic #52 sturen, elk met redenering. Vervolgitems die hierop anticipeerden zijn
bijgewerkt: W31 (#55), W32 (#56), W33 (#57), W35 (#59) en epic #52 zelf.

**Herzien na een onafhankelijke second opinion** (een vers model, zonder de
context van de ontwerpsessie zelf, gevraagd om puur de inhoud van de vier
besluiten te bekritiseren — niet de tekst). Die review vond een harde naam-
botsing en drie onderbouwingen die de juiste uitkomst hadden met een zwakke
reden. Alle vier zijn hierop aangepast; besluit 5 is nieuw en volgt uit een
gat dat de review blootlegde.

### 1. De naam: `spec-driven-guardrails`

**Herzien.** De oorspronkelijke werktitel `agentic-SDD-workflow` bleek bij
extern zoekwerk **de eigen term van GitHub's Spec Kit** te zijn voor zijn
methodiek ("Agentic SDD"). Voor de doelgroep die dit veld kent, leest die naam
als een derivaat van Spec Kit, niet als iets zelfstandigs — en het veld is
sowieso al vol vergelijkbare namen (`cc-sdd`, `agentic-sdlc-spec-kit`,
`specky`). Voor een release waarvan het hele doel deelbaarheid is, is dat geen
detail.

`spec-driven-guardrails` — het eerder overwogen en afgevallen alternatief —
botst nergens mee en legt de nadruk op wat dit project onderscheidt van een
willekeurige SDD-aanpak: **de afdwinging**, niet nóg een spec-generator. Het
vermijdt ook het acroniem dat botste met besluit 4's doelgroep. Consequent
kleine letters (geen gemengde casing) — wordt een mapnaam, een repo-URL en de
basis van een omgevingsvariabele, en gemengde casing is daar een bekende bron
van cross-platform ellende.

### 2. Provider-agnostisch: niveau a — alleen benoemen

Van de drie niveaus (a: benoemen, b: adapterlaag met één invulling, c: een
tweede invulling erbij bouwen) is gekozen voor **a**. De grens tussen
agent-onafhankelijk en Claude Code-specifiek (zie W31/#55) wordt gedocumenteerd,
niet gebouwd als contract.

**Onderbouwing herzien.** De oorspronkelijke reden ("een contract zonder
tweede invulling blijft een aanname") bewijst te veel — met die redenering is
geen enkele abstractie ooit gerechtvaardigd vóór haar tweede consument. De
werkelijke reden is een rule-of-three: er is geen tweede agent in zicht en geen
concrete vrager, dus is een contract nu speculatief. De sterkste reden stond er
al, maar op de tweede plaats: epic #52's eigen grens ("geen nieuwe
functionaliteit").

**Het risico dat wél reëel is:** na deze release presenteert het product zich
naar buiten als neutraal (nieuwe naam, voorpagina voor een niet-technische
lezer), terwijl het 100% aan Claude Code vastzit — hooks, skills,
`.claude/settings.json`. Dat is geen technische schuld maar een belofte-schuld,
die je aan precies de nieuwe lezer verkoopt. Om niveau a sterk te maken in
plaats van alleen goedkoop, krijgt W31 (#55) er twee concrete stappen bij: een
`check`-test die de grens afdwingt (niet alleen beschrijft), en een eenmalige
meting van wat er zonder Claude Code daadwerkelijk nog werkt.

De bestaande technical-debt-rij ("Skills binden dit repo aan Claude Code")
wordt door dít besluit niet gesloten — dat gebeurt pas als W31 de grenstabel
en de twee bovenstaande stappen heeft geleverd, en dan niet als "opgelost"
maar als "bewust begrensd, met een concrete trigger om verder te gaan (niveau
b of c)".

### 3. Taalscope: A + B, via een criterium — niet via een lijst

Dat dit repo zelf — documentatie, hookmeldingen, testnamen, commentaar — Engels
wordt, staat niet ter discussie; dat is W33 (#57)'s hoofdwerk. Waar dit besluit
ook echt over gaat: welke stukken van die vertaling meebewegen in de vier
Nederlandse geadopteerde projecten, waar ze niet zelf vertaald worden.

**Herzien: het criterium vervangt de opsomming.** De oorspronkelijke lijst (twee
items: entry-ID's en `**Dekt:**`/`AC<n>`) bleek bij natrekken onvolledig — de
review vond zelfstandig minstens vijf machinaal gematchte Nederlandse tokens
die er niet in stonden (de bestandsnaam `WORKFLOW-ADOPTIE.md` zelf, de
`ja`/`nee`-antwoordwaarden, de stempel "vereist onderbouwing", de
`.gitignore`-beheerde-blokmarkering, en de issue-templates die sowieso al bij
elke `adopt.sh`-run ververst worden). Een hand-onderhouden lijst heeft precies
de faalmodus die dit besluit zegt te bestrijden: iets wordt gemist en zakt
stilzwijgend weg.

Het achterliggende, wél houdbare criterium:

> **Migreert mee: elke letterlijke string die een script uit dit repo matcht in
> een bestand van een ander repo.**

Dat is laag **A** (fysiek gedeelde bestanden — symlinks: `CLAUDE.md`,
`WORKFLOW.md`, `skills/*/SKILL.md`, `session-hooks.json`) plus laag **B**
(gedeelde vocabulaire die als los token in andermans bestand staat, en die een
script van dit repo terugleest). W33 (#57) genereert de volledige inventaris
van laag B door de scripts zelf te doorzoeken op wat ze in andermans bestanden
matchen, in plaats van de lijst hier met de hand te proberen compleet te
krijgen.

Expliciet buiten scope blijft een derde laag, **C — gescaffolde documentkoppen
en scriptoutput** (bijv. `check-traceability.sh`'s eigen meldingen ín de vier
projecten) die na het scaffolden lokaal eigendom zijn geworden van die
projecten, en die geen enkel script van dit repo terugleest. Die migreert niet
mee. Nieuw gescaffolde kopieën, voor toekomstige projecten, zijn wél Engels — de
bronsjablonen in `templates/` maken deel uit van dit repo en gaan dus mee.

Overwogen en niet gekozen: backwards-compatibele parsers (bijv. `Dekt:` én
`Covers:` allebei laten werken, met een overgangswaarschuwing) in plaats van
een migratie ineens. Dat zou de cross-repo-mutatie vermijden, maar is niet
gekozen omdat het de dubbele-taal-periode zonder einddatum in stand houdt —
precies wat dit repo elders (zie R9, de nulmeting) probeert te voorkomen.

### 4. Voorpagina: welke vraag wordt eerst beantwoord — niet welke lezer is primair

**Herzien.** "De functionele lezer is primair" bleek twee gaten te hebben: de
oorspronkelijke onderbouwing ("de ontwikkelaar vindt zijn weg via
`WORKFLOW.md`") is insiderlogica — dat bestand is een agent-instructietekst,
geen installatiehandleiding, en dus geen wegwijzer voor een echte
buitenstaander. Belangrijker: de functionele lezer kan de eerste installatiestap
(clonen, omgevingsvariabele zetten, een bash-script draaien, Claude Code
hebben) sowieso niet zelf zetten — een voorpagina geoptimaliseerd voor iemand
die er niet naar kan handelen, converteert niets.

De vraag wordt daarom niet "welke lezer is primair", maar **welke vraag wordt
als eerste beantwoord**: functionele framing boven de vouw (welk probleem, voor
wie, wat kost het — business analisten, product owners en product managers
lezen dat eerst), gevolgd door een zelfstandige ontwikkelaarssectie die op
zichzelf compleet is om te installeren, zonder de rest gelezen te hoeven
hebben. W35 (#59) krijgt hiervoor een extra acceptatiecriterium: een
ontwikkelaar die het repo nooit zag, installeert het uitsluitend vanuit de
`README.md`.

### 5. Installatie- en updatemodel: getagde, pinbare release

**Nieuw, uit de second opinion.** Geen van de vier oorspronkelijke besluiten
beantwoordde wat "installeren" betekent voor iemand die niet Ties is. Het
huidige model — los checkout, een omgevingsvariabele, `adopt.sh` — is een model
voor één persoon op meerdere machines, niet voor een consument die niet main
wil volgen. Dit document sloot "een pinbare versie voor consumenten" voorheen
expliciet uit (zie "Niet in scope" hierboven, en F15's "een tag is een
menselijk referentiepunt, geen pinbare versie" — beide bijgewerkt met een
verwijzing hierheen), wat de belofte van deze release (deelbaarheid)
tegensprak.

Besloten: consumenten pinnen een **getagde release** (bouwend op W22/#35's
bestaande tag-/CHANGELOG-mechanisme uit epic #11 — F15 beschreef dat mechanisme
correct voor Ties' eigen live-via-symlink-gebruik; W37 bouwt er een tweede,
pinbaar pad bovenop, geen vervanging); het losse-checkout-plus-env-var-model
blijft daarnaast bestaan voor Ties' eigen multi-machine-gebruik. Uitgewerkt als
nieuw werkitem: **W37 (#79)**.

Aanvullend besloten: `CHANGES.md` wordt gelezen als **productdefaults**, niet
als Ties' persoonlijke voorkeurenregister. Elke entry krijgt daarmee impliciet
een verdedigbare default voor een nieuwe adopter; Ties' eigen antwoorden in de
vier bestaande projecten blijven staan als voorbeeld, niet als voorschrift.
Ook uitgewerkt in W37 (#79) — die tekst in `CHANGES.md`'s inleiding wijzigt
mee.

---

## Projectbestanden

| Bestand | Doel |
|---|---|
| `WORKFLOW.md` | De workflow-kern; gesymlinkt als `CLAUDE.md` in elk geadopteerd project |
| `USER-CLAUDE.md` | Userbrede trigger-instructie; gesymlinkt als `~/.claude/CLAUDE.md` |
| `CHANGES.md` | Adopteerbare wijzigingen (na F4: de twaalf niet-NFR-entries) |
| `CHANGES-ARCHIEF.md` | Geretireerde entries, met ID en reden (F5, nieuw) |
| `nfr/*.md` | Register van de vijftien NFR's — één bron voor vraag, betekenis en invulhulp (F4, nieuw) |
| `lib/changes.sh` | Gedeelde parser en predicaatlogica (F3, nieuw) |
| `adopt.sh` | Installeert symlinks, kopieën, skills en de adoptietabel |
| `pending-changes.sh` | Meldt openstaande wijzigingen en onderbouwingen bij sessiestart |
| `check` | Eigen testcommando: syntax, JSON-validatie, shellcheck, testsuite (F1, nieuw) |
| `test/` | Testharnas en `fixtures/nulmeting/` (F1, F2, nieuw) |
| `hooks/` | Guard-scripts voor de `PreToolUse`-hooks (F7, F8, nieuw) |
| `skills/*/SKILL.md` | De negen skills (F10, nieuw) |
| `settings/session-hooks.json` | Hookconfiguratie; gesymlinkt als `.claude/settings.json` |
| `templates/` | Sjablonen voor geadopteerde projecten (PRD, testscenario's, architectuur, CI, issues) |
| `PRD.md` | Dit document |
| `TEST-SCENARIOS.md` | De scenario's die dit document dekken |
| `CHANGELOG.md` | Releasehistorie met vereiste acties per release (F15, nieuw) |
