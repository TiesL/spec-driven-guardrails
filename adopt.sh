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
  copy_issue_templates "$project_dir"

  if [ -f "$project_dir/package.json" ]; then
    mkdir -p "$project_dir/.github/workflows"
    scaffold_if_missing "$CLAUDE_WORKFLOW_DIR/templates/ci.yml" "$project_dir/.github/workflows/ci.yml"
  fi

  echo "Klaar: $project_dir gebruikt nu de gedeelde workflow uit $CLAUDE_WORKFLOW_DIR"
}

if [ "${1:-}" = "--user" ]; then
  adopt_user_trigger
else
  adopt_project "${1:-.}"
fi
