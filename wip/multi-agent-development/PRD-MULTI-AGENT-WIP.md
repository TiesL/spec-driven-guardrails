# PRD — Multi-agent softwareontwikkeling in de agentic development workflow

| Veld | Waarde |
| --- | --- |
| Status | **Work in progress (WIP) — ter verkenning en review** |
| Beoogde release | **TBD** — volgende release van de bestaande agentic development workflow |
| Type work item | Voorstel voor een GitHub Epic en opvolgende work items |
| Epic | [#65](https://github.com/TiesL/spec-driven-guardrails/issues/65) — Multi-agent softwareontwikkeling in de workflow (WIP-verkenning) |
| Eigenaar | Ties |
| Laatst bijgewerkt | 26 september 2026 |

> Dit document beschrijft een gewenste richting, geen definitieve architectuur of implementatieplan. Besluiten, concrete tooling en technische uitwerking blijven expliciet **TBD**.

> **Verhouding tot de andere documenten in dit repo.** Dit is *niet* het PRD van
> de lopende release — dat is [`PRD.md`](../../PRD.md) ("From prose to mechanism",
> epic [#11](https://github.com/TiesL/spec-driven-guardrails/issues/11)). Dit document
> is een verkenning voor een latere release en is nog niet vertaald naar
> work items; dat gebeurt pas na expliciete besluitvorming. De workflow-afspraken
> waarnaar hieronder verwezen wordt, staan in [`WORKFLOW.md`](../../WORKFLOW.md).

## 1. Samenvatting

De agentic development workflow wordt uitgebreid met een model voor multi-agent softwareontwikkeling. Het doel is niet alleen om werk over agents te verdelen, maar om voorspelbare softwareontwikkeling te organiseren waarin verantwoordelijkheden gescheiden zijn, aantoonbaar wordt gewerkt volgens de workflow en kwaliteit niet op zelfverklaring berust.

Agents werken met afgebakende context en specialistische verantwoordelijkheden. Zij werken samen via expliciete, reviewbare artifacts — bijvoorbeeld requirements, specificaties, ontwerpen, tests, GitHub Issues, documentatie, pull requests en CI-resultaten — in plaats van uitsluitend via informele hand-offs. Een orkestratiemechanisme bewaakt de volgorde, afhankelijkheden, gates en het bewijs dat nodig is om werk door te laten gaan of als voltooid te beschouwen.

## 2. Doel en probleemstelling

### Doel

Een bestaande agentic development workflow zodanig uitbreiden dat een team van AI-agents software kan ontwikkelen binnen dezelfde ontwikkelafspraken die voor het project gelden, met controleerbare naleving en duidelijke kwaliteitsgates.

### Probleemstelling

Zonder expliciet samenwerkings- en governancemodel kunnen meerdere agents:

- dezelfde context verschillend interpreteren of elkaar tegenspreken;
- verantwoordelijkheden overslaan of dubbel uitvoeren;
- werk als “klaar” behandelen zonder onafhankelijk bewijs;
- de afgesproken ontwikkelworkflow slechts gedeeltelijk volgen;
- kennis en beslissingen alleen in chat-overdrachten vastleggen, waardoor traceability ontbreekt.

De gewenste oplossing is daarom geen verzameling los aangestuurde agents, maar een ontwikkelsysteem waarin werk, beslissingen, controles en overdrachten terug te vinden zijn in gedeelde artifacts en aantoonbare gates.

### Gewenste uitkomst

Voor een verandering moet zichtbaar en toetsbaar zijn:

```text
Requirement → specificatie → test(s) → GitHub work item(s) → implementatie → pull request → CI/review → integratie/deployment
```

De exacte artifacttypen, relaties en automatisering worden in vervolgontwerp bepaald.

## 3. Productvisie en ontwerpprincipes

### 3.1 Context isolation en gespecialiseerde verantwoordelijkheden

Iedere agent krijgt een doelgericht afgebakende context: alleen de informatie, bevoegdheden en artifacts die nodig zijn voor de toegewezen verantwoordelijkheid. Dit beperkt ruis, ongecontroleerde aannames en onbedoelde overlap.

Specialisatie wordt primair bepaald door een samenhangende verantwoordelijkheid, niet door een traditionele technische laag. Een verantwoordelijkheid kan door één agent worden uitgevoerd, door verschillende agents gedeeld worden, of in latere iteraties anders worden georganiseerd.

### 3.2 Samenwerking via expliciete artifacts

Agents leveren werk op in duurzame, reviewbare artifacts. Een volgende rol baseert zich op die artifacts en legt haar bevindingen eveneens vast. Voorbeelden zijn:

- requirements en acceptatiecriteria;
- specificaties en architectuur- of ontwerpbesluiten;
- testgevallen en testresultaten;
- GitHub Issues en hun onderlinge relaties;
- code, repositorydocumentatie en Infrastructure as Code;
- pull requests, reviewcommentaar en CI-resultaten.

Chatberichten kunnen coördineren, maar zijn niet het primaire bewijs van voortgang, kwaliteit of traceability.

### 3.3 Voltooiing is een besluit op basis van bewijs

Een agent mag werk uitvoeren en bewijs produceren, maar bepaalt niet zelfstandig dat dat werk aan alle vereisten voldoet. Voortgang en completion volgen uit vooraf gedefinieerde gates, beoordeeld op artifacts en evidence door de daarvoor aangewezen rollen en/of automatisering.

Dit betekent onder meer dat een implementatie niet alleen “klaar” is omdat code is geschreven: relevante tests, review, CI-resultaten, traceability en overige afgesproken controls moeten aantoonbaar aanwezig zijn.

### 3.4 Werkgranulariteit: productbrief, release, feature (besloten, 2026-09-21)

Drie niveaus, elk met een eigen artifact, oplopend in omvang:

| Niveau | Trigger | Artifact | Rol |
| --- | --- | --- | --- |
| 1. Nieuw product | Project ontstaat | Productbrief — wordt zelf `PRD.md` | Product (alleen; Architect nog niet betrokken) |
| 2. Nieuwe release/initiatief binnen bestaand product | Scope groot genoeg voor een eigen Epic | Sectie in `PRD.md` + Epic-issue | Product + Architect |
| 3. Feature binnen een release | Eén afgebakende oplevering | Work item-issue + scenario's in `TEST-SCENARIOS.md` (`Covers:`-token) | Product/Architect (issue) → QA → Fullstack Developer → Reviewer |

Een nieuw product doorloopt alle drie niveaus, in die volgorde. Niveau 3 heeft geen los brief-artifact vooraf: de issue zelf draagt de verkorte productbrief-inhoud (zie hieronder).

**Format van die verkorte inhoud in een issue:** Jobs-to-be-done of user story, afhankelijk van of `PRD.md` een concrete eindgebruiker-persona benoemt naast de beheerder/ontwikkelaar zelf.

- `PRD.md` noemt een externe eindgebruiker-persona → **user story** ("Als [gebruikerstype] wil ik [doel], zodat [reden]").
- `PRD.md`'s doelgroep is de beheerder, andere ontwikkelaars, of de workflow zelf (zoals dit repo) → **Jobs-to-be-done** ("wanneer [situatie], wil ik [motivatie], zodat [uitkomst]").

Deze regel wordt niet per project apart vastgelegd (geen extra veld in `CONTEXT.md`) — de bedoeling is dat de `write-spec`-skill bij elke issue-opmaak tegen `PRD.md`'s doelgroep zou moeten controleren, zodat de regel niet vergeten kan worden en niet verouderd kan raken. Dat is nog niet zo geïmplementeerd: `skills/write-spec/SKILL.md` bevat vandaag geen JTBD-/user-story-/doelgroepcheck.

Concrete plaatsing in `templates/ISSUE_TEMPLATE/epic.md`/`work-item.md` (welk veld deze regel vervangt of aanvult) is **buiten scope voor deze WIP** — zie §8. Dat is een sjabloonwijziging als elke andere en wordt pas een besluit wanneer die templates daadwerkelijk worden aangepast, niet hier vooruitgeschoven.

### 3.5 Pre-decision elaboration: co-thinking sessions (decided, 2026-09-23)

Levels 1 and 2 in §3.4's table (new product; new release/epic within an existing product)
happen *before* a decision to build. This elaboration/elicitation step runs as a
**co-thinking session**: Orchestrator + Product + Architect only — QA, Fullstack Developer,
and Reviewer do not participate, because there is nothing yet to test, implement, or review.
Full detail (evaluation criteria, options weighed, the architecture requirement it produces)
is in [`ARCHITECTURE-MULTI-AGENT-WIP.md`](ARCHITECTURE-MULTI-AGENT-WIP.md), Decision 5 and
A6.

This does not conflict with issue #281's "no phase-skipping in v1" decision (§6,
"Orchestrator: besloten model" above; A3 in `ARCHITECTURE-MULTI-AGENT-WIP.md`) — that
decision governs Level 3 execution, where a work item already exists and all five roles
fully engage on it. A co-thinking session is an earlier, separate layer: there is no work
item yet, so there is nothing for QA/Fullstack Developer/Reviewer to engage with.

Output goes to a dedicated `wip/<slug>/` folder (short, kebab-case, descriptive name — not
tied to an issue number, since a co-thinking session may start before any issue exists),
never directly into `PRD.md`/`ARCHITECTURE.md`. Once Ties explicitly accepts the output
(same acceptance gate as §11), it gets promoted into a new `PRD.md` epic section and a real
Epic issue; the `wip/<slug>/` folder itself is kept afterward as historical record by
default, not deleted — same precedent as this very epic's own `wip/multi-agent-development/`
folder.

**Pilot findings incorporated (2026-09-25).** The pattern above ran for the first time
against `wip/claude-code-plugin/` (Product then Architect, sequential, each a fresh sub-agent
producing a durable report). A blameless retrospective — one fresh reviewer per role plus the
orchestrator's own self-assessment, kept as three separate, unmerged artifacts
(`CO-THINKING-PILOT-RETRO-PRODUCT.md`, `-ARCHITECT.md`, `-ORCHESTRATOR.md`) — surfaced process
gaps now closed in `ARCHITECTURE-MULTI-AGENT-WIP.md` (A7, A8, A9, and the Decision 4
addendum). Two further rules for whoever runs the orchestrator role, not rising to
architecture invariants but load-bearing for every future co-thinking session:

- **Never ask a second-or-later role in the chain for a "final" decomposition/output while
  also asking it to flag disagreements with the prior role.** Those two asks pull against
  each other — "final" nudges toward treating that role's framing as the resolved account,
  undercutting the disagreement-flagging asked for in the same breath. Ask instead for "a
  proposed [output], with every deviation from the prior role's [output] marked and
  reasoned."
- **Every role's report opens with a one-line model/effort declaration** (e.g. "Model/effort:
  Claude Opus, [role] role") — self-declared in the artifact itself, not only recorded
  orchestrator-side, per the `model-choice` skill's "record every stage, always" principle.

## 4. Rollen en verantwoordelijkheden

De onderstaande rollen zijn kernrollen in het beoogde model. Dit zijn verantwoordelijkheden; de toewijzing aan concrete agents is **TBD**.

| Rol | Primaire verantwoordelijkheid | Voorbeelden van evidence / gates |
| --- | --- | --- |
| Product | Probleem, gewenste uitkomst, requirements en acceptatiecriteria expliciteren en inhoudelijk valideren. | Requirements, acceptatiecriteria, productvalidatie. |
| Architect | Samenhang, technische haalbaarheid, grenzen, kwaliteitseisen en ontwerpbesluiten bewaken. | Specificatie/ontwerp, architectuurreview, vastgelegde besluiten. |
| QA | Teststrategie (welk soort test — unit/integratie/end-to-end/penetratie/etc. — past bij deze wijziging) en testscenario's/seams bepalen; kwaliteitsrisico's en verificatie van gedrag bewaken. | Teststrategie, testscenario's/seams, testresultaten, QA-beoordeling. |
| Reviewer / Lead Developer | Onafhankelijk beoordelen: bewijs dat het voorgaande daadwerkelijk gebeurd is; codekwaliteit, abstracties, hergebruik, verbositeit/efficiëntie. | Pull-requestreview, technische bevindingen, goed- of afkeuring. |
| Fullstack Developer | Een samenhangend, afgebakend onderdeel end-to-end implementeren, inclusief relevante tests en documentatie. | Implementatie, rode/groene tests, documentatie, pull request. |

### Kernverantwoordelijkheden per rol (besloten)

Aanvullend op de rollentabel hierboven, per rol de kernverantwoordelijkheden en welke vraag die rol beantwoordt (dit is wat overlap voorkomt — elke rol beantwoordt een andere vraag, niet dezelfde vraag opnieuw):

- **Product**: productvisie en releases bepalen, features/requirements prioriteren op basis van business-/gebruikersbehoefte, trade-off- en scopebeslissingen nemen. Beantwoordt: *is de requirement zelf correct en compleet?*
- **Architect**: systeemstructuur ontwerpen (applicatie-, software-, integratie-, data- en infrastructuurarchitectuur), technologiekeuzes en standaarden vastleggen, schaalbaarheid/performance/onderhoudbaarheid borgen, grote technische besluiten beoordelen, technisch risico mitigeren. Beantwoordt: *voldoet het ontwerp aan de requirement en aan de architectuurprincipes?*
- **QA**: teststrategie bepalen (welk soort test past — unit/integratie/end-to-end/penetratie/etc.) en testscenario's/seams uitwerken, uitvoeren, defecten identificeren/rapporteren, functionele en non-functionele requirements verifiëren, kwaliteitsgates bewaken vóór release. Beantwoordt: *wat moet getest worden, op welke manier, en gedraagt de implementatie zich volgens die tests?*
- **Fullstack Developer**: features/fixes bouwen volgens specificatie, **de daadwerkelijke testcode schrijven volgens QA's teststrategie/scenario's** (rood-voor-groen, zie `tdd-seams`), onderhoudbare code schrijven, codekwaliteit en technische schuld beheren, werkende software opleveren.
- **Reviewer**: onafhankelijke eindgate — verifieert dat er bewijs is dat het voorgaande daadwerkelijk is gebeurd en dat de verzameling artifacts consistent is voor release; beoordeelt daarnaast codekwaliteit, abstracties, hergebruik en verbositeit/efficiëntie (dezelfde reikwijdte als dit repo's eigen `pre-merge-review`/`code-review`). Blijft een eigen rol (niet samengevoegd met QA/Fullstack Developer) — dit repo's eigen `pre-merge-review` (F11) bestaat specifiek omdat, over vier projecten en 27 samengevoegde PR's heen (`PRD.md`), geen enkele daarvan review had; zelfcontrole door dezelfde rol lost dat probleem niet op.

**Overlap 1 — wie schrijft de falende test (QA vs. Fullstack Developer)?** (besloten, resolveert §9 OQ6) Geen overlap zodra de vraag gesplitst wordt: QA bepaalt *wat* getest moet worden en *welk soort test* daarbij past (de strategie/het seam) — dat is QA's bestaande "teststrategie bepalen"-verantwoordelijkheid, nu expliciet inclusief testsoortkeuze. Fullstack Developer schrijft de *daadwerkelijke testcode*, rood-voor-groen, als onderdeel van implementatie — dat is precies wat `tdd-seams`' eigen rood-voor-groen-discipline al beschrijft (het seam is vooraf afgesproken, de rode test hoort bij de implementatiestap). Geen nieuwe regel, alleen de bestaande rolverdeling expliciet gemaakt.

**Overlap 2 — wie verifieert traceability (Reviewer vs. `check-traceability.sh`)?** (besloten, resolveert §9 OQ6) Ook geen overlap: `check-traceability.sh` verifieert *structureel* (link 1, offline, mechanisch) — bestaat er *een* scenario per functionaliteit, resolveren `Covers:`-tokens. Dat kan het script vaststellen, het is geen oordeel. Reviewer verifieert *semantisch* — is het de *juiste* scenario voor de *juiste* functionaliteit, dekt het daadwerkelijk het gedrag dat de requirement vraagt. Dat is precies het soort oordeel een mechanische check niet kan vellen. Andere vraag, geen dubbel werk.

**Gap closed (decided 2026-09-25, in English — see `ROLE-DESCRIPTIONS.md` and
[[feedback_no_dutch_default_english]]): who checks that Fullstack Developer's actual test
code faithfully implements QA's scenarios/strategy, not just that it exists and passes?**
Overlap 1 only resolved *who writes* the test; nothing resolved who verifies it matches
intent. Extends Overlap 2's structural/semantic split to test code specifically: Reviewer
judges this, since it's the same kind of judgment `check-traceability.sh` can't make, and
Reviewer is the only role positioned after Fullstack Developer in the standard path (there is
nowhere else for this check to live).

Samenhang: Product bepaalt *wat*; Architect bepaalt *hoe*; Fullstack Developer voert uit; QA verifieert dat het werkt zoals bedoeld; Reviewer bevestigt onafhankelijk de hele keten vóór release.

**Conflict is verwacht, geen fout van het model.** Een andere vraag per rol voorkomt *overbodige* herverificatie, niet legitiem conflict (bijv. Architect's ontwerp vs. Product's requirement, of QA die een ontwerpfout vindt). Zulke conflicten escaleren via het al besloten enkele pad — rol-agent → orchestrator → Ties — zie de Escalation Triggers in `MULTI-AGENT-WORKFLOW.md` (categorieën 1 en 2 daar). **Bij escalatie van een conflict tussen twee rollen presenteert de orchestrator beide rollen' eigen bevindingen naast elkaar** (besloten, `ARCHITECTURE-MULTI-AGENT-WIP.md` Decision 4) — geen samengevoegde samenvatting, geen alleen-de-laatste-rol-aan-het-woord — zodat Ties zelf vanuit beide posities beoordeelt, niet via orchestrator-interpretatie.

### Security als expliciete verantwoordelijkheid

Security testing en het controleren van security-relevante risico’s zijn een expliciete verantwoordelijkheid in de workflow. Dit betekent niet automatisch dat er een afzonderlijke Security-agent nodig is. De taak kan, afhankelijk van risico, expertise en automatisering, onderdeel zijn van meerdere rollen of later alsnog als aparte rol/agent worden ingericht.

**Minimale gates en risicogestuurde toepassing (besloten):** geen los mechanisme — hergebruikt de bestaande `security-review`-skill. Reviewer roept die aan (checklistitem "Security & Compliance", al aanwezig in `MULTI-AGENT-WORKFLOW.md`) wanneer een wijziging raakt aan: auth/sessiebeheer, secrets/credentials, deploy-/CI-configuratie, Infrastructure as Code, gevoelige/persoonsgegevens, of een interface die niet-vertrouwde input ontvangt (API/CLI/webhook) — risicogestuurd, niet altijd-aan. Geen nieuwe risicotaxonomie: dezelfde OWASP-top-10-achtige categorieën die dit project al impliciet als basislijn hanteert.

**Inbedding van de triggerlijst:** tekst in de skill die Reviewer's rolcontract vastlegt (nog te schrijven, zie "Rol-naar-agent toewijzing" hieronder) — dezelfde plek als Reviewer's overige checklistitems, geen nieuw artifacttype. Optioneel aanvullend: een deterministische, padgebaseerde CI-vlag (raakt `auth/`, `.github/workflows/`, IaC-mappen, deploy-scripts) in de stijl van `check-pr-issue-link.sh` — vervangt Reviewer's eigen beoordeling niet, vangt alleen de voor-de-hand-liggende gevallen.

**Wanneer een aparte Security-agent gerechtvaardigd is:** dezelfde voorwaardelijke-escalatie-redenering als bij UX hieronder — wanneer de triggerlijst van toepassing is *en* de inzet hoog is (echte gebruikerscredentials, betaalgegevens, publiek toegankelijke productieomgeving), niet standaard.

**Minimale testcatalogus per triggercategorie (besloten, resolveert §9 OQ5):** POLP (Principle of Least Privilege) als organiserend uitgangspunt, voor zowel implementatie als test — niet zes losstaande ad-hoc checks, maar telkens dezelfde vraag: *is dit beperkt tot het minimum dat daadwerkelijk nodig is, en bewijst een test dat een overschrijding daarvan wordt geweigerd?*

| Triggercategorie | Minimale test (POLP-vraag) |
| --- | --- |
| Auth/sessiebeheer | Toegang met minder dan de vereiste rol/scope wordt geweigerd — niet alleen "ongeautoriseerd geweigerd" in het algemeen, maar specifiek *te veel* rechten geweigerd. |
| Secrets/credentials | Het gebruikte credential zelf heeft minimale scope (een scoped token, geen mastersleutel); geen secretwaarde lekt in logs/diff/output (dit repo's eigen `gitleaks`-werk, #264). |
| Deploy-/CI-configuratie | De toegekende permissies/scope zijn het minimum voor de taak — zoals dit repo's eigen CI al doet (`contents: read` expliciet, alleen uitgebreid wanneer een stap dat echt nodig heeft). |
| Infrastructure as Code | De geprovisioneerde resource/rol heeft minimale rechten, geen brede/wildcard-toekenningen; een plan/dry-run-diff is bekeken vóór apply, nooit blind toegepast. |
| Gevoelige/persoonsgegevens | Toegang tot de data is beperkt tot wat daadwerkelijk nodig is (minimale scope, minimale bewaartermijn) — conform de privacy-NFR. |
| Niet-vertrouwde input (API/CLI/webhook) | De inputverwerking opereert met minimale rechten op die input — valideert vóór gebruik in een bevoegde operatie, geeft niet-vertrouwde input nooit direct door aan een bevoegde operatie (dit repo's eigen "geen `eval`"-principe, toegepast in bredere zin). |

Dit is de ontbrekende catalogus zelf, niet een nieuwe taxonomie — de triggerlijst hierboven blijft ongewijzigd.

### UX als voorwaardelijke verantwoordelijkheid (besloten activeringsregel)

Geen apart UX-rol standaard. Activeringsregel is **niet** "is er een UI" — dat mist bijvoorbeeld een agent die via een LLM-harness (zoals Claude Code) opereert, waar die harness zelf de interface is die de gebruikerservaring bepaalt. In plaats daarvan: **heeft het product enige interactie-oppervlak waar een mens of agent doorheen opereert** — GUI, CLI, API-responsvorm, foutmeldingen, of een agent-/LLM-harness. Dat is bij vrijwel alles waar, behalve een pure interne library zonder extern interface.

- Bij een interactie-oppervlak → UX-verantwoordelijkheid is standaard verdeeld over bestaande rollen: Product (gewenste UX-uitkomst), QA (bestaand checklistitem "Usability criteria"), Reviewer (bestaand checklistitem "Operational Readiness" uitgebreid). Geen nieuwe rol/agent standaard.
- Geen interactie-oppervlak (zeldzaam) → UX activeert niet.
- Aparte UX-agent alleen wanneer de daadwerkelijke complexiteit/inzet van dat interactie-oppervlak dat rechtvaardigt — zelfde voorwaardelijke-escalatie-patroon als Security hierboven.

### Fullstack developers binnen bounded contexts

De voorkeur is om development agents als fullstack developer agents te organiseren binnen heldere bounded contexts of andere samenhangende werkgrenzen. Zij dragen een wijziging van technisch ontwerp tot implementatie, tests en relevante documentatie voor hun afgebakende onderdeel.

Een verplichte splitsing tussen frontend- en backend-agents is nadrukkelijk geen uitgangspunt. Zo’n splitsing kan later passend blijken wanneer integratiecomplexiteit, schaal of domeingrenzen dat rechtvaardigen, maar is geen standaardstructuur.

### Rol-naar-agent toewijzing (besloten)

- Eén sessie per rol per fase; geen langlevende rol-agent. De orchestrator (zie §6) start een verse sub-agent-sessie per fase; overdracht loopt uitsluitend via artifacts, nooit via chatgeheugen.
- Sequentieel: rollen werken één voor één, geen parallelle uitvoering (vooralsnog — geen infrastructuur hiervoor in dit project).
- Mens/agent-verdeling: Product en Architect zijn agent-ondersteund met de mens (Ties) leidend; QA en Fullstack Developer zijn agent-eigendom; Reviewer is agent-eigendom, optioneel ondersteund door een menselijke engineer (niet Ties) die de PR rechtstreeks via `gh` beoordeelt; mergebevestiging is en blijft uitsluitend menselijk (Ties), nooit geautomatiseerd — zie ook §6.
- Identiteit: `role:<naam>`-labels (bijv. `role:product`, `role:architect`, `role:qa`, `role:dev`, `role:reviewer`) op het issue/PR waaraan de rol werkt. Geen native GitHub-assignee — de orchestrator is zelf de bron van waarheid over wie waaraan werkt; een label zou dat alleen dubbel en inconsistent maken.
- Context isolation: skill-gebaseerd bestands-/mapbereik per rol (welke paden een rol-sessie mag lezen/schrijven), geen worktree-per-rol — niet nodig zolang rollen sequentieel werken (één branch, één checkout op elk moment).

Detailuitwerking en de vijf rollen als concrete agent-specificatie: zie [`MULTI-AGENT-WORKFLOW.md`](MULTI-AGENT-WORKFLOW.md).

## 5. Workflow- en governancestandaarden

De multi-agent-opzet moet de volgende bestaande of beoogde workflowpraktijken ondersteunen en naleven:

| Praktijk | Betekenis voor de workflow |
| --- | --- |
| Spec-driven development (SDD) | Werk start vanuit expliciete, reviewbare specificaties. |
| Test-driven development (TDD) | Ontwikkelwerk volgt waar passend de rood-groen-refactor-cyclus; tests zijn geen sluitpost. |
| Traceability | Relaties tussen requirements, tests, work items en pull requests zijn vastgelegd en controleerbaar. |
| GitHub Issues | GitHub Issues vormen het work-itemmechanisme, inclusief Epic-relaties waar relevant. |
| Documentatie in de repository | Documentatie is een standaardonderdeel van de repository en van de oplevering. |
| Continuous Integration | Tests en relevante controles draaien automatisch bij integratie. |
| Deployments en IaC | Deployments worden waar mogelijk geautomatiseerd; infrastructuur wordt waar mogelijk als code beheerd. |
| GitHub Flow | Branch-, pull-request- en integratiewerk volgt GitHub Flow; projectdetails blijven leidend. |

De exacte interpretatie per project, uitzonderingen en afdwingmechanismen zijn **TBD**. Dit PRD vervangt geen bestaande projectconventies.

## 6. Orchestratie, enforcement en compliance

Orkestratie is een kernonderdeel van het product, niet alleen een uitvoeringsdetail. De orchestrator — als verantwoordelijkheid, mogelijk later als concrete agent of component — coördineert werk over rollen heen.

Beoogde verantwoordelijkheden van orkestratie:

- werk opdelen en aan rollen/agents toewijzen binnen hun contextgrenzen;
- benodigde artifacts en afhankelijkheden zichtbaar maken;
- de voorgeschreven volgorde en gates bewaken;
- vereiste evidence controleren of laten controleren;
- escaleren wanneer evidence ontbreekt, artifacts conflicteren of een gate niet gehaald wordt;
- voorkomen dat een agent een eigen oplevering eenzijdig als compliant of voltooid markeert.

Compliance betekent hier: aantoonbaar handelen volgens de afgesproken workflow, met expliciete uitzonderingen wanneer daarvan wordt afgeweken. Het mechanisme voor uitzonderingen, overrides en audit trail is **TBD**.

### Orchestrator: besloten model

De orchestrator is een concrete agent (niet alleen een verantwoordelijkheid), gedetailleerd uitgewerkt in [`MULTI-AGENT-WORKFLOW.md`](MULTI-AGENT-WORKFLOW.md) — een geïmporteerde spec, op de volgende punten aangepast aan dit project:

- **Context is artifact-gebaseerd, geen los toestandsobject.** De orchestrator bouwt "gedeelde context" door de bestaande artifacts te lezen (issue, `PRD.md`/`ARCHITECTURE.md`-secties, `TEST-SCENARIOS.md`-items, PR-diff, CI-resultaten) — niet door een eigen ondoorzichtige state bij te houden. Elke context is daardoor door iedereen (mens, verse agent, audit) reconstrueerbaar uit dezelfde bronnen. De geïmporteerde spec sprak nog van een los "shared context object"; dat is hiermee vervangen.
- **Escalatie kent één doel**: rol-agent → orchestrator → mens (Ties). Geen aparte routing per rol/lead zoals in de oorspronkelijk geïmporteerde spec (Product Lead/Tech Lead/QA Lead/Release Manager/CTO) — dit project heeft één menselijke beslisser.
- **Non-lineaire routing (loop-back) is toegestaan voor herwerk, maar fase-verkorting/-overslag hoort niet bij v1 (besloten, issue #281)**: elke rol (Product, Architect, QA, Fullstack Developer, Reviewer) is bij elke verandering volledig betrokken, ongeacht type of urgentie. CI, `pre-merge-review` en `deploy-guards` waren al nooit overslaanbaar; dit trekt hetzelfde principe door naar elke rol — geen scenario-gebaseerde routing (security-hotfix, refactor-only, spike of anderszins) in v1. Hoeveel diepgang een verandering daadwerkelijk vraagt, beoordeelt elke rol zelf, binnen de eigen fase — dat blijft een oordeel van de rol, geen orchestrator-regel. Terugschalen van betrokkenheid per scenario is bewust uitgesteld tot een latere versie: dat nu al modelleren, zonder echte gebruiksdata, riskeert overengineering van de eerste release.
- **Geen geautomatiseerde release/merge, ook niet als toekomstige uitbreiding**: mergebevestiging blijft altijd bij Ties, zoals `WORKFLOW.md` stap 4 al vastlegt. Dit vervangt het "2.0-autoapprove"-voorstel uit de geïmporteerde spec (Dev/QA/Reviewer die release zelf autoriseren) — agents mogen wél autonoom naar de *volgende fase* doorschakelen binnen guardrails, nooit naar release.

### Compliance-rapportage: patroon en uitgewerkt voorbeeld (besloten, resolveert §9 OQ9)

**Patroon:** hergebruikt `WORKFLOW-ADOPTION.md`'s rij-per-besluit-vorm (Change/Answer/Date/Notes), geschaald naar per work-item-issue. Elke rij verwijst naar bewijs dat al bestaat (`pre-merge-review`-marker, CI-run, PR-veld) — geen nieuw rapportformat, geen apart dashboard. Orchestrator plaatst dit als één issuecomment per work item, ná merge.

**Uitgewerkt voorbeeld**, tegen een echt, al afgerond work item uit dit repo (issue #265 / PR #279, `wait-for-ci.sh`) — om te bevestigen dat het patroon daadwerkelijk de juiste evidence-links draagt, niet als hypothetisch ontwerp:

| Gate | Status | Evidence |
| --- | --- | --- |
| Discovery/Planning/Test/Implementation-model vastgelegd | ✅ | model-record-markers op PR #279 (alle vier `claude-sonnet-5`) |
| Review: ander/minstens even bekwaam model, of expliciete uitzondering | ✅ | Review-marker met `same-model-exception` (enige beschikbare model in deze sessie) |
| Quality review vóór merge, bevindingen in de PR | ✅ | pre-merge-review ronde 1 (2 bevindingen: ontbrekende `CHANGES.md`-rij; dubbele `gh`-calls + ongeteste zero-checks-case) en ronde 2 (beide opgelost, marker `pre-merge-review:done sha=...` op de laatste commit) |
| CI groen | ✅ | check-run gekoppeld aan PR #279, zelf bevestigd via `wait-for-ci.sh` — dogfooding van het opgeleverde werk zelf |
| Traceability schakel 3 (PR ↔ issue) | ✅ | `Closes #265` in de PR-body, `closingIssuesReferences` = 1 |
| Ties' expliciete mergebevestiging | ✅ | gegeven vóór `gh pr merge`, conform A2 |

**Vastgesteld:** het patroon draagt daadwerkelijk de juiste evidence-links, elke rij wijst naar iets dat al bestaat, en het past in één issuecomment zonder apart dashboard — de resterende twijfel bij OQ9 is hiermee weggenomen.

## 7. Begrippenkader en grenzen

Om ontwerpbeslissingen scherp te houden, worden de volgende begrippen onderscheiden:

| Begrip | Betekenis |
| --- | --- |
| Workflow | De voorgeschreven manier van ontwikkelen: fasen, practices, gates en traceability. |
| Governance | Wie welke beslissing of toetsing mag uitvoeren, welke evidence vereist is en hoe uitzonderingen worden behandeld. |
| Rol | Een duurzame verantwoordelijkheid, zoals Product, Architect, QA of Reviewer. |
| Agent | Een concrete uitvoerder die één of meer rollen of taken krijgt toegewezen. Een rol is niet automatisch één agent. |
| Artifact | Een duurzaam, reviewbaar resultaat of bewijsstuk dat werk overdraagbaar en controleerbaar maakt. |
| Orchestrator | De coördinerende verantwoordelijkheid die werk, afhankelijkheden, gates en compliance bewaakt. |
| Tooling | De technische middelen die de workflow mogelijk maken of afdwingen, zoals GitHub, CI, testframeworks en deployment- of IaC-tooling. |
| Co-thinking session (English term, decided 2026-09-23) | A reduced-role elaboration/elicitation step (Orchestrator + Product + Architect only) for a new product or a new release/epic, before deciding to build — see §3.5. |

Deze begrippen moeten in vervolgontwerp consequent worden gebruikt. Een keuze voor tooling mag de governance- of rolverdeling niet ongemerkt bepalen.

## 8. Buiten scope voor deze WIP

Bijgewerkt 2026-09-21: vijf van de oorspronkelijke zeven punten zijn inmiddels
(gedeeltelijk) besloten elders in dit document of in `ARCHITECTURE-MULTI-AGENT-WIP.md` —
onderaan staat waar. Wat nog steeds volledig openstaat:

- een concrete implementatiestack, modelkeuze of leverancierskeuze;
- een vaste frontend/backend- of andere technische teamsplitsing;
- de precieze technische implementatie van permissies en geheugenmechanisme (het
  *principe* — skill-gebaseerd bestandsbereik, geen state buiten artifacts — is wél
  besloten, zie A1/A4 in `ARCHITECTURE-MULTI-AGENT-WIP.md`);
- een concrete GitHub-sjabloonstructuur voor Issues/PR-templates (het `role:<name>`-label
  is wél besloten, zie A5; §3.4 bakent expliciet af dat concrete sjabloonveldplaatsing
  hier nog niet wordt vastgelegd);
- een uitgewerkte minimale testcatalogus per securitytriggercategorie (de triggerlijst
  zelf is wél besloten, zie §9 OQ5).

Wat oorspronkelijk hier stond en inmiddels (deels) elders besloten is: definitieve
agentarchitectuur/aantal agents (`ARCHITECTURE-MULTI-AGENT-WIP.md` Decision 3, §4 vijf
rollen + orchestrator); UX-rolinvulling (§9 OQ7, volledig besloten); QA/Reviewer-
rolinvulling ("Kernverantwoordelijkheden per rol" hierboven).

## 9. Open questions / TBD

Status per vraag: **besloten**/**deels besloten** verwijst naar een concreet besluit hierboven of in [`ARCHITECTURE-MULTI-AGENT-WIP.md`](ARCHITECTURE-MULTI-AGENT-WIP.md)/[`MULTI-AGENT-WORKFLOW.md`](MULTI-AGENT-WORKFLOW.md); overige blijven **open** — geen enkele hiervan is impliciet beantwoord.

1. Welke artifacts zijn per workflowfase minimaal verplicht, en welke relaties moeten machineleesbaar zijn voor traceability? — **deels besloten**: artifacts per granulariteitsniveau vastgelegd in §3.4; het referentieproces (requirement → PR) met artifact per fase staat in `MULTI-AGENT-WORKFLOW.md`. Machineleesbare relatie blijft het bestaande `Covers:`-token; geen nieuw mechanisme geïntroduceerd.
2. Welke gates zijn verplicht voordat werk naar de volgende fase mag, en welke rol of automatisering beoordeelt elke gate? — **besloten**: gate/rol per fase volgt het referentieproces in `MULTI-AGENT-WORKFLOW.md`, met CI/`pre-merge-review`/`deploy-guards` als nooit-overslaanbare gates (zie "Orchestrator: besloten model", §6).
3. Hoe wordt context isolation technisch en organisatorisch vormgegeven, inclusief toegang tot repository, GitHub en deploymentomgeving? — **besloten**: skill-gebaseerd bestands-/mapbereik per rol (zie "Rol-naar-agent toewijzing", §4), geen OS-sandboxing, geen worktree-per-rol.
4. Hoe worden bounded contexts of andere werkgrenzen vastgesteld en gewijzigd? — **besloten** (21-09-2026): een bounded-contextkeuze is een architectuurbesluit als elk ander, vastgelegd als `## Decision N` in `ARCHITECTURE-MULTI-AGENT-WIP.md`. Wijzigingstrigger hergebruikt `refactoring-triggers`. Wie mag voorstellen en wat gebeurt met werk in uitvoering: zie `ARCHITECTURE-MULTI-AGENT-WIP.md`, "Proposing a boundary change mid-work" — geen synchrone escalatie, een niet-blokkerende issue + async triagevraag aan Ties; werk in uitvoering maakt de oude grens af.
5. Welke security tests en risicoclassificaties zijn minimaal vereist, en wanneer is een afzonderlijke Security-agent gerechtvaardigd? — **besloten** (21-09-2026): zie "Security als expliciete verantwoordelijkheid" hierboven — risicogestuurde triggerlijst (auth, secrets, deploy/CI-config, IaC, gevoelige data, niet-vertrouwde input), ingebed in Reviewer's rolcontract-skill, geen nieuwe taxonomie, plus een POLP-georganiseerde minimale testcatalogus per triggercategorie (zelfde subsectie).
6. Welke verificaties worden verwacht van Product en Architect naast QA en Reviewer, en hoe wordt overlap doelbewust beheerd? — **besloten** (21-09-2026): zie "Kernverantwoordelijkheden per rol" hierboven — elke rol beantwoordt een andere vraag; legitiem conflict escaleert, wordt niet onderdrukt. Beide concrete overlaps opgelost (zie "Overlap 1"/"Overlap 2" in dezelfde subsectie): QA bepaalt teststrategie + scenario, Fullstack Developer schrijft de daadwerkelijke falende test; `check-traceability.sh` verifieert structureel, Reviewer verifieert semantisch.
7. Is een UX-designrol nodig? Zo ja, welke artifacts en gates hoort die rol te bezitten of te beoordelen? — **besloten**: zie "UX als voorwaardelijke verantwoordelijkheid" hierboven — activeringsregel is niet "is er een UI" maar "heeft het product enig interactie-oppervlak" (GUI, CLI, API, of een agent-/LLM-harness); standaard verdeeld over bestaande rollen, aparte agent alleen bij gerechtvaardigde complexiteit/inzet.
8. Welke taken van de orchestrator worden geautomatiseerd, welke vragen menselijk besluit en hoe worden uitzonderingen vastgelegd? — **besloten**: zie "Orchestrator: besloten model", §6.
9. Hoe wordt compliance gerapporteerd zonder dat de workflow onnodig traag of bureaucratisch wordt? — **besloten** (21-09-2026): zie §6, "Compliance-rapportage: patroon en uitgewerkt voorbeeld" — het `WORKFLOW-ADOPTION.md`-patroon, plus een uitgewerkt voorbeeld tegen een echt, afgerond work item (#265/PR #279) dat bevestigt dat het patroon de juiste evidence-links draagt.
10. Hoe sluit dit ontwerp aan op bestaande workflowdocumentatie, bestaande repositories en hun eigen conventies? — **besloten**: hergebruikt bestaande skills/hooks (`WORKFLOW.md`, `write-spec`, `pre-merge-review`, `deploy-guards`, `tdd-seams`, `check-traceability.sh`) ongewijzigd; de nieuwe rol-/orchestratielaag komt in een eigen skill, geen vervanging.

## 10. Voorgestelde vervolgscope

Bijgewerkt 2026-09-21: het referentieproces (requirement → PR, met artifact per fase) dat
hier eerder als "eerstvolgende ontwerpstap" stond, bestaat inmiddels al —
`MULTI-AGENT-WORKFLOW.md`'s pijplijn, "Workflow State & Context Management" en het Standard
Workflow Path-diagram dekken dat. Vier van de zes onderstaande vervolgpunten zijn om
dezelfde reden ook al (deels) besloten. De daadwerkelijk resterende stap is smaller:

1. **OQ9 sluiten**: het bestaande referentieproces tegen één echt work item doorlopen,
   end-to-end, om te bevestigen dat het compliance-rapportagepatroon daadwerkelijk werkt
   zoals beschreven — geen apart nieuw ontwerp, alleen het ontbrekende voorbeeld. (OQ4, OQ5
   en OQ6 zijn op 21-09-2026 volledig besloten — zie §9.)
2. Daarna: §11-acceptatie vragen.

Oorspronkelijke vervolgpunten en waar ze inmiddels (deels) landen: een artifact- en
traceabilitymodel (besloten, §3.4 + het referentieproces); een rol-/agenttoewijzingsmodel en
contextgrenzen (besloten, §4 + A4); orchestration- en compliance-controles (besloten, §6 +
OQ9's patroon); een voorstel voor UX (volledig besloten, OQ7). Nog genuine vervolgscope: een
gate- en evidencecatalogus in detail, en de risico-gebaseerde securitytestaanpak (samenvalt
met OQ5 hierboven).

Elk vervolgvoorstel moet eerst worden getoetst aan de ontwerpprincipes in dit document en mag niet als definitieve architectuur worden behandeld voordat daar expliciet over is besloten.

## 11. Acceptatie van dit PRD

Bijgewerkt 2026-09-21: acceptatie geldt voor dit PRD **samen met**
[`ARCHITECTURE-MULTI-AGENT-WIP.md`](ARCHITECTURE-MULTI-AGENT-WIP.md) en
[`MULTI-AGENT-WORKFLOW.md`](MULTI-AGENT-WORKFLOW.md) — niet alleen dit document. De
architectuurbesluiten en -invarianten (A1-A5) staan inmiddels grotendeels in die twee
bestanden, niet hier; acceptatie van dit PRD alleen zou ze niet dekken.

Dit documentendrietal is gereed om als attachment of referentie bij een GitHub Epic te dienen wanneer stakeholders bevestigen dat het:

- de beoogde richting en uitgangspunten correct weergeeft;
- open ontwerpbeslissingen zichtbaar als **TBD** laat (of **deels besloten**, met wat nog ontbreekt expliciet genoemd — zie §9);
- elke implementatie-/architectuurkeuze vastlegt als een expliciet, gedateerd besluit — geen enkele keuze is stilzwijgend gemaakt (dit is scherper dan "introduceert geen keuzes": een uitgewerkt architectuurdocument bevát keuzes, de eis is dat ze allemaal traceerbaar besloten zijn, niet dat er geen zijn);
- een voldoende basis biedt om afzonderlijke, traceerbare vervolgwork items te formuleren.

**Current status (updated 2026-09-23).** Ties confirmed acceptance on 2026-09-21 — see `wip/multi-agent-development/
DIRECTION-CHECK-SUMMARY.md`. OQ11 (target release timing) stays deliberately open,
resolved only once the process has run end-to-end on one real work item. Follow-up work
items are now being drafted (§3.5's co-thinking session, applied first to the plugin
conversion initiative in `wip/claude-code-plugin/`), consistent with that acceptance.

