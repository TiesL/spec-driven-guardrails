# Testscenario's — <Projectnaam>

Doel: deze scenario's beschrijven het beoogde/waargenomen gedrag (zie
`PRD.md`). Ze zijn onafhankelijk van de gekozen technische oplossing en
beschrijven alleen waarneembaar gedrag.

Notatie: **Given / When / Then**.

Elk functionaliteitsitem uit `PRD.md` krijgt minstens één scenario voor het
verwachte gedrag én minstens één voor wat er misgaat: onverwachte invoer,
ontbrekende gegevens, of een afhankelijkheid die wegvalt. Alleen happy paths
beschrijven is de snelste manier om je te laten verrassen door productie.

---

## <Feature-gebied 1>

### S1 — <titel: het verwachte gedrag>
- Given: ...
- When: ...
- Then: ...

### S2 — <titel: wat er misgaat>
- Given: <onverwachte invoer, ontbrekende gegevens, of een afhankelijkheid die faalt>
- When: ...
- Then: <het waarneembare gedrag — een leesbare melding, een overgeslagen actie,
  een herstelbare toestand; niet "er gebeurt iets onduidelijks">
- And: <wat er níét gebeurt: geen halve schrijfactie, geen stille fout>
