#!/usr/bin/env bash
# S19 t/m S23 — adopt.sh installeert skills en beheert het .gitignore-blok.
# Dekt: F9
#
# Dit werkitem schrijft in andermans repo's en migreert een getrackte
# .gitignore. Alles hieronder draait tegen sandbox-fixtures; de vier echte
# projecten worden nooit aangeraakt.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# Een kopie van dit repo, zodat een test skills mag toevoegen zonder de echte
# checkout aan te raken.
bron="$(sandbox_copy_repo)"
mkdir -p "$bron/skills/pre-merge-review" "$bron/skills/tdd-seams"
echo "# review" > "$bron/skills/pre-merge-review/SKILL.md"
echo "# seams"  > "$bron/skills/tdd-seams/SKILL.md"

adopteer_uit() {
  SPEC_DRIVEN_GUARDRAILS_DIR="$1" "$1/adopt.sh" "$2" >/dev/null 2>&1
}

# Zelfde, maar met de uitvoer zichtbaar en de exitstatus bruikbaar.
adopteer_uit_luid() {
  SPEC_DRIVEN_GUARDRAILS_DIR="$1" "$1/adopt.sh" "$2"
}

# De markers zoals adopt.sh ze schrijft, uit het script zelf gelezen in plaats
# van hier overgeschreven - anders toetst deze test zijn eigen kopie.
GITIGNORE_BEGIN="$(sed -n 's/^GITIGNORE_BEGIN="\(.*\)"$/\1/p' "$bron/adopt.sh")"
GITIGNORE_EIND="$(sed -n 's/^GITIGNORE_EIND="\(.*\)"$/\1/p' "$bron/adopt.sh")"
[ -n "$GITIGNORE_BEGIN" ] && [ -n "$GITIGNORE_EIND" ] \
  || fail "S21 — de markers zijn niet uit adopt.sh te lezen"

# --- S19 -------------------------------------------------------------------
project="$(vers_project s19)"
adopteer_uit "$bron" "$project"

skills="$project/.claude/skills"
[ -d "$skills" ] || fail "S19 — .claude/skills is niet aangemaakt"
if [ -L "$skills" ]; then
  fail "S19 — .claude/skills is zelf een symlink, dat maakt de namespace eigendom van claude-workflow"
fi

for naam in pre-merge-review tdd-seams; do
  [ -L "$skills/$naam" ] || fail "S19 — $naam is geen symlink"
  doel="$(readlink "$skills/$naam")"
  case "$doel" in
    "$bron"/skills/*) ;;
    *) fail "S19 — $naam wijst naar $doel, niet naar de skills-map van het repo" ;;
  esac
done

# --- S20 -------------------------------------------------------------------
# Een verweesde symlink: wijst naar een skill die niet meer bestaat. Die is niet
# inert - Claude Code meldt er elke sessie een laadfout op, in vier projecten
# tegelijk.
mkdir -p "$skills"
ln -s "$bron/skills/verdwenen" "$skills/verdwenen"
mkdir -p "$skills/eigen-skill"
echo "# van het project zelf" > "$skills/eigen-skill/SKILL.md"
# En twee symlinks die het project zelf ergens anders heen legde: niet van ons,
# dus niet van ons om op te ruimen. De tweede is bewust dood - alleen die toont
# aan dat de prefixcontrole werkt. Wijst een vreemde link naar iets dat nog
# bestaat, dan beschermt niet de prefixcontrole hem maar het toeval.
mkdir -p "$SANDBOX/elders/vreemde-skill"
ln -s "$SANDBOX/elders/vreemde-skill" "$skills/vreemde-skill"
ln -s "$SANDBOX/elders/nooit-bestaan" "$skills/vreemde-dode-skill"

adopteer_uit "$bron" "$project"

if [ -e "$skills/verdwenen" ] || [ -L "$skills/verdwenen" ]; then
  fail "S20 — de verweesde symlink 'verdwenen' is blijven staan"
fi
[ -d "$skills/eigen-skill" ] || fail "S20 — de eigen map 'eigen-skill' is verwijderd"
[ -f "$skills/eigen-skill/SKILL.md" ] || fail "S20 — de inhoud van 'eigen-skill' is weg"
[ -L "$skills/vreemde-skill" ] || fail "S20 — een symlink buiten dit repo is opgeruimd; alleen onze eigen verweesde links mogen weg"
[ -L "$skills/vreemde-dode-skill" ] || fail "S20 — een dóde symlink buiten dit repo is opgeruimd; het criterium is de bestemming, niet of de link werkt"

# Een dode wees met een relatief pad. Zonder het pad eerst betekenisvol te maken
# valt hij buiten de prefixcontrole en blijft hij eeuwig staan - en dan meldt
# Claude Code er elke sessie een laadfout op.
ln -s "$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$bron/skills/ook-verdwenen" "$skills")" "$skills/relatieve-wees"
adopteer_uit "$bron" "$project"
if [ -e "$skills/relatieve-wees" ] || [ -L "$skills/relatieve-wees" ]; then
  fail "S20 — een verweesde symlink met een relatief pad is blijven staan"
fi

# --- S21 -------------------------------------------------------------------
# Het gevaarlijkste geval, naar het echte tennis-admin gemodelleerd: regels die
# geneste git-repo's uitsluiten. Verdwijnen die, dan ziet git ineens twee hele
# repo's als ongetrackte inhoud.
project="$(vers_project s21)"
cat > "$project/.gitignore" <<'IGNORE'
tennis-registration/
tennis-invoicing/
.DS_Store
CLAUDE.md
.claude/settings.json

# clasp-koppeling is machinespecifiek
.clasp.json
IGNORE
voor="$(cat "$project/.gitignore")"

adopteer_uit "$bron" "$project"
na="$project/.gitignore"

for regel in "tennis-registration/" "tennis-invoicing/" ".DS_Store" ".clasp.json"; do
  grep -qxF "$regel" "$na" || fail "S21 — de bestaande regel '$regel' is verdwenen uit .gitignore"
done
grep -q '^# clasp-koppeling is machinespecifiek$' "$na" \
  || fail "S21 — een commentaarregel buiten het blok is verdwenen"

# Witregels midden in het bestand scheiden groepen. Ze weggooien is precies het
# ongevraagd herschrijven van andermans .gitignore dat hier niet hoort - en het
# is geen theorie: een eerdere versie van dit script deed het, en alleen een
# droogdraai tegen een kopie van een echt project bracht dat aan het licht.
verwacht_kop="$(printf 'tennis-registration/\ntennis-invoicing/\n.DS_Store\n\n# clasp-koppeling is machinespecifiek\n.clasp.json')"
werkelijk_kop="$(sed -n '1,6p' "$na")"
[ "$werkelijk_kop" = "$verwacht_kop" ] \
  || fail "S21 — de inhoud buiten het blok is herschreven:
$werkelijk_kop"

# En het blok staat één keer, ook na de tweede run.
markers="$(grep -c '^# claude-workflow: begin' "$na")"
[ "$markers" -eq 1 ] || fail "S21 — het beheerde blok staat $markers keer, 1 verwacht"

for regel in "CLAUDE.md" ".claude/settings.json"; do
  aantal="$(grep -cxF "$regel" "$na")"
  [ "$aantal" -eq 1 ] || fail "S21 — '$regel' staat $aantal keer in .gitignore, 1 verwacht"
done

# En ze staan binnen het beheerde blok, niet als losse restanten erbuiten.
binnen="$(awk '/^# claude-workflow: begin/{i=1;next} /^# claude-workflow: eind/{i=0} i' "$na")"
for regel in "CLAUDE.md" ".claude/settings.json" ".claude/skills/"; do
  printf '%s\n' "$binnen" | grep -qxF "$regel" \
    || fail "S21 — '$regel' staat niet binnen het beheerde blok"
done

# --- S21b: randgevallen in de bestáánde .gitignore ------------------------
# De acht mutaties hierboven toetsen wat er misgaat als het script fout gebouwd
# wordt. Dit blok toetst de andere kant: wat er misgaat als de invoer een
# randgeval heeft. Daar zat de zwaarste bug.

# Een blok met alleen een beginmarker liet een eerdere versie alles daarna
# stilzwijgend wissen. Het bestand is getrackt; stil doorploegen is de duurste
# fout die dit script kan maken.
project="$(vers_project s21b-kapot)"
printf 'belangrijke-regel.txt\n%s\nCLAUDE.md\nregel-na-kapot-blok\n' "$GITIGNORE_BEGIN" > "$project/.gitignore"
voor="$(cat "$project/.gitignore")"
uitvoer="$(adopteer_uit_luid "$bron" "$project" 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "S21b — een kapot blok werd niet geweigerd"
[ "$(cat "$project/.gitignore")" = "$voor" ] \
  || fail "S21b — het bestand is aangeraakt terwijl het blok beschadigd was"
assert_contains "S21b — de melding legt uit wat er mis is" "corrupted managed block" "$uitvoer"

# Genest: twee beginmarkers vóór de eerste eindmarker. Tellen alleen is niet
# genoeg, want de aantallen kloppen dan.
project="$(vers_project s21b-genest)"
printf 'x\n%s\n%s\nCLAUDE.md\n%s\n%s\n' "$GITIGNORE_BEGIN" "$GITIGNORE_BEGIN" "$GITIGNORE_EIND" "$GITIGNORE_EIND" > "$project/.gitignore"
voor="$(cat "$project/.gitignore")"
adopteer_uit_luid "$bron" "$project" >/dev/null 2>&1
[ "$?" -ne 0 ] || fail "S21b — een genest blok werd niet geweigerd"
[ "$(cat "$project/.gitignore")" = "$voor" ] || fail "S21b — het geneste geval raakte het bestand toch aan"

# CRLF en trailing spaces: voor git dezelfde regel, voor een exacte vergelijking
# niet. Zonder normaliseren blijft de oude regel naast de nieuwe staan.
project="$(vers_project s21b-varianten)"
printf 'CLAUDE.md\r\nCLAUDE.md   \nnode_modules/\n   \n*.log\n' > "$project/.gitignore"
adopteer_uit "$bron" "$project"
aantal="$(grep -c 'CLAUDE.md' "$project/.gitignore")"
[ "$aantal" -eq 1 ] || fail "S21b — CLAUDE.md staat $aantal keer; CRLF- en spatie-varianten zijn niet gemigreerd"

# Een regel met alleen spaties houdt zijn spaties. awk splitst op witruimte, dus
# NF is daar nul - die als lege regel terugschrijven is een wijziging van
# inhoud buiten het blok.
grep -q '^   $' "$project/.gitignore" \
  || fail "S21b — een witregel met spaties is herschreven naar een lege regel"

# .claude/skills/ hoort in het blok: het zijn symlinks naar een absoluut pad op
# deze machine. Zonder deze regel verschijnt er na W9 in elk project een stapel
# ongetrackte bestanden.
grep -qxF '.claude/skills/' "$project/.gitignore" \
  || fail "S21b — .claude/skills/ staat niet in het beheerde blok"

# --- S22 -------------------------------------------------------------------
project="$(vers_project s22)"
adopteer_uit "$bron" "$project"
boom_een="$(cd "$project" && find . -not -path './.git/*' -not -name '.git' | sort)"
ignore_een="$(cat "$project/.gitignore")"

adopteer_uit "$bron" "$project"
boom_twee="$(cd "$project" && find . -not -path './.git/*' -not -name '.git' | sort)"
ignore_twee="$(cat "$project/.gitignore")"

[ "$boom_een" = "$boom_twee" ] || fail "S22 — de bestandsboom verschilt na de tweede run"
[ "$ignore_een" = "$ignore_twee" ] || fail "S22 — .gitignore verschilt na de tweede run"

# --- S23 -------------------------------------------------------------------
# Een checkout zonder skills/-map: de installer landt vóór de inhoud, dus dit is
# de normale toestand tot W9 klaar is.
kaal="$(sandbox_copy_repo kaal)"
rm -rf "$kaal/skills"
project="$(vers_project s23)"
uitvoer="$(SPEC_DRIVEN_GUARDRAILS_DIR="$kaal" "$kaal/adopt.sh" "$project" 2>&1)"; status=$?
[ "$status" -eq 0 ] || fail "S23 — adoptie zonder skills/ faalde met exit $status: $uitvoer"
if [ -e "$project/.claude/skills" ]; then
  fail "S23 — er is een lege .claude/skills achtergelaten"
fi
[ -L "$project/CLAUDE.md" ] || fail "S23 — de gewone adoptie werkte niet meer zonder skills/"

test_klaar "S19-S23"
