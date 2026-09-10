# Testscenario's — <Projectnaam>

Doel: deze scenario's beschrijven het beoogde/waargenomen gedrag (zie
`PRD.md`). Ze zijn onafhankelijk van de gekozen technische oplossing en
beschrijven alleen waarneembaar gedrag.

Notatie: **Given / When / Then**.

Elk scenario draagt een `**Covers:**`-veld direct onder zijn kop, met de
functionaliteit uit `PRD.md` die het scenario beschrijft. Komma-gescheiden bij
meer dan één, bijvoorbeeld `F3, F4`.

Elk token matcht `^[A-Z]{1,2}[0-9]+[a-z]?$`. Die staart-letter is geen
slordigheid maar bestaand gebruik — een project in gebruik heeft een `S2b`
tussen `S2` en `S3` — en twee beginletters komen ook voor (`OP4`). Een
grammatica die daar geen rekening mee houdt, wijst op dag één geldige ID's af.

Het prefix ligt niet vast. `F` voor functionaliteit en `S` voor scenario is
gebruikelijk, maar een project dat zijn scenario's `R`/`A`/`B`/`P` nummert werkt
ongewijzigd: de controle toetst dat een token oplost naar een bestaande kop,
niet welke letter ervoor staat. Alleen het veld telt — een ID in lopende tekst
is geen verwijzing.

Elk functionaliteitsitem uit `PRD.md` krijgt minstens één scenario voor het
verwachte gedrag én minstens één voor wat er misgaat: onverwachte invoer,
ontbrekende gegevens, of een afhankelijkheid die wegvalt. Alleen happy paths
beschrijven is de snelste manier om je te laten verrassen door productie.

---

## <Feature-gebied 1>

### S1 — <titel: het verwachte gedrag>
**Covers:** <F<n>>
- Given: ...
- When: ...
- Then: ...

### S2 — <titel: wat er misgaat>
**Covers:** <F<n>>
- Given: <onverwachte invoer, ontbrekende gegevens, of een afhankelijkheid die faalt>
- When: ...
- Then: <het waarneembare gedrag — een leesbare melding, een overgeslagen actie,
  een herstelbare toestand; niet "er gebeurt iets onduidelijks">
- And: <wat er níét gebeurt: geen halve schrijfactie, geen stille fout>
