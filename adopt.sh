#!/usr/bin/env bash
# adopt.sh — Adopteer de gedeelde claude-workflow in een project, of zet de
# userbrede adoptievraag-trigger op (--user).
#
# Gebruik:
#   ./adopt.sh                 # adopteert de workflow in de huidige directory
#   ./adopt.sh /pad/naar/proj   # adopteert de workflow in de opgegeven directory
#   ./adopt.sh --user           # zet ~/.claude/CLAUDE.md symlink (eenmalig per machine)
#
# Vereist: omgevingsvariabele CLAUDE_WORKFLOW_DIR, wijzend naar de lokale
# checkout van dit repo op déze machine (zie README.md).

set -euo pipefail

if [ -z "${CLAUDE_WORKFLOW_DIR:-}" ]; then
  echo "Fout: CLAUDE_WORKFLOW_DIR is niet ingesteld." >&2
  echo "Zet dit eenmalig in je shell-profiel, bijv.:" >&2
  echo "  export CLAUDE_WORKFLOW_DIR=\"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)\"" >&2
  exit 1
fi

if [ ! -f "$CLAUDE_WORKFLOW_DIR/WORKFLOW.md" ]; then
  echo "Fout: CLAUDE_WORKFLOW_DIR ('$CLAUDE_WORKFLOW_DIR') bevat geen WORKFLOW.md — klopt het pad?" >&2
  exit 1
fi

# De bibliotheek komt uit de checkout waar dít script in staat, niet uit
# CLAUDE_WORKFLOW_DIR: code hoort bij het script dat hem aanroept. De data
# (CHANGES.md, templates) komt wél uit CLAUDE_WORKFLOW_DIR, zoals altijd.
eigen_map="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/changes.sh
. "$eigen_map/lib/changes.sh"
# shellcheck source=lib/nfr.sh
. "$eigen_map/lib/nfr.sh"

backup_if_real_file() {
  local path="$1"
  if [ -e "$path" ] && [ ! -L "$path" ]; then
    echo "Bestaand bestand gevonden op $path — back-up naar $path.bak"
    mv "$path" "$path.bak"
  elif [ -L "$path" ]; then
    rm "$path"
  fi
}

scaffold_if_missing() {
  local template="$1" target="$2"
  if [ ! -e "$target" ] && [ -f "$template" ]; then
    cp "$template" "$target"
    echo "Aangemaakt vanuit template: $target"
  fi
}

copy_issue_templates() {
  local project_dir="$1"
  local template_src="$CLAUDE_WORKFLOW_DIR/templates/ISSUE_TEMPLATE"
  if [ -d "$template_src" ]; then
    mkdir -p "$project_dir/.github/ISSUE_TEMPLATE"
    cp -f "$template_src"/*.md "$project_dir/.github/ISSUE_TEMPLATE/"
    [ -f "$template_src/config.yml" ] && cp -f "$template_src/config.yml" "$project_dir/.github/ISSUE_TEMPLATE/"
    echo "Issue-templates gekopieerd naar $project_dir/.github/ISSUE_TEMPLATE/"
  fi
}

# Callback voor itereer_entries. De invoer komt via _seed_*-globals in plaats
# van via dynamische scope, zodat zichtbaar is waar hij vandaan komt.
#
# `standaard: vraag` wordt hier overgeslagen: die entries worden nooit
# automatisch beantwoord. pending-changes.sh negeert datzelfde veld juist — zie
# de callback daar. Die asymmetrie is bewust en staat daarom bij beide
# aanroepers, niet verstopt in lib/changes.sh.
seed_entry() {
  local id="$1" standaard="$2" predicaat="$3"
  if [ "$standaard" = "vraag" ]; then
    return 0
  fi
  if ! predicaat_waar "$predicaat" "$_seed_project_dir"; then
    return 0
  fi
  echo "| $id | ja | $_seed_vandaag | bij adoptie — vereist onderbouwing tijdens PRD/architectuur |" >> "$_seed_doel"
}

# Legt bij adoptie vast dat dit project akkoord is met de huidige staat van de
# workflow: elke nú van toepassing zijnde wijziging krijgt "ja". Wat niet van
# toepassing is krijgt geen rij en wordt later alsnog gevraagd zodra de conditie
# waar wordt (zie pending-changes.sh).
seed_adoptietabel() {
  local project_dir="$1"
  local doel="$project_dir/WORKFLOW-ADOPTIE.md"
  local changes="$CLAUDE_WORKFLOW_DIR/CHANGES.md"

  [ -e "$doel" ] && return 0
  [ -f "$changes" ] || return 0

  {
    echo "# Adoptie van gedeelde workflow-wijzigingen"
    echo
    echo "Per wijziging uit \`CHANGES.md\` in [claude-workflow](https://github.com/TiesL/claude-workflow)"
    echo "of dit project hem toepast. Geen rij betekent: (nog) niet van toepassing —"
    echo "de vraag verschijnt vanzelf zodra dat verandert."
    echo
    echo "| Wijziging | Antwoord | Datum | Toelichting |"
    echo "|---|---|---|---|"
  } > "$doel"

  _seed_project_dir="$project_dir"
  _seed_doel="$doel"
  _seed_vandaag="$(date +%Y-%m-%d)"
  itereer_alle_entries "$CLAUDE_WORKFLOW_DIR" seed_entry

  echo "Adoptietabel aangemaakt: $doel"
}

GITIGNORE_BEGIN="# claude-workflow: begin — beheerd blok, niet met de hand bewerken"
GITIGNORE_EIND="# claude-workflow: eind"

# Zet het beheerde blok in .gitignore, met precies de meegegeven regels.
#
# Waarom een blok en geen losse regels: zonder markering is niet te zien welke
# regels van deze workflow zijn, en dus ook niet welke weg mogen als een
# conventie verdwijnt. Losse regels stapelen zich op en blijven eeuwig staan.
#
# De migratie haalt dezelfde regels weg als ze los buiten het blok staan - dat
# is de bestaande situatie in alle vier de projecten. Alles wat niet letterlijk
# een beheerde regel of onderdeel van het blok is, blijft ongemoeid, op zijn
# plek en in zijn volgorde. Dat is geen nettigheid: `tennis-admin/.gitignore`
# sluit met `tennis-registration/` en `tennis-invoicing/` twee geneste
# git-repo's uit, en die per ongeluk opeten maakt van twee hele repo's
# ongetrackte inhoud.
schrijf_gitignore_blok() {
  local project_dir="$1"; shift
  local gitignore="$project_dir/.gitignore"
  local tijdelijk="$gitignore.claude-workflow-tmp"

  touch "$gitignore"

  # Eerst controleren of de markers kloppen. Een blok met alleen een
  # beginmarker liet een eerdere versie alles daarna stilzwijgend wissen: de
  # awk hieronder zet zijn vlag op de beginmarker en wacht op een eindmarker
  # die nooit komt, dus loopt hij door tot het einde van het bestand.
  #
  # Bij twijfel niets aanraken en luid melden. Dit bestand is getrackt en bevat
  # in minstens één project regels die geneste git-repo's uitsluiten; er stil
  # doorheen ploegen is de duurste fout die dit script kan maken.
  if ! marker_probleem="$(awk -v begin="$GITIGNORE_BEGIN" -v eind="$GITIGNORE_EIND" '
    $0 == begin {
      if (diepte > 0) { print "een tweede beginmarker op regel " NR " terwijl het vorige blok nog niet gesloten is"; exit 1 }
      diepte++; next
    }
    $0 == eind {
      if (diepte == 0) { print "een eindmarker op regel " NR " zonder bijbehorende beginmarker"; exit 1 }
      diepte--; next
    }
    END { if (diepte > 0) { print "een beginmarker zonder eindmarker"; exit 1 } }
  ' "$gitignore")"; then
    echo "adopt.sh: $gitignore heeft een beschadigd beheerd blok — $marker_probleem." >&2
    echo "adopt.sh: het bestand is niet aangeraakt. Herstel de markers met de hand en draai opnieuw." >&2
    return 1
  fi

  # Bestaande inhoud, zonder het oude blok en zonder de losse varianten van de
  # beheerde regels.
  awk -v begin="$GITIGNORE_BEGIN" -v eind="$GITIGNORE_EIND" '
    $0 == begin { in_blok = 1; next }
    in_blok { if ($0 == eind) in_blok = 0; next }
    { print }
  ' "$gitignore" > "$tijdelijk"

  # De losse varianten weghalen. Vergelijken gebeurt op de regel zonder
  # regeleinde-rommel en zonder witruimte aan het eind: `CLAUDE.md` met een
  # achtergebleven carriage return of drie spaties erachter is dezelfde regel
  # voor git, en een exacte vergelijking zou hem laten staan naast de nieuwe -
  # dan staat hij twee keer in plaats van gemigreerd.
  local regel
  for regel in "$@"; do
    awk -v weg="$regel" '
      { kaal = $0; sub(/\r$/, "", kaal); sub(/[ \t]+$/, "", kaal) }
      kaal == weg { next }
      { print }
    ' "$tijdelijk" > "$tijdelijk.f"
    mv "$tijdelijk.f" "$tijdelijk"
  done

  # Alleen de witregels aan het éínd weghalen, anders groeit het bestand met een
  # witregel per run en is de adoptie niet meer idempotent. Witregels midden in
  # het bestand blijven: die scheiden groepen, en ze weggooien is precies het
  # ongevraagd herschrijven van andermans .gitignore dat hier niet hoort.
  #
  # De test is `length($0) == 0`, niet `NF`: awk splitst op witruimte, dus een
  # regel met alleen spaties heeft NF nul en zou als lege regel teruggeschreven
  # worden - met de spaties eraf. Dat is een wijziging van inhoud buiten het
  # blok, en die hoort dit script niet te maken.
  awk '
    length($0) > 0 { for (i = 1; i <= wacht; i++) print ""; wacht = 0; print; next }
    { wacht++ }
  ' "$tijdelijk" > "$tijdelijk.f"
  mv "$tijdelijk.f" "$tijdelijk"

  {
    if [ -s "$tijdelijk" ]; then
      cat "$tijdelijk"
      echo
    fi
    echo "$GITIGNORE_BEGIN"
    for regel in "$@"; do
      echo "$regel"
    done
    echo "$GITIGNORE_EIND"
  } > "$gitignore"

  rm -f "$tijdelijk"
  echo "Beheerd .gitignore-blok bijgewerkt: $*"
}

# Ververst of legt één skill-symlink aan in doel_map: <doel_map>/<naam> ->
# <bron_map>/<naam>. Alleen vervangen als het bestaande pad zelf een symlink is
# of nog niet bestaat - een echte map (van het project of de gebruiker zelf)
# wordt nooit overschreven.
skill_symlink_bijwerken() {
  local doel_map="$1" naam="$2" bron_map="$3"
  if [ -L "$doel_map/$naam" ] || [ ! -e "$doel_map/$naam" ]; then
    rm -f "$doel_map/$naam"
    ln -s "$bron_map/$naam" "$doel_map/$naam"
  fi
}

# Ruimt één symlink op als hij verweesd is: hij wijst (opgelost) naar iets
# onder bron_echt dat niet meer bestaat. Een verweesde skill is niet inert:
# Claude Code meldt er elke sessie een laadfout op.
#
# Strikt: alleen symlinks die naar bron_echt wijzen én waarvan het doel niet
# meer bestaat. Een symlink die ergens anders heen wijst is niet van ons om op
# te ruimen. Vergelijken gebeurt op opgeloste paden, niet op de tekst van de
# symlink - een relatieve link naar dezelfde plek is dezelfde link, en een
# tekstuele prefixvergelijking ziet dat niet.
#
# Lukt het oplossen niet, dan blijft de link staan. Bij twijfel niets
# weggooien: dit is andermans map.
skill_symlink_opruimen_indien_verweesd() {
  local link="$1" bron_echt="$2"
  [ -L "$link" ] || return 0

  local bestemming map map_echt
  bestemming="$(readlink "$link")"
  case "$bestemming" in
    /*) ;;
    *) bestemming="$(dirname "$link")/$bestemming" ;;
  esac

  map="$(dirname "$bestemming")"
  map_echt="$(cd "$map" 2>/dev/null && pwd -P)" || return 0
  [ -n "$map_echt" ] || return 0

  case "$map_echt/$(basename "$bestemming")" in
    "$bron_echt"/*) ;;
    *) return 0 ;;
  esac

  if [ ! -e "$bestemming" ]; then
    rm "$link"
    echo "Verweesde skill-symlink opgeruimd: $(basename "$link")"
  fi
}

# Installeert de skills van dit repo als losse symlinks in het project.
#
# Per skill een symlink in een echte map, niet één map-symlink. Dat laatste
# maakt de hele skills-namespace eigendom van claude-workflow, waarmee een
# project nooit een eigen skill kan hebben zonder te de-adopteren.
#
# Zonder skills/-map: niets doen, en géén lege map achterlaten. De installer
# landt vóór de inhoud, dus dit is de normale toestand tot die map gevuld is.
installeer_skills() {
  local project_dir="$1"
  local bron="$CLAUDE_WORKFLOW_DIR/skills"
  local doel="$project_dir/.claude/skills"

  if [ ! -d "$bron" ]; then
    return 0
  fi

  if [ -L "$doel" ]; then
    rm "$doel"
  fi
  mkdir -p "$doel"

  local pad naam
  for pad in "$bron"/*/; do
    [ -d "$pad" ] || continue
    naam="$(basename "$pad")"
    skill_symlink_bijwerken "$doel" "$naam" "$bron"
  done

  local bron_echt
  bron_echt="$(cd "$bron" && pwd -P)"

  local link
  for link in "$doel"/*; do
    skill_symlink_opruimen_indien_verweesd "$link" "$bron_echt"
  done
}

# Installeert precies de user-level skill (adopt-workflow) in
# ~/.claude/skills/. F10: dit is de enige skill die op userniveau hoort, want
# USER-CLAUDE.md laadt juist in niet-geadopteerde projecten, waar
# .claude/skills/ niet bestaat.
installeer_user_skill() {
  local naam="adopt-workflow"
  local bron="$CLAUDE_WORKFLOW_DIR/skills"
  local doel="$HOME/.claude/skills"

  if [ ! -d "$bron/$naam" ]; then
    return 0
  fi

  if [ -L "$doel" ]; then
    rm "$doel"
  fi
  mkdir -p "$doel"

  skill_symlink_bijwerken "$doel" "$naam" "$bron"

  local bron_echt
  bron_echt="$(cd "$bron" && pwd -P)"
  skill_symlink_opruimen_indien_verweesd "$doel/$naam" "$bron_echt"
}

adopt_user_trigger() {
  mkdir -p "$HOME/.claude"
  backup_if_real_file "$HOME/.claude/CLAUDE.md"
  ln -s "$CLAUDE_WORKFLOW_DIR/USER-CLAUDE.md" "$HOME/.claude/CLAUDE.md"
  echo "Klaar: ~/.claude/CLAUDE.md -> $CLAUDE_WORKFLOW_DIR/USER-CLAUDE.md"

  installeer_user_skill
}

adopt_project() {
  local project_dir="$1"

  if [ ! -d "$project_dir/.git" ]; then
    echo "Fout: '$project_dir' is geen git-repository (geen .git-map gevonden)." >&2
    exit 1
  fi

  local resolved_project resolved_workflow
  resolved_project="$(cd "$project_dir" && pwd)"
  resolved_workflow="$(cd "$CLAUDE_WORKFLOW_DIR" && pwd)"
  if [ "$resolved_project" = "$resolved_workflow" ]; then
    echo "Dit is claude-workflow zelf — geen adoptie nodig."
    exit 0
  fi

  mkdir -p "$project_dir/.claude"

  backup_if_real_file "$project_dir/CLAUDE.md"
  ln -s "$CLAUDE_WORKFLOW_DIR/WORKFLOW.md" "$project_dir/CLAUDE.md"

  backup_if_real_file "$project_dir/.claude/settings.json"
  ln -s "$CLAUDE_WORKFLOW_DIR/settings/session-hooks.json" "$project_dir/.claude/settings.json"

  # `.claude/skills/` hoort erbij: dat zijn symlinks naar een absoluut pad op
  # déze machine. Ze committen levert in elke andere checkout kapotte links op,
  # en zonder deze regel verschijnt er bij de eerste her-adoptie na W9 in alle
  # vier de projecten een stapel ongetrackte bestanden.
  schrijf_gitignore_blok "$project_dir" "CLAUDE.md" ".claude/settings.json" ".claude/skills/"
  installeer_skills "$project_dir"

  scaffold_if_missing "$CLAUDE_WORKFLOW_DIR/templates/PRD.md" "$project_dir/PRD.md"
  scaffold_if_missing "$CLAUDE_WORKFLOW_DIR/templates/TEST-SCENARIOS.md" "$project_dir/TEST-SCENARIOS.md"
  scaffold_if_missing "$CLAUDE_WORKFLOW_DIR/templates/ARCHITECTUUR.md" "$project_dir/ARCHITECTUUR.md"
  scaffold_if_missing "$CLAUDE_WORKFLOW_DIR/templates/check-traceability.sh" "$project_dir/check-traceability.sh"
  # Expliciet uitvoerbaar maken. `cp` neemt de rechten van de bron over, maar
  # dat is geen garantie waar dit script op mag leunen: een niet-uitvoerbaar
  # script faalt pas bij de eerste aanroep, en dan lijkt de controle kapot in
  # plaats van verkeerd geïnstalleerd. Als `if`, niet als `&&`: onder `set -e`
  # zou een falende test de hele adoptie afbreken.
  if [ -f "$project_dir/check-traceability.sh" ]; then
    chmod +x "$project_dir/check-traceability.sh"
  fi
  copy_issue_templates "$project_dir"

  if [ -f "$project_dir/package.json" ]; then
    mkdir -p "$project_dir/.github/workflows"
    scaffold_if_missing "$CLAUDE_WORKFLOW_DIR/templates/ci.yml" "$project_dir/.github/workflows/ci.yml"
  fi

  seed_adoptietabel "$project_dir"

  echo "Klaar: $project_dir gebruikt nu de gedeelde workflow uit $CLAUDE_WORKFLOW_DIR"
}

if [ "${1:-}" = "--user" ]; then
  adopt_user_trigger
else
  adopt_project "${1:-.}"
fi
