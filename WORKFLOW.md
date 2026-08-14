# Werkwijze — Git/GitHub-workflow

Dit project wordt vanaf meerdere computers ontwikkeld. Volg deze workflow in elke sessie, ongeacht op welke machine je werkt. Deze tekst wordt in geadopteerde projecten gesymlinkt als `CLAUDE.md` — zie `README.md` in dit repo voor de adoptieprocedure.

## Branchstrategie: GitHub Flow

- `main` is altijd stabiel/werkend. **Nooit rechtstreeks naar `main` committen of pushen** — dit is een workflow-afspraak, geen technisch afgedwongen regel (GitHub branch protection op private repo's vereist een betaald plan).
- Al het werk gebeurt op een kortlevende branch vanaf de actuele `main`:
  - `feature/<kebab-case-omschrijving>` voor nieuwe functionaliteit/epics
  - `fix/<kebab-case-omschrijving>` voor bugfixes (ook triviale, zoals documentatiecorrecties)

## Bij het starten van een sessie

1. `git fetch origin` (gebeurt ook automatisch via een `SessionStart`-hook, zie `settings/session-hooks.json`).
2. Ga na of je verder werkt aan bestaand werk (bestaande feature-branch) of iets nieuws begint.
   - Bestaand werk: `git checkout <branch> && git pull origin <branch>`.
   - Nieuw werk: `git checkout main && git pull origin main && git checkout -b feature/<naam>` (of `fix/<naam>`).
3. Bekijk de recente historie voor context: `git log --oneline -10` — vooral nuttig als je op de andere computer verdergaat en wilt zien wat er sinds de laatste keer is gebeurd.

## Tijdens het werk

- Commit logische stappen op de feature-branch.
- Push regelmatig naar `origin/<branch>` — nooit naar `main`. Dit gebeurt ook automatisch: een `SessionEnd`-hook pusht bij het afsluiten van een sessie de huidige branch, met een guard die dit overslaat wanneer toevallig `main` is uitgecheckt (extra vangnet, want er is geen branch protection — zie hieronder).
- Commitberichten bevatten geen "Co-Authored-By"-trailer — afgedwongen via `attribution.commit: ""` in `settings/session-hooks.json`, niet afhankelijk van of de uitvoerende sessie zich dat herinnert.

## Afronden

1. Zodra de wijziging klaar en getest is (en, waar van toepassing, handmatig geverifieerd): open een PR met `gh pr create`.
2. **Draai een kwaliteitsreview** vóór de merge — zie hieronder.
3. **Wacht op expliciete bevestiging van Ties** dat de test geslaagd is en er geen regressie is, vóór je merget. Merg nooit automatisch zonder die bevestiging.
4. Merge daarna met `gh pr merge --squash --delete-branch` — dit houdt de historie op `main` overzichtelijk en ruimt de branch (lokaal en remote) direct op.

### Kwaliteitsreview vóór de merge

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
- **Daarbovenop**: precies de NFR's uit "Niet-functionele kenmerken" in
  `templates/PRD.md` waarvoor de bijbehorende `spec-*`-vraag in dit project met
  "ja" is beantwoord (zie `WORKFLOW-ADOPTIE.md`) — er wordt niet gereviewd op
  iets wat niet eens gespecificeerd is.

**Wat ermee gebeurt.** De bevindingen komen in de PR te staan, niet alleen in de
chat: leesbaar, blijvend, achteraf terug te vinden. Elke bevinding wordt daarna
óf opgelost, óf vastgelegd onder *Technical debt* in de PRD met een reden. Niets
verdwijnt stilzwijgend.

**De grens ervan.** Modellen delen veel trainingsdata, dus ook een ander model
heeft deels overlappende blinde vlekken. Dit verhoogt de bodem; het vervangt geen
ervaren engineer die met andere ogen kijkt.

## Specificeren van werk (PRD, testscenario's, issues)

1. Elk project houdt een `PRD.md` (as-built of ontwerp) en
   `TEST-SCENARIOS.md` (Given/When/Then) bij — zie `templates/` in dit
   repo voor de vorm. Bij adoptie van een nieuw project scaffold `adopt.sh`
   beide automatisch als ze nog niet bestaan.
2. Werk wordt vanuit de PRD opgesplitst in GitHub issues: één `Epic`-issue
   voor het geheel, `Work item`-issues per te bouwen onderdeel (zie
   `templates/ISSUE_TEMPLATE/`).
3. Elk work-item-issue heeft eigen Given/When/Then-acceptatiecriteria en
   verwijst naar de bijbehorende scenario's in `TEST-SCENARIOS.md` — zo is
   elk issue direct bruikbaar om de gebouwde software tegen te testen.
4. `PRD.md`/`TEST-SCENARIOS.md` zijn levende documenten: bijwerken zodra de
   implementatie ervan afwijkt (zoals nu al gebeurt in tennis-registration
   en tennis-invoicing).
5. **Onderbouwingsplicht.** Bij het opstellen of herzien van
   `PRD.md`/`ARCHITECTUUR.md`: loop de relevante rijen in
   `WORKFLOW-ADOPTIE.md` langs.
   - **Rijen met de tekst "vereist onderbouwing"** (auto-geseed vanuit
     `Standaard: ja` in `CHANGES.md`): vervang die door een objectieve, op
     dít project gegronde redenering waarom `ja` geldt — of, als die
     redenering niet standhoudt, zet de rij om naar `nee` met de reden.
   - **Nog onbeantwoorde `Standaard: vraag`-rijen**: geen blanco vraag. Doe
     een beargumenteerd voorstel, gegrond in de daadwerkelijke inhoud van dit
     project, en leg dat ter bevestiging voor.
   - Dit geldt voor élke rij die hierbij hoort, niet alleen de NFR's uit
     "Niet-functionele kenmerken" — ook `spec-prd` of `architectuurdocument`
     zelf verdient een echte reden, geen automatisme. Een auto-geseede `ja`
     die nooit onderbouwd wordt, is in de praktijk niet anders dan de stille
     drift die deze hele voorziening moest voorkomen.

## Testen en deployen automatiseren

Voor projecten met buildbare/testbare code gelden twee vaste, platform-
neutrale commandonamen:

1. **`check`** — alles wat bepaalt of een wijziging goed is (typecheck,
   lint, tests, build). De GitHub Actions-workflow (zie `templates/ci.yml`,
   automatisch gescaffold door `adopt.sh` als het project een
   `package.json` heeft) roept dit commando aan en verzint zelf geen
   losse checks — één bron van waarheid, geen drift tussen lokaal en CI.
2. **`deploy`** — rolt daadwerkelijk uit naar een doelomgeving. Blijft altijd
   een bewuste, handmatig gestarte stap: geen automatische uitrol bij een
   merge — dezelfde soort regie als bij de afspraak dat een merge pas gebeurt
   na expliciete bevestiging (zie "Afronden" hierboven).

Projectspecifieke checks (een eigen lintregel, een domeinspecifieke
validatie) horen thuis in het `check`-script van het project zelf, niet in
`claude-workflow`.

Dit sjabloon veronderstelt npm. Voor een project op een andere stack geldt
hetzelfde principe (vaste `check`/`deploy`-namen, CI roept alleen `check`
aan), toegepast met de eigen tooling van die stack — `adopt.sh` scaffoldt
`ci.yml` alleen wanneer een `package.json` aanwezig is.

### `deploy` weigert te draaien vanuit een ongeverifieerde toestand

`deploy` controleert zelf of de toestand deugt en stopt als dat niet zo is.
Welke voorwaarden gelden, hangt af van de doelomgeving.

**Pre-productie (acceptatie) — mag vanaf elke branch.** De omgeving waarin de
acceptatietest gebeurt, vóór de merge. Voorwaarden: de werkmap is schoon (wat je
uitrolt is herleidbaar tot één commit — anders weet je niet wát je getest hebt);
`check` slaagt (`deploy` draait hem zelf, in plaats van erop te vertrouwen dat je
eraan dacht); de commit is gepusht (zodat CI hem ziet, en terug te vinden is wat
er in acceptatie stond). Een groene CI-run is hier bewust géén voorwaarde —
`check` is net lokaal gedraaid, en wachten bij elke iteratie maakt de lus traag.

**Productie — alleen vanaf `main`.** Alles hierboven, plus: je staat op `main`
(alleen dan is de code via een PR gegaan en gereviewd); lokale `main` is gelijk
aan `origin/main` (anders rol je iets uit dat CI nooit gezien heeft, of juist
iets verouderds); de laatste CI-run op `main` is geslaagd.

Heeft een project meer dan één doelomgeving, dan is er **geen impliciete
standaard** — de omgeving wordt elke keer expliciet meegegeven. Een
standaardwaarde die je kunt vergeten is precies het mechanisme dat hier wordt
afgeschaft.

Controles die het netwerk nodig hebben (CI-status, actualiteit van de remote)
waarschuwen en gaan door als tooling of verbinding ontbreekt; de puur lokale
controles blokkeren hard. Er is één bewuste uitweg (`--force` of gelijkwaardig)
die luid meldt wélke controles worden overgeslagen en naar wélke omgeving het
gaat — een guard zonder uitweg wordt op den duur omzeild door het script aan te
passen, en dat is erger dan een guard die je expliciet uitzet.

### De volgorde in de praktijk

1. Werk op een feature-branch; commit en push.
2. Deploy die branch naar **pre-productie**; doe daar de acceptatietest.
3. Gaat die goed: Ties initieert de merge naar `main` (zie "Afronden").
4. Deploy `main` naar **productie**, na expliciete goedkeuring van Ties.

Zonder pre-productieomgeving bijten stap 2 en de afspraak uit "Afronden" elkaar:
verifiëren kan dan alleen in productie, maar daar mag je pas ná de merge komen.
Laat die spanning niet sluimeren — kies bewust: gebruik de ontsnappingsroute voor
die ene uitrol en zeg hardop dat je dat doet, óf richt een pre-productieomgeving
in. Het tweede is de bedoeling.

### Waarom deze regels bestaan

Een `deploy` die niet naar git kijkt, rolt uit wat er toevallig in de werkmap
ligt — ongeacht branch, commit of CI. Draait er daarna een periodieke trigger op
die code, dan voert ongereviewde code zichzelf uit; een bevestigingsstap in een
UI beschermt alleen de handmatige route, niet de automatische. Dit is in
`tennis-admin` één keer misgegaan, en de enige beveiliging tot dat moment was dat
degene die deployde eraan dacht. Dat is geen beveiliging. Uitgewerkt voorbeeld:
`scripts/deploy.mjs` in `tennis-admin`.

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

## Adoptieregistratie: per wijziging een keuze per project

Niet elke afspraak uit `claude-workflow` past bij elk project. Daarom legt elk
geadopteerd project in `WORKFLOW-ADOPTIE.md` vast wélke wijzigingen het
toepast — zodat afwijken een geregistreerde, onderbouwde uitzondering is in
plaats van stille drift.

Hoe het loopt:

1. Elke PR op `claude-workflow` die iets toevoegt waarover een project een eigen
   keuze moet maken, **voegt een entry toe aan `CHANGES.md`** — met een gesloten
   vraag, een `Standaard` (`ja`/`vraag`, zie hieronder), een "van toepassing
   als"-conditie en wat "ja" concreet betekent. Geen entry betekent geen vraag,
   en dus een vals gevoel van dekking; let hier bij review op.
2. Bij sessiestart meldt een hook welke van die wijzigingen voor dít project van
   toepassing zijn en nog geen antwoord hebben.
3. Hoe Claude die vraag afhandelt, hangt af van het soort entry:
   - **Raakt de entry `PRD.md`/`ARCHITECTUUR.md`** (de meeste `spec-*`-entries
     en de NFR's): volg de onderbouwingsplicht uit "Specificeren van werk"
     hierboven — geen blanco vraag en geen stilzwijgend geaccepteerde `ja`,
     altijd een op dit project gegronde redenering.
   - **Puur procesmatig, raakt geen specificatie** (bijv. `ci-conventie`,
     `deploy-guards`): een gewone gesloten ja/nee-vraag volstaat.
   In beide gevallen: schrijf het antwoord in `WORKFLOW-ADOPTIE.md`, en voer bij
   "ja" de actie uit of maak er een work item voor.

**`Standaard: ja` vs. `Standaard: vraag`** bepaalt alleen het startpunt, niet of
onderbouwing nodig is. Bij adoptie van een nieuw project zet `adopt.sh` elke op
dat moment toepasselijke `Standaard: ja`-wijziging op "ja — vereist
onderbouwing" (een voorlopige stempel, geen besluit); `Standaard: vraag`-
wijzigingen worden nooit automatisch beantwoord. Een ontbrekende rij betekent
"(nog) niet van toepassing": wordt de conditie later alsnog waar — een project
krijgt bijvoorbeeld een deploycommando — dan verschijnt de vraag vanzelf. Een
`nee`-rij is een bewuste, onderbouwde uitzondering en blijft staan tot je hem
handmatig weghaalt.

## Nieuw (gerelateerd) project opzetten

1. `gh repo create <naam> --private --source=. --remote=origin` — maakt in één stap een lege GitHub-repo aan, initialiseert git lokaal (`git init`) en koppelt de remote (`git remote add origin <URL>`). Gebruik `git init` + `git remote add origin <URL>` los van elkaar alleen als de GitHub-repo al bestaat of buiten `gh` om is aangemaakt.
2. Deze gedeelde workflow adopteren via `adopt.sh` in dit repo (`claude-workflow`) — zie `README.md`.

## Waarom

Zonder deze afspraak ontstaan conflicten en kan werk van de ene computer per ongeluk overschreven worden door werk van de andere. Er is geen technische blokkade tegen directe pushes naar `main` — volg deze workflow dus bewust, ook wanneer een directe push technisch zou lukken.
