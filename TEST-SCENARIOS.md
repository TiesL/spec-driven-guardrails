# Testscenario's — spec-driven-guardrails

Doel: deze scenario's beschrijven het beoogde/waargenomen gedrag (zie `PRD.md`).
Ze zijn onafhankelijk van de gekozen technische oplossing en beschrijven alleen
waarneembaar gedrag.

Notatie: **Given / When / Then**.

Elk scenario draagt een `**Dekt:**`-veld met de functionaliteit uit `PRD.md` die
het toetst — de conventie uit F13, besluit b, hier op dit repo zelf
toegepast. De prefixen zijn bewust gemengd: `R<n>` zijn de regressiescenario's uit het oorspronkelijke
issue #7, `T<n>` de traceabilityscenario's uit #8, `S<n>` de nieuwe. Dat is geen
slordigheid maar de proef op de som van F13, besluit c: de
integriteitscontrole mag geen prefix hardcoderen.

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

### R6 — Predicaatgedrag identiek én aantoonbaar juist
**Dekt:** F3
- Given: vier testprojecten (met/zonder `package.json` × met/zonder `"deploy"`-script)
- When: de seed-logica en `van_toepassing()` beide `heeft-package-json` en
  `heeft-deploy-script` evalueren tegen elk van de vier
- Then: beide komen voor elke combinatie tot exact hetzelfde antwoord
- And: voor **elk** predicaat bestaat minstens één geval waarin het waar is én de
  bijbehorende entry onbeantwoord — anders is een té streng geworden predicaat
  onzichtbaar, omdat het verschil dan nergens in een openstaand-set landt
- And: de uitkomst per combinatie is expliciet vastgelegd, niet alleen onderling
  vergeleken; twee identiek kapotte predicaten zijn het met elkaar eens en zouden
  een zuivere gelijkheidstest passeren
- And: wat `adopt.sh` daadwerkelijk seedt wordt **rechtstreeks** tegen de
  vastgelegde uitkomst gehouden, niet alleen via een vereniging met de
  openstaand-set. Een vereniging kan alleen zien dat er te véél geseed is: wat
  `adopt.sh` mist, blijft gewoon openstaan en valt daardoor weg tegen elkaar

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

### S66 — De bron van de vraagset is volledig ingevroren, ook het nfr-deel
**Dekt:** F2
- Given: de nulmeting-fixtures, ná W28
- When: een gouden set wordt nagerekend
- Then: elk `spec-*`-ID erin is te herleiden tot een ingevroren bestand in
  `test/fixtures/nulmeting/nfr.momentopname/`, verbatim gelijk aan
  `CHANGES.md.momentopname`'s vorm
- And: geen enkel ID hangt alleen af van de actuele, niet-ingevroren vorm van
  `nfr/`

### S67 — Een wijziging in het nfr-register die de vraagset raakt, valt op
**Dekt:** F2
- Given: een `nfr/`-bestand met `van-toepassing-als: altijd` wordt toegevoegd
  (alle vijftien bestaande dragen dat predicaat, dus raakt elke toevoeging,
  verwijdering of retirement per definitie alle vier de fixtures)
- When: `pending-changes.sh` na die wijziging tegen een fixture draait
- Then: de uitkomst wijkt af van de ingevroren gouden set, met het nieuwe ID
  benoemd — R9 vangt dit al, aangetoond met een mutatie
- And: dat verschil is niet op te lossen door alleen de gouden set aan te
  passen: `nfr.momentopname` moet dan bewust meeveranderen, met toelichting in
  de PR (zie `LEESMIJ.md`)

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
- And: ontbreken `jq` én `python3`, dan faalt `check` alsnog — hij kan het
  bestand dan niet verifiëren en mag dus niet "in orde" melden

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

### S38 — Een veld zonder voorafgaande kop levert geen entry
**Dekt:** F3
- Given: een misvormde bron waarin een `Van toepassing als`-veld staat vóór de
  eerste `## `-kop
- When: `itereer_entries` die bron leest
- Then: er wordt geen callback aangeroepen voor dat veld — een entry zonder ID
  zou anders als lege rij in een adoptietabel belanden
- And: de entries ná de eerste kop worden gewoon verwerkt
- And: hetzelfde geldt via `adopt.sh` zelf, niet alleen via de bibliotheek
  rechtstreeks: de adoptietabel bevat geen rij met een leeg ID

### S37 — Predicaat- en parserlogica staat op precies één plek
**Dekt:** F3
- Given: `lib/changes.sh` bevat de predicaten en het parserskelet
- When: `adopt.sh` en `pending-changes.sh` worden doorzocht
- Then: geen van beide bevat nog een eigen `heeft-*`-tak of een eigen
  `## `-koploper — ze sourcen de bibliotheek
- And: de bibliotheek bevat ze wél, zodat de test faalt als hij leeggehaald wordt
  in plaats van alleen bij terugkerende duplicatie
- And: beide scripts roepen `predicaat_waar` uit de bibliotheek **daadwerkelijk
  aan** — vastgesteld door de functie te instrumenteren en te draaien, niet door
  op tekst te zoeken. Een tekstmatch ziet alleen letterlijke kopieën; logica die
  in een andere vorm is herschreven glipt er ongemerkt doorheen

### S36 — Een ID in de toelichting telt niet als antwoord
**Dekt:** F3
- Given: een `WORKFLOW-ADOPTIE.md` waarin het ID van een nog onbeantwoorde
  wijziging voorkomt in de vrije toelichtingstekst van een ándere rij
- When: `pending-changes.sh` draait
- Then: die wijziging staat nog steeds open — alleen de ID-kolom telt als antwoord
- And: toelichtingen zijn vrije tekst en ID's als `test-integratie` zijn gewone
  woorden, dus een onverankerde match zou stilzwijgend vragen laten verdwijnen

---

## NFR-register en archief (vervolg)

### S5 — Generator en ingecheckt sjabloon lopen niet uit de pas
**Dekt:** F4
- Given: een `nfr/*.md` waarvan de `Invulhulp` gewijzigd is zonder
  `templates/PRD.md` te regenereren
- When: `./check` draait
- Then: exit ≠ 0, met de betreffende NFR in de melding

### S39 — Een geretireerd kenmerk verdwijnt uit beide consumenten
**Dekt:** F4
- Given: een `nfr/*.md` met `status: geretireerd`
- When: `pending-changes.sh` draait en het sjabloonblok wordt gegenereerd
- Then: het kenmerk wordt niet meer gevraagd en staat niet meer in het blok
- And: na regenereren klaagt `check` niet — retirement is hier een veld, geen
  verhuizing, en dat moet aan beide kanten doorwerken

### S40 — De volgorde van het sjabloonblok ligt vast
**Dekt:** F4
- Given: het `volgorde`-veld bepaalt waar een kenmerk in het blok staat
- When: het blok in een andere volgorde wordt gegenereerd dan wat is ingecheckt
- Then: `check` faalt — een vergelijking die op ID sorteert ziet dat verschil
  niet, dus de volgorde wordt apart getoetst

### S41 — Een kapot registerbestand valt niet stil weg
**Dekt:** F4
- Given: een `nfr/*.md` waarin een verplicht veld ontbreekt of onbruikbaar is
  (geen `volgorde`, CRLF-regeleinden, een naam die niet bij het `id` past)
- When: `./check` draait
- Then: exit ≠ 0, met het bestand en het ontbrekende veld in de melding
- And: dat is niet af te vangen met de driftcontrole alleen — een kenmerk dat uit
  het register valt, verdwijnt uit álle consumenten tegelijk, en dan zijn beide
  kanten van die vergelijking het gewoon met elkaar eens

### S42 — Elke gemelde wijziging toont de vraag uit zijn eigen bron
**Dekt:** F4
- Given: de openstaande wijzigingen van een project, uit `CHANGES.md` én `nfr/`
- When: `pending-changes.sh` draait
- Then: elke regel toont de vraagtekst die bij dat ID in zijn bron staat
- And: een verminkte of lege tekst wordt gevangen — een vergelijking op alleen
  ID's ziet dat niet, terwijl het wél is wat de gebruiker leest

### S6 — Een entry zonder `Van toepassing als` levert een waarschuwing
**Dekt:** F5
- Given: `CHANGES.md` met een `## `-kop zonder `Van toepassing als`-veld, terwijl
  de sectiescheidingen naar `###` zijn omgezet
- When: de gedeelde parser die bron leest
- Then: er verschijnt een waarschuwing die het ID noemt
- And: de entry wordt niet geseed of gevraagd — een waarschuwing blokkeert niets
- And: dat geldt ook wanneer de kapotte entry ná een goede komt, en wanneer hij
  de laatste in het bestand is — de parserstand mag niet van de vorige entry
  blijven hangen
- And: een bron zonder afsluitende newline verliest zijn laatste regel niet;
  anders wordt een entry stilzwijgend overgeslagen mét een misleidende melding

---

## Onderbouwingsplicht en poorten

### S43 — Een gezonde bron levert niets op stderr
**Dekt:** F6
- Given: een geadopteerd project met een goed gevormde `WORKFLOW-ADOPTIE.md` —
  met wachtende onderbouwingen, zonder, of zonder tabel
- When: `pending-changes.sh` draait
- Then: er komt niets op stderr
- And: dit is geen cosmetische eis. De SessionStart-hook stuurt stderr naar
  `/dev/null` en elke testaanroep deed dat ook, waardoor een shellfout in het
  script structureel onzichtbaar bleef — inclusief één die in drie van de vier
  echte projecten dagelijks afging

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

### S44 — De hookbedrading laat de blokkade door
**Dekt:** F7
- Given: een project waarvan `.claude/settings.json` naar dit repo symlinkt
- When: de geconfigureerde `PreToolUse`-opdracht een te blokkeren commando krijgt
- Then: exitstatus 2 komt eruit — de guard blokkeert daadwerkelijk
- And: de vorm `[ -x … ] && … || exit 0` doet dat níét: de `||` vangt exit 2 op
  en meldt succes, waarmee de guard stil uit staat terwijl hij geïnstalleerd
  lijkt. Daarom `if … then exec … fi; exit 0`

### S47 — Committen op `main` wordt geblokkeerd, met een begaanbare uitweg
**Dekt:** F7
- Given: `main` is uitgecheckt in een repo die al commits heeft
- When: `git commit` wordt aangeroepen
- Then: het wordt geblokkeerd, en de melding noemt `git checkout -b` én dat de
  wijzigingen gewoon meegaan
- And: dat laatste is geen beleefdheid maar noodzaak — zonder die uitweg blijft
  het werk ongecommit, en dat is onveiliger dan de lokale commit die je net
  tegenhield
- And: op een feature-branch gaat committen gewoon door
- And: een repo zonder commits is de uitzondering: de allereerste commit van een
  nieuw project staat per definitie op `main`, en die stap staat zo in
  `WORKFLOW.md`

### S45 — Tekst binnen quotes is data, geen commando
**Dekt:** F7
- Given: een commando met een `;`, `|` of `&` binnen een gequote string, of met
  een heredoc waarvan de body met `git` begint
- When: de guard het beoordeelt
- Then: het gaat door — de inhoud van een string of heredoc is data
- And: een gequote vlag telt juist wél mee: `git reset "--hard"` is hetzelfde
  commando als zonder quotes. Beide eisen tegelijk kunnen alleen met echte
  quote-bewuste tokenisatie; quoted spans maskeren lost het eerste op en maakt
  het tweede permanent onmogelijk

### S46 — De branch wordt bepaald in de repo waar het commando over gaat
**Dekt:** F7
- Given: `git -C <pad> push origin HEAD`, waarbij `<pad>` een andere repo is dan
  de map waar de sessie staat
- When: de guard de huidige branch bepaalt
- Then: hij kijkt naar de repo uit `-C`, niet naar de sessiemap
- And: `--git-dir` en `--work-tree` tellen net zo mee, en git rekent zelf uit hoe
  ze zich verhouden — de guard herimplementeert die regels niet
- And: bestaat dat pad niet of is het geen repo, dan komt er geen branch uit en
  wordt er niet geblokkeerd

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

### S64 — De merge-guard-uitweg schakelt alleen de merge-guard uit
**Dekt:** F8
- Given: hetzelfde commandosegment bevat zowel
  `CLAUDE_WORKFLOW_MERGE_GUARD_UIT=1` als een destructief git-commando
  (bijvoorbeeld `git reset --hard`)
- When: dat segment beoordeeld wordt
- Then: het destructieve git-commando wordt nog steeds geblokkeerd
- And: de uitweg schakelt uitsluitend de merge-guard uit, niet de rest van
  git-guardrails — anders is de luide, gerichte uitweg uit AC6 in de praktijk
  een blanco vrijbrief voor het hele segment

### S65 — Waardevlaggen van `gh pr merge` schuiven het doel niet op
**Dekt:** F8
- Given: `gh pr merge --body "een tekst met woorden" --subject "titel"` zonder
  expliciet PR-nummer/url/branch
- When: de merge-guard het doel bepaalt
- Then: hij vraagt de PR van de huidige branch op (`gh pr view` zonder
  argument), niet `gh pr view "een tekst met woorden"`
- And: een marker-loze PR wordt dus nog steeds geblokkeerd, in plaats van via
  het faal-openpad (een mislukte opvraging van een niet-bestaande "PR" met die
  naam) alsnog toegelaten te worden

### S73 — Merge wordt geblokkeerd als CI niet groen is
**Dekt:** F8
- Given: een PR met de review-marker, maar met een check die faalt
- When: `gh pr merge` wordt aangeroepen
- Then: het commando wordt geblokkeerd, met de naam van de falende check in de
  melding

### S74 — Merge gaat door als alle checks slagen
**Dekt:** F8
- Given: een PR met de review-marker en alle checks `pass`
- When: `gh pr merge` wordt aangeroepen
- Then: het commando gaat door

### S75 — Geen gerapporteerde checks blokkeert niet
**Dekt:** F8
- Given: een PR met de review-marker, maar zonder gerapporteerde checks (geen
  CI geadopteerd voor dat project, zie F6)
- When: `gh pr merge` wordt aangeroepen
- Then: het commando gaat door — geen checks is geen rode vlag

### S76 — De CI-controle faalt open als de opvraging zelf mislukt
**Dekt:** F8
- Given: een PR met de review-marker, maar de CI-opvraging zelf mislukt (geen
  netwerk, geen toegang)
- When: `gh pr merge` wordt aangeroepen
- Then: er verschijnt een luide waarschuwing dat de CI-controle is
  overgeslagen
- And: het commando wordt toegestaan

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

### S68 — `tdd-seams` benoemt de discipline concreet, niet aansporend
**Dekt:** F10
- Given: `skills/tdd-seams/SKILL.md`
- When: hij gelezen wordt
- Then: hij noemt "seam", "rood" én "groen" (rood-vóór-groen), en de drie
  anti-patronen met naam: implementatie-gekoppeld, tautologisch, en
  horizontaal slicen tegenover verticale slices

### S69 — `diagnose-bug` beschrijft de dwingende volgorde
**Dekt:** F10
- Given: `skills/diagnose-bug/SKILL.md`
- When: hij gelezen wordt
- Then: reproductie, hypotheses en regressietest staan er alle drie in, in die
  volgorde vóór de fix
- And: het staat er expliciet bij dat hypotheses getoond worden vóórdat ze
  getest worden

### S70 — `CONTEXT.md` wordt gescaffold zodra de rij op `ja` staat
**Dekt:** F10
- Given: een project waarvan `WORKFLOW-ADOPTIE.md` `proces-context-document`
  op `ja` heeft staan
- When: `adopt.sh` draait
- Then: `CONTEXT.md` wordt aangemaakt vanuit `templates/CONTEXT.md`, als het
  nog niet bestaat
- And: een al bestaand `CONTEXT.md` wordt nooit overschreven
- And: staat de rij op `nee` of ontbreekt ze, dan scaffoldt `adopt.sh` niets

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
- Then: voor kwaliteitsreview, onderbouwingsplicht, deploy-guards en
  adoptieregistratie — die zíjn verplaatst — levert elke term een Wegwijzer-rij
  op die naar precies één bestaande skill verwijst
- And: twee termen die in dezelfde skill landen krijgen twee eigen rijen
- And: branching is niet verplaatst (F12 houdt branchstrategie in de kern) en
  lost dus op zoals R7 dat toestaat: direct in het bestand, zonder
  Wegwijzer-rij

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

### S62 — Zonder dekkingsvelden waarschuwt de controle, en handhaaft niet
**Dekt:** F13
- Given: een project waarvan geen enkel scenario een `**Dekt:**`-veld draagt —
  alle vier de bestaande projecten zijn dit geval op de dag van invoering
- When: de offline controle draait
- Then: er verschijnt een waarschuwing en exit 0
- And: er wordt geen enkel ongedekt item gemeld. Zonder die uitzondering klaagt
  de controle bij invoering in één klap over álles, en dat is de retrofit die
  het ontwerp juist vermijdt
- And: zodra het eerste `**Dekt:**`-veld er staat, handhaaft hij wél — anders kan
  één verwijzing de rest ongestraft laten liggen

### S63 — De controle wordt gescaffold en draait in een vers project
**Dekt:** F13
- Given: een project dat `adopt.sh` voor het eerst draait
- When: de adoptie klaar is
- Then: `check-traceability.sh` staat er, uitvoerbaar
- And: hij draait daar zonder te falen — een scaffold die meteen rood staat,
  wordt bij de eerste aanraking uitgezet
- And: een eigen versie van dat bestand wordt niet overschreven

### S71 — Bestaande projecten krijgen de schakel-3-vraag alsnog voorgelegd
**Dekt:** F13
- Given: een project met een `package.json` en een al bestaande `ci.yml` die
  `check-pr-issue-link.sh` niet aanroept (W19b's `scaffold_if_missing` laat
  zo'n bestand ongemoeid — het sjabloon repareren helpt alleen nieuwe
  projecten, zelfde patroon als `ci-op-pr-en-main` bij W24)
- When: `pending-changes.sh` draait
- Then: een nieuwe entry verschijnt als openstaand
- And: een project zonder `package.json` krijgt die vraag niet

---

## Issue-templates en release

### S31 — Blocking-edges staan in beide issue-templates
**Dekt:** F14
- Given: `templates/ISSUE_TEMPLATE/work-item.md` en `epic.md`
- When: een issue vanuit het sjabloon wordt aangemaakt
- Then: beide bevatten een `**Blocked by:**`- en een `**Blocks:**`-veld, aan
  regelbegin en in de `**Veld:**`-vorm die de bestaande issues gebruiken
- And: een variant als `- Blocked by:` telt niet — die leest voor een mens
  hetzelfde en is voor een grep iets anders, en dan levert de conventie geen
  graaf op maar een gevoel
- And: een project met een verouderd sjabloon krijgt het nieuwe bij de
  eerstvolgende adoptie

### S60 — Acceptatiecriteria in het sjabloon heten `AC<n>`
**Dekt:** F13
- Given: `templates/ISSUE_TEMPLATE/work-item.md`
- When: een issue vanuit het sjabloon wordt aangemaakt
- Then: de acceptatiecriteria zijn `AC<n>` genummerd, niet `S<n>`
- And: zolang een issue zijn eigen criteria `S1` noemt, raakt elke `grep` naar
  scenarioverwijzingen het issue zelf — dan is schakel 2 niet controleerbaar
- And: dit scenario hoort bij W18 en wacht op de uitkomst van W17; valt die
  hernoeming anders uit, dan verandert dit scenario mee
- And: dit dekt **F13**, niet F14. De ongesplitste S31 droeg `Dekt: F14` voor
  beide claims, maar F13 punt a is de plek waar de `AC<n>`-hernoeming besloten
  wordt; F14 gaat uitsluitend over de blocking-edges
- And: `S<n>` mag in het sjabloon alleen nog voorkomen als verwijzing naar
  `TEST-SCENARIOS.md`, niet als eigen nummering

### S61 — Het scenariosjabloon draagt het dekkingsveld en de grammatica
**Dekt:** F13
- Given: `templates/TEST-SCENARIOS.md`
- When: een project ermee scaffoldt
- Then: elk voorbeeldscenario toont een `**Dekt:**`-veld direct onder de kop
- And: de tokengrammatica `^[A-Z]{1,2}[0-9]+[a-z]?$` staat er expliciet bij, met
  `S2b` als voorbeeld — een sjabloon dat de vorm voordoet zonder hem te benoemen
  leert de uitzondering niet aan, en dan strandt de eerste `S2b` op een
  handhaving die niemand had zien aankomen
- And: het sjabloon toont het veld met een placeholder, niet met een verzonnen
  ID dat nergens op slaat

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

### S35 — `check` meldt wat hij niet heeft kunnen controleren
**Dekt:** F1
- Given: een bestand dat `check` zou moeten onderzoeken maar niet kan lezen
  (bijvoorbeeld een script zonder leesrechten)
- When: `./check` draait
- Then: er verschijnt een waarschuwing die het bestand noemt
- And: het bestand verdwijnt niet stilzwijgend uit de controle — stille
  degradatie is de faalmodus die dit repo het duurst betaalt

---

## Issue-templates en release (vervolg)

### S34 — De README beschrijft de nieuwe structuur
**Dekt:** F16
- Given: `README.md` na deze release
- When: de inhoudstabel gelezen wordt
- Then: er staan rijen voor `skills/`, `hooks/`, `lib/`, `nfr/`, `test/`, `check`
  en `CHANGES-ARCHIEF.md`
- And: het aantal niet-functionele vragen staat op vijftien, niet vijf

---

## Dekking buiten de agentic loop

### S48 — Het CI-sjabloon valideert pull requests en `main`
**Dekt:** F17
- Given: een project dat met `templates/ci.yml` scaffoldt
- When: er een pull request wordt geopend en er naar `main` wordt gepusht
- Then: de workflow draait in beide gevallen
- And: hij roept nog steeds uitsluitend `check` aan — de CI-conventie zelf
  verandert niet, alleen wanneer hij afgaat

### S49 — Een eigen `ci.yml` wordt niet overschreven
**Dekt:** F17
- Given: een project met een handgeschreven `ci.yml` die afwijkt van het sjabloon
- When: `adopt.sh` opnieuw draait
- Then: dat bestand blijft ongemoeid — `scaffold_if_missing` schrijft alleen wat
  ontbreekt
- And: de afwijking blijft niet onzichtbaar. De adoptieregistratie stelt de vraag
  `ci-op-pr-en-main`, en blijft die stellen tot het project hem beantwoordt. Dat
  is het mechanisme, niet een melding in `adopt.sh` die één keer voorbijkomt en
  daarna weg is

### S50 — De guard geldt ook buiten Claude om
**Dekt:** F17
- Given: een geadopteerd project met `main` uitgecheckt en de git-hooks
  geïnstalleerd
- When: `git commit` of `git push origin main` rechtstreeks in een shell wordt
  aangeroepen, dus zonder tussenkomst van Claude
- Then: het wordt geweigerd, met dezelfde melding als de `PreToolUse`-guard
- And: de *regel* staat maar op één plek — welke branch beschermd is en wat de
  melding zegt, komt uit dezelfde bron als de `PreToolUse`-guard. De inleeslaag
  verschilt noodzakelijk: een native `pre-commit` krijgt geen commandostring om
  te tokeniseren

### S51 — Een bestaande git-hook wordt niet stilzwijgend vervangen
**Dekt:** F17
- Given: een project met een eigen `pre-commit`-hook die niet van dit repo komt
- When: `adopt.sh` draait
- Then: die hook wordt niet overschreven zonder melding
- And: twee keer draaien geeft een identieke boom — hooks stapelen niet

### S52 — Een commit op `main` buiten een PR om wordt gemeld
**Dekt:** F17
- Given: een commit die rechtstreeks naar `main` is gepusht
- When: de CI-workflow draait
- Then: hij faalt, met de betreffende commit in de melding
- And: een merge-commit die wél uit een pull request komt laat hij door
- And: de controle geldt zowel in `spec-driven-guardrails` zelf als in elk project dat
  met `templates/ci.yml` scaffoldt — een regel die dit repo aan anderen oplegt
  maar zelf ontloopt, is geen regel

### S53 — De controle beoordeelt de push, niet de historie
**Dekt:** F17
- Given: eerdere commits op `main` die niet aan de eis voldoen
- When: de workflow op een nieuwe push draait
- Then: alleen die push wordt beoordeeld
- And: de controle staat dus niet op dag één rood — een retrofit die altijd
  faalt leert je precies één ding, en dat is de melding negeren

### S58 — Een git-hook die zijn oordeel niet kan vellen, laat door
**Dekt:** F17
- Given: een geadopteerd project waarin de git-hook zijn beslislogica niet kan
  uitvoeren — het bronscript ontbreekt, of de vereiste interpreter is er niet
- When: `git commit` of `git push` wordt aangeroepen
- Then: er verschijnt een luide waarschuwing die zegt dat de controle níét is
  uitgevoerd
- And: het commando gaat door, net als bij S14 — een kapotte guard mag nooit het
  werk blokkeren, en zeker niet buiten Claude om, waar geen agent meekijkt die
  de melding kan duiden

### S59 — Een CI-controle die zijn oordeel niet kan vellen, faalt
**Dekt:** F17
- Given: de workflow uit S52 kan de herkomst van een push naar `main` niet
  vaststellen (geen API-antwoord, ontbrekende rechten)
- When: de controle draait
- Then: hij faalt, met de reden erbij
- And: dat is bewust het omgekeerde van S58. Een lokale hook die faalt houdt
  werk tegen dat allang legitiem kan zijn; een CI-controle die stil groen wordt
  meldt dat er niets aan de hand is terwijl hij niets weet — en dat is precies
  de stille degradatie die dit repo het duurst betaalt

### S72 — Bestaande projecten krijgen de main-via-PR-vraag alsnog voorgelegd
**Dekt:** F17
- Given: een project met een `package.json` en een al bestaande `ci.yml` die
  `check-main-via-pr.sh` niet aanroept (`scaffold_if_missing` laat zo'n
  bestand ongemoeid — zelfde patroon als `ci-schakel-3-hard-slot` bij W19b)
- When: `pending-changes.sh` draait
- Then: een nieuwe entry verschijnt als openstaand
- And: een project zonder `package.json` krijgt die vraag niet

### S80 — De check-job heeft leestoegang tot pull requests
**Dekt:** F17
- Given: `templates/ci.yml` en dit repo's eigen `.github/workflows/ci.yml`
- When: op beide bestanden gecontroleerd wordt welke tokenscope de `check`-job
  krijgt
- Then: `pull-requests: read` geldt voor die job, op job- of workflow-niveau
- And: zonder die scope draait `check-pr-issue-link.sh` (schakel 3) en
  `check-main-via-pr.sh` onder het default, minimale tokenscope, en falen
  beide — niet incidenteel, zoals issue #83 en #85 allebei lieten zien

---

## Zelf-adoptie

### S81 — spec-driven-guardrails kan zichzelf adopteren
**Dekt:** F7, F8
- Given: een sandboxkopie van dit repo, gebruikt als zowel
  `SPEC_DRIVEN_GUARDRAILS_DIR` als adoptiedoel
- When: `adopt.sh` daartegen draait
- Then: hij adopteert daadwerkelijk — `CLAUDE.md` en `.claude/settings.json`
  zijn symlinks naar zijn eigen `WORKFLOW.md` en
  `settings/session-hooks.json` — in plaats van de weigering "geen adoptie
  nodig" te tonen
- And: geen enkel bestaand, gecommit bestand (`PRD.md`, `TEST-SCENARIOS.md`,
  `check`, ...) verandert
- And: de git-guardrails-hook is daarna functioneel: een gefabriceerde
  `PreToolUse`-aanroep die een directe `git push origin main` voorstelt,
  wordt geweigerd — dezelfde controle die geadopteerde projecten krijgen
- And: de native git-hooks zijn ook geïnstalleerd en weigeren een directe
  `git push origin main` buiten Claude Code om (zelfde patroon als S50)
- And: een tweede `adopt.sh`-aanroep is idempotent — geen fouten, geen
  dubbele `.gitignore`-regels

---

## Werk veiligstellen zonder sessie-einde

### S54 — Sessiestart meldt dat `main` is uitgecheckt
**Dekt:** F18
- Given: een geadopteerd project met `main` uitgecheckt
- When: een sessie start
- Then: er verschijnt een melding die `main` noemt en `git checkout -b` voorstelt
- And: dat is vóór er werk is — de commit-blokkade uit F7 grijpt pas erna, als
  vertakken niet meer gratis voelt

### S55 — Op een feature-branch meldt de sessiestart niets
**Dekt:** F18
- Given: hetzelfde project op `feature/<naam>`
- When: `pending-changes.sh` draait
- Then: er verschijnt geen melding over de branch
- And: exit 0 en niets op stderr, conform S43 — een hook die ruis produceert
  wordt weggeklikt en daarmee waardeloos

### S56 — Een geslaagde commit is meteen gepusht
**Dekt:** F18
- Given: een feature-branch met een nieuwe commit
- When: de commit slaagt
- Then: de huidige branch staat op `origin`
- And: het werk is daarmee veilig zodra het is vastgelegd, in plaats van pas bij
  een nette afsluiting — waarvoor `SessionEnd` geen garantie geeft

### S57 — Een mislukte commit of ontbrekend netwerk pusht niets
**Dekt:** F18
- Given: een `git commit` die faalt (niets te committen, afgebroken editor), of
  een omgeving zonder verbinding of zonder `origin`
- When: de hook draait
- Then: er wordt niet gepusht, en op `main` gebeurt sowieso niets
- And: de hook meldt het en houdt het werk niet op — een push die niet lukt mag
  nooit een commando blokkeren
