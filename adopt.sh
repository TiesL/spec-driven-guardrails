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

add_gitignore_entry() {
  local project_dir="$1" entry="$2"
  local gitignore="$project_dir/.gitignore"
  touch "$gitignore"
  if ! grep -qxF "$entry" "$gitignore"; then
    echo "$entry" >> "$gitignore"
    echo "Toegevoegd aan .gitignore: $entry"
  fi
}

adopt_user_trigger() {
  mkdir -p "$HOME/.claude"
  backup_if_real_file "$HOME/.claude/CLAUDE.md"
  ln -s "$CLAUDE_WORKFLOW_DIR/USER-CLAUDE.md" "$HOME/.claude/CLAUDE.md"
  echo "Klaar: ~/.claude/CLAUDE.md -> $CLAUDE_WORKFLOW_DIR/USER-CLAUDE.md"
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

  add_gitignore_entry "$project_dir" "CLAUDE.md"
  add_gitignore_entry "$project_dir" ".claude/settings.json"

  scaffold_if_missing "$CLAUDE_WORKFLOW_DIR/templates/PRD.md" "$project_dir/PRD.md"
  scaffold_if_missing "$CLAUDE_WORKFLOW_DIR/templates/TEST-SCENARIOS.md" "$project_dir/TEST-SCENARIOS.md"
  scaffold_if_missing "$CLAUDE_WORKFLOW_DIR/templates/ARCHITECTUUR.md" "$project_dir/ARCHITECTUUR.md"
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
