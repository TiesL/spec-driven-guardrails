# Testscenario's — claude-workflow

Doel: deze scenario's beschrijven het beoogde/waargenomen gedrag (zie `PRD.md`).
Ze zijn onafhankelijk van de gekozen technische oplossing en beschrijven alleen
waarneembaar gedrag.

Notatie: **Given / When / Then**.

Elk scenario draagt een `**Dekt:**`-veld met de functionaliteit uit `PRD.md` die
het toetst — de conventie uit F13b, hier op dit repo zelf toegepast. De prefixen
zijn bewust gemengd: `R<n>` zijn de regressiescenario's uit het oorspronkelijke
issue #7, `T<n>` de traceabilityscenario's uit #8, `S<n>` de nieuwe. Dat is geen
slordigheid maar de proef op de som van F13c: de integriteitscontrole mag geen
prefix hardcoderen.

**Rood vóór groen.** Elk scenario wordt toegevoegd en aantoonbaar rood gezien
vóórdat de bijbehorende implementatie landt. De uitzondering is R1–R9: die horen
juist **groen** te zijn op ongewijzigde `main` — zij leggen de nulmeting vast en
bewijzen dat de refactor gedrag behoudt, niet dat er iets nieuws bij komt.

---

## Regressie — gedragsbehoud over de refactor heen

### R1 — Verse adoptie seedt exact dezelfde rijen
**Dekt:** F3
- Given: een leeg git-project zonder `package.json`
- When: `adopt.sh .` wordt gedraaid
- Then: `WORKFLOW-ADOPTIE.md` bevat exact 17 rijen, allemaal met "vereist
  onderbouwing tijdens PRD/architectuur"
- And: de legacy-entry `prd-testscenarios-issue-templates` staat er **niet** in

### R2 — Openstaande vragen na verse adoptie
**Dekt:** F3
- Given: hetzelfde verse project, direct na adoptie
- When: `pending-changes.sh .` wordt gedraaid
- Then: exact deze 7 ID's verschijnen als openstaand, in willekeurige volgorde:
  `proces-issue-tracking`, `test-integratie`, `spec-performance-schaal`,
  `spec-compliance`, `spec-portability`, `spec-usability`, `spec-kostenbeheersing`

### R3 — `package.json` maakt `ci-conventie` relevant
**Dekt:** F3
- Given: hetzelfde project, nu met een `package.json`
- When: `pending-changes.sh .` wordt gedraaid
- Then: `ci-conventie` verschijnt aanvullend als openstaand

### R4 — Een `"deploy"`-script maakt `deploy-guards` relevant
**Dekt:** F3
- Given: `package.json` met een `"deploy"`-script
- When: `pending-changes.sh .` wordt gedraaid
- Then: `deploy-guards` verschijnt als openstaand

### R5 — NFR-lijst blijft 1-op-1 synchroon
**Dekt:** F4
- Given: de vijftien NFR-ID's en de vijftien `###`-subsecties onder
  "Niet-functionele kenmerken" in `templates/PRD.md`
- When: beide lijsten naast elkaar gelegd worden
- Then: exacte 1-op-1-overeenkomst, geen ontbrekende of overtollige kant
- And: na F4 gebeurt dat via het `id`/`kop`-paar uit `nfr/*.md`, zonder
  normalisatieheuristiek

### R6 — Predicaatgedrag identiek tussen beide scripts
**Dekt:** F3
- Given: vier testprojecten (met/zonder `package.json` × met/zonder `"deploy"`-script)
- When: de seed-logica en `van_toepassing()` beide `heeft-package-json` en
  `heeft-deploy-script` evalueren tegen elk van de vier
- Then: beide komen voor elke combinatie tot exact hetzelfde antwoord

### R7 — Geadopteerd project blijft de volledige operationele instructie zien
**Dekt:** F12
- Given: een geadopteerd project waarvan `CLAUDE.md` naar de opgesplitste
  `WORKFLOW.md` symlinkt
- When: een sessie start en `CLAUDE.md` gelezen wordt
- Then: branching, kwaliteitsreview, onderbouwingsplicht, deploy-guards en
  adoptieregistratie zijn allemaal bereikbaar — direct in het bestand, of via een
  expliciete, direct volgbare verwijzing
- And: elke in de Wegwijzer genoemde skill bestaat als `SKILL.md`

### R8 — Retirement blijft werken na herstructurering van `CHANGES.md`
**Dekt:** F5
- Given: een geretireerde entry, verhuisd naar `CHANGES-ARCHIEF.md`
- When: `adopt.sh` en `pending-changes.sh` tegen een project draaien
- Then: de entry wordt nergens meer geseed of gevraagd
- And: het ID blijft vindbaar via `grep` over `CHANGES.md` + het archiefbestand
  samen, zodat een project dat de entry ooit beantwoordde kan nazoeken waar die
  rij vandaan komt

### R9 — De vier bestaande projecten krijgen geen enkele vraag opnieuw
**Dekt:** F2
- Given: de ingevroren nulmeting-fixtures van `tennis-admin`,
  `tennis-registration`, `tennis-invoicing` en `a2t-emails`
- When: `pending-changes.sh` na de refactor tegen elke fixture draait
- Then: aantal én identiteit van openstaande vragen is exact gelijk aan de nulmeting
- And: wijkt dit af, dan faalt de test met het verschil per ID benoemd — een
  stille wijziging in de vraagset is nooit acceptabel, ook niet als "opschoning"

---

## Testharnas en `check`

### S1 — `check` faalt op een syntaxfout in een script
**Dekt:** F1
- Given: een script in dit repo met een bash-syntaxfout
- When: `./check` draait
- Then: exit ≠ 0, met het betreffende bestand in de melding

### S2 — `check` faalt op ongeldige JSON in de hookconfiguratie
**Dekt:** F1
- Given: `settings/session-hooks.json` met een ontbrekende komma
- When: `./check` draait
- Then: exit ≠ 0 met een melding die het bestand noemt
- And: dit gebeurt ook wanneer `shellcheck` niet geïnstalleerd is — de
  JSON-validatie is geen optionele stap

### S3 — De testsandbox weigert te draaien met de echte `HOME`
**Dekt:** F1
- Given: een test waarvan de sandboxopzet `HOME` niet heeft omgezet
- When: die test start
- Then: de run stopt onmiddellijk met een expliciete melding
- And: er is niets geschreven buiten de tijdelijke map

### S4 — Nulmeting-fixture legt `a2t-emails` vast zoals gevonden
**Dekt:** F2
- Given: `a2t-emails` heeft geen `WORKFLOW-ADOPTIE.md`
- When: de nulmeting-fixture wordt aangemaakt
- Then: de fixture legt "alles openstaand" vast
- And: er wordt géén `WORKFLOW-ADOPTIE.md` aangemaakt of gerepareerd — de fixture
  bevat de toestand, niet de reparatie

---

## NFR-register en archief

### S5 — Generator en ingecheckt sjabloon lopen niet uit de pas
**Dekt:** F4
- Given: een `nfr/*.md` waarvan de `Invulhulp` gewijzigd is zonder
  `templates/PRD.md` te regenereren
- When: `./check` draait
- Then: exit ≠ 0, met de betreffende NFR in de melding

### S6 — Een entry zonder `Van toepassing als` levert een waarschuwing
**Dekt:** F5
- Given: `CHANGES.md` met een `## `-kop zonder `Van toepassing als`-veld, terwijl
  de sectiescheidingen naar `###` zijn omgezet
- When: de gedeelde parser die bron leest
- Then: er verschijnt een waarschuwing die het ID noemt
- And: de entry wordt niet geseed of gevraagd — een waarschuwing blokkeert niets

---

## Onderbouwingsplicht en poorten

### S7 — Het signaal telt rijen die nog op onderbouwing wachten
**Dekt:** F6
- Given: een vers geadopteerd project met 17 geseede rijen die "vereist
  onderbouwing" dragen
- When: `pending-changes.sh` draait
- Then: er verschijnt een melding "17 rij(en) … wachten nog op onderbouwing"

### S8 — Het signaal verandert de openstaand-set niet
**Dekt:** F6
- Given: hetzelfde project
- When: `pending-changes.sh` draait
- Then: de lijst openstaande ID's is identiek aan die vóór F6 — het nieuwe
  signaal staat ernaast, niet erin

### S9 — Verouderde adoptie meldt zichzelf
**Dekt:** F6
- Given: een geadopteerd project zonder `.claude/skills/`, terwijl
  `$CLAUDE_WORKFLOW_DIR/skills` skills bevat
- When: een sessie start
- Then: de hook meldt dat `adopt.sh` opnieuw moet draaien
- And: de sessie start gewoon door — de melding blokkeert niets

### S10 — De productie-poort blokkeert een onderbouwingsgat
**Dekt:** F6
- Given: een project waarvan een rij met `productie-poort: ja` nog "vereist
  onderbouwing" zegt
- When: `deploy` naar productie wordt aangeroepen
- Then: de deploy stopt met een melding die de betreffende rij noemt
- And: dezelfde deploy naar pre-productie gaat wél door

---

## Git-guardrails

### S11 — Destructieve commando's worden geblokkeerd
**Dekt:** F7
- Given: de guardrails-hook is actief
- When: `git reset --hard`, `git clean -fd`, `git branch -D <naam>` of
  `git checkout .` wordt aangeroepen
- Then: het commando wordt geblokkeerd met een leesbare reden

### S12 — Push naar `main` wordt geblokkeerd, ook via refspec
**Dekt:** F7
- Given: een uitgecheckte feature-branch
- When: `git push origin main` of `git push origin HEAD:main` wordt aangeroepen
- Then: het commando wordt geblokkeerd
- And: `git push origin HEAD` terwijl `main` is uitgecheckt wordt óók geblokkeerd

### S13 — Push naar een feature-branch blijft werken
**Dekt:** F7
- Given: een uitgecheckte feature-branch
- When: `git push origin HEAD` wordt aangeroepen
- Then: het commando gaat door — de bestaande `SessionEnd`-hook blijft werken

### S14 — De guard faalt naar toestaan als hij zelf stuk is
**Dekt:** F7
- Given: geen `jq`, geen `python3` en geen bruikbare `sed` in `PATH`
- When: een willekeurig git-commando langs de guard komt
- Then: er verschijnt een luide waarschuwing
- And: het commando wordt toegestaan — een kapotte guard blokkeert nooit het werk

---

## Merge-guard

### S15 — Merge zonder review-marker wordt geblokkeerd
**Dekt:** F8
- Given: een open PR zonder review-marker in de comments
- When: `gh pr merge` wordt aangeroepen
- Then: het commando wordt geblokkeerd, met verwijzing naar `pre-merge-review`

### S16 — Merge mét review-marker gaat door
**Dekt:** F8
- Given: een open PR met de marker die `pre-merge-review` plaatst
- When: `gh pr merge` wordt aangeroepen
- Then: het commando gaat door

### S17 — De merge-guard faalt open zonder netwerk
**Dekt:** F8
- Given: `gh` ontbreekt of heeft geen netwerkverbinding
- When: `gh pr merge` wordt aangeroepen
- Then: er verschijnt een luide waarschuwing dat de reviewcontrole is overgeslagen
- And: het commando wordt toegestaan

### S18 — Een onderbouwde `nee` schakelt de guard uit
**Dekt:** F8
- Given: een project waarvan `WORKFLOW-ADOPTIE.md` `kwaliteitsreview-voor-merge`
  op `nee` heeft staan
- When: `gh pr merge` wordt aangeroepen op een PR zonder marker
- Then: het commando gaat door, zonder blokkade
- And: dat gebeurt zonder netwerkaanroep — de rij wordt lokaal gelezen

---

## Skills-infrastructuur

### S19 — `adopt.sh` installeert per-skill symlinks
**Dekt:** F9
- Given: een geadopteerd project en een gevulde `skills/`-map in dit repo
- When: `adopt.sh` draait
- Then: `.claude/skills/<naam>` bestaat per skill als symlink naar dit repo
- And: `.claude/skills` zelf is een echte map, geen symlink

### S20 — Verweesde symlinks worden opgeruimd, echte mappen niet
**Dekt:** F9
- Given: `.claude/skills/oude-naam` wijst naar een niet meer bestaande skill in
  dit repo, en `.claude/skills/eigen-skill` is een echte map van het project
- When: `adopt.sh` draait
- Then: `oude-naam` is verwijderd
- And: `eigen-skill` is onaangeroerd

### S21 — Het `.gitignore`-blok wordt beheerd, niet gestapeld
**Dekt:** F9
- Given: een `.gitignore` met de twee bestaande losse regels `CLAUDE.md` en
  `.claude/settings.json`
- When: `adopt.sh` draait
- Then: die regels staan precies één keer, binnen het beheerde blok
- And: regels buiten het blok blijven onaangeroerd

### S22 — `adopt.sh` is idempotent
**Dekt:** F9
- Given: een geadopteerd project
- When: `adopt.sh` twee keer achter elkaar draait
- Then: de bestandsboom is na de tweede run identiek aan na de eerste
- And: `.gitignore` is byte-identiek

### S23 — `adopt.sh` is een no-op zonder `skills/`
**Dekt:** F9
- Given: een checkout van dit repo van vóór deze release, zonder `skills/`-map
- When: `adopt.sh` draait
- Then: de adoptie slaagt zonder foutmelding
- And: er wordt geen lege `.claude/skills/` achtergelaten

---

## Skills en review

### S24 — Elke skill in het register bestaat en is vindbaar
**Dekt:** F10
- Given: het skill-register uit `PRD.md` F10
- When: `./check` draait
- Then: elke genoemde skill heeft een `SKILL.md` met een `name` en `description`
  in de frontmatter

### S25 — De user-level skill staat op userniveau
**Dekt:** F10
- Given: een niet-geadopteerd git-project
- When: `adopt.sh --user` is gedraaid en een sessie start
- Then: `adopt-workflow` is beschikbaar zonder dat `.claude/skills/` in dat
  project bestaat

### S26 — De reviewscope volgt de beantwoorde `spec-*`-rijen
**Dekt:** F11
- Given: een project waarvan `WORKFLOW-ADOPTIE.md` alleen `spec-security` en
  `spec-data-integriteit` op `ja` heeft
- When: `pre-merge-review` draait
- Then: de scope bevat complexiteit en dependencies plus precies die twee NFR's
- And: NFR's die op `nee` of onbeantwoord staan komen niet in de scope

### S27 — Ontbrekende ankers degraderen, ze blokkeren niet
**Dekt:** F11
- Given: een project-PRD zonder de door F4 geplaatste ankers
- When: `pre-merge-review` draait
- Then: de skill valt terug op de kopnamen
- And: hij meldt expliciet dat de ankers ontbreken

### S28 — De review plaatst een machineherkenbare marker
**Dekt:** F11
- Given: een PR waarop `pre-merge-review` zijn bevindingen plaatst
- When: de merge-guard die PR daarna beoordeelt
- Then: de marker wordt gevonden en de merge wordt toegestaan

### S29 — De Wegwijzer lost elk verplaatst onderwerp in één sprong op
**Dekt:** F12
- Given: de vijf termen uit R7 (branching, kwaliteitsreview, onderbouwingsplicht,
  deploy-guards, adoptieregistratie)
- When: `WORKFLOW.md` op elk van die termen wordt gegrept
- Then: elke term levert een Wegwijzer-rij op die naar precies één bestaande skill
  verwijst
- And: twee termen die in dezelfde skill landen krijgen twee eigen rijen

---

## Traceability

### T1 — Volledige keten, alles gedekt
**Dekt:** F13
- Given: `PRD.md` met `F1`; `TEST-SCENARIOS.md` met `S1` (`Dekt: F1`) en `S2`
  (`Dekt: F1`); een issue dat `S1` en `S2` noemt; een PR die naar dat issue verwijst
- When: de controle draait
- Then: geen fouten, exit 0

### T2 — Functionaliteit zonder scenario
**Dekt:** F13
- Given: `PRD.md` met `F2`, geen enkel scenario met `Dekt: F2`
- When: de controle draait
- Then: faalt met een melding die expliciet `F2` noemt

### T3 — Scenario zonder issue
**Dekt:** F13
- Given: `S3` bestaat, geen enkel issue noemt `S3` in het daarvoor bestemde veld
- When: de poort in `pre-merge-review` draait
- Then: de bevinding noemt expliciet `S3`

### T4 — PR zonder gelinkt issue
**Dekt:** F13
- Given: een PR zonder `Closes #<n>` en zonder gelinkt issue
- When: de CI-check op de PR draait
- Then: de check faalt en noemt de betreffende PR

### T5 — Vals-positief voorkomen
**Dekt:** F13
- Given: een issue-tekst die `S1` noemt in een zin die geen verwijzing is
  (bijv. "we hebben inmiddels s1 varianten getest")
- When: de controle draait
- Then: dit telt **niet** mee als schakel — alleen het daarvoor bestemde veld telt
- And: een token als `S2b` telt wél, mits het in het veld staat

### S30 — Dubbele en onbekende ID's worden gemeld
**Dekt:** F13
- Given: een `TEST-SCENARIOS.md` met twee scenario's die hetzelfde ID dragen, en
  een `Dekt:`-token dat nergens oplost
- When: de offline controle draait
- Then: beide problemen worden apart gemeld, met ID
- And: een `PRD.md` zonder enig `F<n>` levert een **waarschuwing** op, geen harde fout

---

## Issue-templates en release

### S31 — Blocking-edges staan in beide issue-templates
**Dekt:** F14
- Given: `templates/ISSUE_TEMPLATE/work-item.md` en `epic.md`
- When: een issue vanuit het sjabloon wordt aangemaakt
- Then: beide bevatten een `**Blocked by:**`- en een `**Blocks:**`-veld
- And: de acceptatiecriteria zijn `AC<n>` genummerd, niet `S<n>`

### S32 — Elke actieve entry heeft een PR-linkback
**Dekt:** F15
- Given: `CHANGES.md` met een entry zonder `**PR:**`-veld
- When: `./check` draait
- Then: exit ≠ 0, met het ID van die entry in de melding

### S33 — De CHANGELOG noemt de vereiste handmatige acties
**Dekt:** F15
- Given: de eerste `CHANGELOG.md`-entry van deze release
- When: hij gelezen wordt
- Then: hij noemt zowel `adopt.sh` per project als `adopt.sh --user` per machine

### S34 — De README beschrijft de nieuwe structuur
**Dekt:** F16
- Given: `README.md` na deze release
- When: de inhoudstabel gelezen wordt
- Then: er staan rijen voor `skills/`, `hooks/`, `lib/`, `nfr/`, `test/`, `check`
  en `CHANGES-ARCHIEF.md`
- And: het aantal niet-functionele vragen staat op vijftien, niet vijf
