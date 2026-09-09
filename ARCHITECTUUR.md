# Architectuurafweging — Installatiemodel voor een tweede gebruiker (W37, #79)

Dit document legt vast *waarom* het systeem is zoals het is. `PRD.md` beschrijft
wat het moet doen; hier staat welke structurele keuzes daaronder liggen, welke
alternatieven zijn afgewogen, en wanneer een keuze opnieuw tegen het licht moet.

Niet elk besluit hoort hier. Wel: platformkeuzes, de indeling in lagen of
componenten, waar gegevens eigenaar van zijn, en het toevoegen van een
substantiële dependency. Niet: hoe één functie is geschreven.

---

## Het besluit

**Besloten op 2026-09-09: een nieuw, git-only entrypoint `install.sh` pint een
checkout op een getagde release, los van `adopt.sh`.**

`install.sh` draait ná een handmatige `git clone`, vanuit die kloon zelf. Hij
valideert een schone werkmap, checkt een opgegeven (of anders de laatste) tag
uit, en meldt de `SPEC_DRIVEN_GUARDRAILS_DIR`-regel die de gebruiker in zijn
shell-profiel zet. Hij adopteert geen project — dat blijft `adopt.sh`'s taak.
Ties' eigen multi-machine-gebruik (clone, altijd `main` volgen) verandert niet:
dit is een tweede, expliciet gekozen pad, geen vervanging.

---

## Beoordelingscriteria

| Criterium | Waarom dit telt |
|---|---|
| Auditeerbaarheid | Dit repo's hele stijl is doorleesbare bash zonder verrassingen (geen `eval`, faal-open bij twijfel). Een installatiemechanisme dat daaraan tornt ondermijnt precies het vertrouwen dat de rest van het repo opbouwt. |
| Hergebruik boven nieuw bouwen | W29/#53 besluit 5 was expliciet: bouw op W22's bestaande tag-/`CHANGELOG.md`-mechanisme, vind niets opnieuw uit. |
| Scheiding van verantwoordelijkheden | "Deze checkout op versie X zetten" en "dit project aan die checkout koppelen" zijn twee verschillende vragen met verschillende faalmodi (een verkeerde tag vs. een verkeerd project) — vermengen maakt beide moeilijker te redeneren. |
| Passend bij de doelgroep | W37's "tweede gebruiker" is iemand die al Claude Code én git gebruikt (dezelfde workflow wordt geadopteerd) — geen behoefte aan een installatiemechanisme voor wie geen git heeft. |

---

## Afgewogen opties

### Optie 1 — Alleen documentatie, geen nieuw script
De consument leest een nieuwe README-sectie en voert de kloon-, checkout- en
env-var-stappen zelf handmatig uit. Kleinste voetafdruk, nul nieuwe code om te
onderhouden. Nadeel: drie handmatige stappen zijn drie plekken om een tag-naam
te verkeerd te typen of de env var te vergeten, zonder enige validatie
(bijvoorbeeld een vieze werkmap die stilzwijgend wordt overschreven door
`git checkout`).

### Optie 2 — Convenience-entrypoint `install.sh` (gekozen)
Automatiseert checkout + validatie or nadat de gebruiker al gekloond heeft.
Voegt precies twee nieuwe, toetsbare garanties toe die optie 1 niet geeft: een
vieze werkmap wordt geweigerd in plaats van overschreven, en een onbekende tag
faalt met een duidelijke melding in plaats van een cryptische git-foutmelding.

### Optie 3 — `curl | bash`-zelfinstallatie
Eén commando, geen voorafgaande kloon nodig. Afgewezen: voert externe code uit
zonder dat de gebruiker hem eerst leest — precies het patroon dat dit repo's
eigen guardrails (geen `eval`, expliciete faalpaden) elders bestrijden. Zou ook
een apart, klein hostingprobleem oplossen (waar staat het script vóór de kloon)
dat de andere opties niet hebben.

### Optie 4 — Gepakte release-artefacten (tarball/zip zonder git)
GitHub's automatische source-archief per tag zou dit deels gratis geven. Maar
de doelgroep heeft al git (zie criterium hierboven), en een apart
artefactformaat onderhouden voor een niet-bestaande behoefte is precies het
soort speculatieve bouwwerk dat dit repo's `rule-of-three`-principe elders
afwijst.

---

## Vergelijking en keuze

Optie 2 wint: het lost de twee concrete faalmodi op die optie 1 openlaat
(stille dataverlies bij een vieze werkmap, onduidelijke fouten bij een
verkeerde tag), zonder de auditeerbaarheid van optie 3 op te geven of de
speculatieve complexiteit van optie 4 te introduceren. Wat je ervoor inlevert:
een extra script om te onderhouden, en de consument moet nog steeds zelf
`git clone` kunnen — dat is bewust aanvaard, zie de doelgroep-aanname
hierboven.

---

## Architectuureisen die hieruit volgen

### A1 — Nooit schrijven op een vieze werkmap
`install.sh` controleert `git status --porcelain` vóór elke `git checkout` en
weigert bij niet-gecommitte wijzigingen. Geschonden wordt dit zichtbaar zodra
een toekomstige wijziging de checkout-stap vóór de vuil-check zet.

### A2 — `install.sh` roept `adopt.sh` nooit aan
De twee scripts hebben elk hun eigen faalmodus en hun eigen doelmap (de
gedeelde checkout zelf, respectievelijk een geadopteerd project). Ze
samenvoegen zou een fout in de ene stap onherkenbaar maken in de andere.

### A3 — Geen extern uitgevoerde code
`install.sh` haalt nooit code op om die vervolgens uit te voeren (geen
`curl | bash`, geen `eval` van opgehaalde inhoud). Alles wat draait, staat al
in de gekloonde checkout en is dus door de gebruiker leesbaar vóór het draait.

---

## Systeemgrenzen en eigenaarschap

- **`install.sh`** is eigenaar van "op welke versie staat déze checkout" — hij
  wijzigt uitsluitend git-state binnen de eigen map (`git fetch --tags`,
  `git checkout <tag>`).
- **`adopt.sh`** blijft eigenaar van "welk project is aan welke checkout
  gekoppeld" — ongewijzigd door dit besluit.
- De twee communiceren uitsluitend via `SPEC_DRIVEN_GUARDRAILS_DIR`, een
  omgevingsvariabele die de gebruiker zelf zet — geen directe aanroep tussen
  de scripts (zie A2).

---

## Dependencies

Geen nieuwe. `install.sh` gebruikt uitsluitend `git`, al een vereiste voor
elke checkout van dit repo.

---

## Wanneer we deze keuze zouden herzien

- Als W35 (#59) een doelgroep beschrijft die geen git heeft — dan wordt optie
  4 (of een variant) alsnog nodig, niet als vervanging maar als aanvulling.
- Als het aantal handmatige stappen vóór `install.sh` (kloon, `cd`, script
  uitvoeren) zelf een aantoonbare bron van fouten blijkt — dan is optie 3
  (met een expliciete, leesbare tussenstap, geen blinde `curl | bash`) het
  heroverwegen waard.

---

## Openstaand na dit document

- **Beslist (2026-09-09): geen formele GitHub Release voor de bestaande tag
  vóór epic #52 zelf afgerond is.** `install.sh` en de bare git-tag werken
  daar niet minder om — een release nu zou alleen een versie discoverable
  maken die nog niet is wat epic #52 belooft (nog niet vertaald, nog niet
  ingedikt, nog geen voorpagina). Een `gh release create` per toekomstige
  tag, met notities, blijft dus open totdat de laatste werkitems onder #52
  (W33-W35) landen — dan pas is er iets dat een tweede gebruiker ook echt
  zou moeten willen pinnen.
