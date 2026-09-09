# PRD — Multi-agent softwareontwikkeling in de agentic development workflow

| Veld | Waarde |
| --- | --- |
| Status | **Work in progress (WIP) — ter verkenning en review** |
| Beoogde release | **TBD** — volgende release van de bestaande agentic development workflow |
| Type work item | Voorstel voor een GitHub Epic en opvolgende work items |
| Epic | [#65](https://github.com/TiesL/claude-workflow/issues/65) — Multi-agent softwareontwikkeling in de workflow (WIP-verkenning) |
| Eigenaar | Ties / **TBD** |
| Laatst bijgewerkt | 4 september 2026 |

> Dit document beschrijft een gewenste richting, geen definitieve architectuur of implementatieplan. Besluiten, concrete tooling en technische uitwerking blijven expliciet **TBD**.

> **Verhouding tot de andere documenten in dit repo.** Dit is *niet* het PRD van
> de lopende release — dat is [`PRD.md`](PRD.md) ("From prose to mechanism",
> epic [#11](https://github.com/TiesL/claude-workflow/issues/11)). Dit document
> is een verkenning voor een latere release en is nog niet vertaald naar
> work items; dat gebeurt pas na expliciete besluitvorming. De workflow-afspraken
> waarnaar hieronder verwezen wordt, staan in [`WORKFLOW.md`](WORKFLOW.md).

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

## 4. Rollen en verantwoordelijkheden

De onderstaande rollen zijn kernrollen in het beoogde model. Dit zijn verantwoordelijkheden; de toewijzing aan concrete agents is **TBD**.

| Rol | Primaire verantwoordelijkheid | Voorbeelden van evidence / gates |
| --- | --- | --- |
| Product | Probleem, gewenste uitkomst, requirements en acceptatiecriteria expliciteren en inhoudelijk valideren. | Requirements, acceptatiecriteria, productvalidatie. |
| Architect | Samenhang, technische haalbaarheid, grenzen, kwaliteitseisen en ontwerpbesluiten bewaken. | Specificatie/ontwerp, architectuurreview, vastgelegde besluiten. |
| QA | Teststrategie, kwaliteitsrisico’s en verificatie van gedrag bewaken. | Testgevallen, testresultaten, QA-beoordeling. |
| Reviewer / Lead Developer | Kwaliteit en onderhoudbaarheid van de geleverde ontwikkeloutput onafhankelijk beoordelen. | Pull-requestreview, technische bevindingen, goed- of afkeuring. |
| Fullstack Developer | Een samenhangend, afgebakend onderdeel end-to-end implementeren, inclusief relevante tests en documentatie. | Implementatie, rode/groene tests, documentatie, pull request. |

### Security als expliciete verantwoordelijkheid

Security testing en het controleren van security-relevante risico’s zijn een expliciete verantwoordelijkheid in de workflow. Dit betekent niet automatisch dat er een afzonderlijke Security-agent nodig is. De taak kan, afhankelijk van risico, expertise en automatisering, onderdeel zijn van meerdere rollen of later alsnog als aparte rol/agent worden ingericht.

De minimale security-gates, hun risicogestuurde toepassing en de eigenaar per gate zijn **TBD**.

### Fullstack developers binnen bounded contexts

De voorkeur is om development agents als fullstack developer agents te organiseren binnen heldere bounded contexts of andere samenhangende werkgrenzen. Zij dragen een wijziging van technisch ontwerp tot implementatie, tests en relevante documentatie voor hun afgebakende onderdeel.

Een verplichte splitsing tussen frontend- en backend-agents is nadrukkelijk geen uitgangspunt. Zo’n splitsing kan later passend blijken wanneer integratiecomplexiteit, schaal of domeingrenzen dat rechtvaardigen, maar is geen standaardstructuur.

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

Deze begrippen moeten in vervolgontwerp consequent worden gebruikt. Een keuze voor tooling mag de governance- of rolverdeling niet ongemerkt bepalen.

## 8. Buiten scope voor deze WIP

Dit document legt nog niet vast:

- een definitieve agentarchitectuur, aantal agents of runtime;
- een concrete implementatiestack, modelkeuze of leverancierskeuze;
- de precieze prompts, permissies, contextmechanismen of geheugenstrategie;
- een definitieve GitHub-gegevensstructuur voor requirements, Issues, labels of PR-templates;
- definitieve kwaliteitsdrempels, securitycontroles of deploymentregels;
- een vaste frontend/backend- of andere technische teamsplitsing;
- een volledige UX-, test- of securityrolinvulling.

## 9. Open questions / TBD

1. Welke artifacts zijn per workflowfase minimaal verplicht, en welke relaties moeten machineleesbaar zijn voor traceability?
2. Welke gates zijn verplicht voordat werk naar de volgende fase mag, en welke rol of automatisering beoordeelt elke gate?
3. Hoe wordt context isolation technisch en organisatorisch vormgegeven, inclusief toegang tot repository, GitHub en deploymentomgeving?
4. Hoe worden bounded contexts of andere werkgrenzen vastgesteld en gewijzigd?
5. Welke security tests en risicoclassificaties zijn minimaal vereist, en wanneer is een afzonderlijke Security-agent gerechtvaardigd?
6. Welke verificaties worden verwacht van Product en Architect naast QA en Reviewer, en hoe wordt overlap doelbewust beheerd?
7. Is een UX-designrol nodig? Zo ja, welke artifacts en gates hoort die rol te bezitten of te beoordelen?
8. Welke taken van de orchestrator worden geautomatiseerd, welke vragen menselijk besluit en hoe worden uitzonderingen vastgelegd?
9. Hoe wordt compliance gerapporteerd zonder dat de workflow onnodig traag of bureaucratisch wordt?
10. Hoe sluit dit ontwerp aan op bestaande workflowdocumentatie, bestaande repositories en hun eigen conventies?

## 10. Voorgestelde vervolgscope

De eerstvolgende ontwerpstap is het uitwerken van een minimaal, toetsbaar referentieproces voor één verandering. Dat proces moet ten minste de lifecycle van requirement tot pull request beschrijven, met de benodigde artifacts, verantwoordelijke rollen, gates en traceability-relaties.

Vervolgwork items kunnen daarna gericht worden opgesteld voor onder meer:

- een artifact- en traceabilitymodel;
- een gate- en evidencecatalogus;
- een rol-/agenttoewijzingsmodel en contextgrenzen;
- orchestration en compliance-controles;
- een risico-gebaseerde securitytestaanpak;
- een voorstel voor UX en multidisciplinaire verificatie.

Elk vervolgvoorstel moet eerst worden getoetst aan de ontwerpprincipes in dit document en mag niet als definitieve architectuur worden behandeld voordat daar expliciet over is besloten.

## 11. Acceptatie van dit PRD

Dit WIP-PRD is gereed om als attachment of referentie bij een GitHub Epic te dienen wanneer stakeholders bevestigen dat het:

- de beoogde richting en uitgangspunten correct weergeeft;
- open ontwerpbeslissingen zichtbaar als **TBD** laat;
- geen onbesproken implementatie- of architectuurkeuzen introduceert;
- een voldoende basis biedt om afzonderlijke, traceerbare vervolgwork items te formuleren.

**Huidige stand.** Het document is als WIP opgenomen in dit repo en gekoppeld aan
epic [#65](https://github.com/TiesL/claude-workflow/issues/65). Die opname is
geen acceptatie: de bevestiging hierboven is nog niet gegeven, en zolang dat zo
is worden er geen vervolgwork items uit afgeleid.

