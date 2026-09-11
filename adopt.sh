#!/usr/bin/env bash
# adopt.sh — Adopts the shared spec-driven-guardrails workflow in a
# project, or sets up the user-wide adoption-question trigger (--user).
#
# Usage:
#   ./adopt.sh                 # adopts the workflow in the current directory
#   ./adopt.sh /path/to/proj   # adopts the workflow in the given directory
#   ./adopt.sh --user           # sets the ~/.claude/CLAUDE.md symlink (once per machine)
#
# Requires: environment variable SPEC_DRIVEN_GUARDRAILS_DIR, pointing at the
# local checkout of this repo on *this* machine (see README.md).

set -euo pipefail

if [ -z "${SPEC_DRIVEN_GUARDRAILS_DIR:-}" ]; then
  echo "Error: SPEC_DRIVEN_GUARDRAILS_DIR is not set." >&2
  echo "Set this once in your shell profile, e.g.:" >&2
  echo "  export SPEC_DRIVEN_GUARDRAILS_DIR=\"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)\"" >&2
  exit 1
fi
CLAUDE_WORKFLOW_DIR="$SPEC_DRIVEN_GUARDRAILS_DIR"

if [ ! -f "$CLAUDE_WORKFLOW_DIR/WORKFLOW.md" ]; then
  echo "Error: the given path ('$CLAUDE_WORKFLOW_DIR') contains no WORKFLOW.md — is the path correct?" >&2
  exit 1
fi

# Normalized to an absolute path, once and globally here — not only
# locally in adopt_project(). Every symlink this script sets (skills,
# git hooks, CLAUDE.md/settings.json) points at CLAUDE_WORKFLOW_DIR
# (internal: the resolved location, regardless of which environment
# variable it came in through); a relative path would make such a symlink
# dangling (relative targets resolve from the symlink's own directory, not
# from the directory adopt.sh happened to run from) — and git silently
# skips a dangling git hook, with no report at all. Exactly the failure
# mode F17 aims to eliminate.
CLAUDE_WORKFLOW_DIR="$(cd "$CLAUDE_WORKFLOW_DIR" && pwd)"

# The library comes from the checkout *this* script lives in, not from
# CLAUDE_WORKFLOW_DIR: code belongs with the script that calls it. The data
# (CHANGES.md, templates) *does* come from CLAUDE_WORKFLOW_DIR, as always.
eigen_map="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/changes.sh
. "$eigen_map/lib/changes.sh"
# shellcheck source=lib/nfr.sh
. "$eigen_map/lib/nfr.sh"

backup_if_real_file() {
  local path="$1"
  if [ -e "$path" ] && [ ! -L "$path" ]; then
    echo "Existing file found at $path — backing up to $path.bak"
    mv "$path" "$path.bak"
  elif [ -L "$path" ]; then
    rm "$path"
  fi
}

scaffold_if_missing() {
  local template="$1" target="$2"
  if [ ! -e "$target" ] && [ -f "$template" ]; then
    cp "$template" "$target"
    echo "Created from template: $target"
  fi
}

copy_issue_templates() {
  local project_dir="$1"
  local template_src="$CLAUDE_WORKFLOW_DIR/templates/ISSUE_TEMPLATE"
  if [ -d "$template_src" ]; then
    mkdir -p "$project_dir/.github/ISSUE_TEMPLATE"
    cp -f "$template_src"/*.md "$project_dir/.github/ISSUE_TEMPLATE/"
    [ -f "$template_src/config.yml" ] && cp -f "$template_src/config.yml" "$project_dir/.github/ISSUE_TEMPLATE/"
    echo "Issue templates copied to $project_dir/.github/ISSUE_TEMPLATE/"
  fi
}

# Callback for itereer_entries. The input comes via _seed_* globals instead
# of dynamic scope, so it's visible where it comes from.
#
# `standaard: question` is skipped here: those entries are never answered
# automatically. pending-changes.sh, on the other hand, ignores that same
# field — see the callback there. That asymmetry is deliberate and so
# lives at both callers, not hidden in lib/changes.sh.
seed_entry() {
  local id="$1" standaard="$2" predicaat="$3"
  if [ "$standaard" = "question" ]; then
    return 0
  fi
  if ! predicaat_waar "$predicaat" "$_seed_project_dir"; then
    return 0
  fi
  echo "| $id | yes | $_seed_vandaag | at adoption — requires substantiation during PRD/architecture |" >> "$_seed_doel"
}

# Records at adoption time that this project agrees to the current state
# of the workflow: every currently applicable change gets "yes". Whatever
# doesn't apply gets no row and is asked about later once the condition
# becomes true (see pending-changes.sh).
#
# Checks for the pre-migration filename (WORKFLOW-ADOPTIE.md, W42/#114) too,
# not just the new one: a project that already has an old-format answer
# file must not get a second, English-named file seeded alongside it —
# that would duplicate every already-answered question. pending-changes.sh
# is what flags an old-format file for migration; this function only ever
# seeds a genuinely new adoption.
seed_adoptietabel() {
  local project_dir="$1"
  local doel="$project_dir/WORKFLOW-ADOPTION.md"
  local oud="$project_dir/WORKFLOW-ADOPTIE.md"
  local changes="$CLAUDE_WORKFLOW_DIR/CHANGES.md"

  [ -e "$doel" ] && return 0
  [ -e "$oud" ] && return 0
  [ -f "$changes" ] || return 0

  {
    echo "# Adoption of shared workflow changes"
    echo
    echo "Per change from \`CHANGES.md\` in [spec-driven-guardrails](https://github.com/TiesL/spec-driven-guardrails)"
    echo "whether this project applies it. No row means: not (yet) applicable —"
    echo "the question shows up on its own once that changes."
    echo
    echo "| Change | Answer | Date | Notes |"
    echo "|---|---|---|---|"
  } > "$doel"

  _seed_project_dir="$project_dir"
  _seed_doel="$doel"
  _seed_vandaag="$(date +%Y-%m-%d)"
  itereer_alle_entries "$CLAUDE_WORKFLOW_DIR" seed_entry

  echo "Adoption table created: $doel"
}

GITIGNORE_BEGIN="# claude-workflow: begin — managed block, do not edit by hand"
GITIGNORE_EIND="# claude-workflow: end"

# Sets the managed block in .gitignore, with exactly the given lines.
#
# Why a block and not loose lines: without a marker, there's no way to see
# which lines belong to this workflow, and thus no way to see which ones
# may go when a convention disappears. Loose lines pile up and stick
# around forever.
#
# The migration removes the same lines when they appear loose, outside the
# block — that's the existing situation in all four projects. Everything
# that isn't literally a managed line or part of the block is left alone,
# in its place and in its order. That's not tidiness: `tennis-admin/.gitignore`
# excludes two nested git repos with `tennis-registration/` and
# `tennis-invoicing/`, and accidentally swallowing those turns two whole
# repos into untracked content.
schrijf_gitignore_blok() {
  local project_dir="$1"; shift
  local gitignore="$project_dir/.gitignore"
  local tijdelijk="$gitignore.claude-workflow-tmp"

  touch "$gitignore"

  # First checking that the markers are sound. A block with only a begin
  # marker let an earlier version silently erase everything after it: the
  # awk below sets its flag on the begin marker and waits for an end marker
  # that never comes, so it runs through to the end of the file.
  #
  # When in doubt, touch nothing and report loudly. This file is tracked
  # and in at least one project contains lines excluding nested git repos;
  # silently plowing through it is the most expensive mistake this script
  # can make.
  if ! marker_probleem="$(awk -v begin="$GITIGNORE_BEGIN" -v eind="$GITIGNORE_EIND" '
    $0 == begin {
      if (diepte > 0) { print "a second begin marker on line " NR " while the previous block is not closed yet"; exit 1 }
      diepte++; next
    }
    $0 == eind {
      if (diepte == 0) { print "an end marker on line " NR " with no matching begin marker"; exit 1 }
      diepte--; next
    }
    END { if (diepte > 0) { print "a begin marker with no end marker"; exit 1 } }
  ' "$gitignore")"; then
    echo "adopt.sh: $gitignore has a corrupted managed block — $marker_probleem." >&2
    echo "adopt.sh: the file was not touched. Fix the markers by hand and run again." >&2
    return 1
  fi

  # Existing content, without the old block and without the loose variants
  # of the managed lines.
  awk -v begin="$GITIGNORE_BEGIN" -v eind="$GITIGNORE_EIND" '
    $0 == begin { in_blok = 1; next }
    in_blok { if ($0 == eind) in_blok = 0; next }
    { print }
  ' "$gitignore" > "$tijdelijk"

  # Removing the loose variants. Comparison happens on the line stripped
  # of line-ending clutter and trailing whitespace: `CLAUDE.md` with a
  # leftover carriage return or three trailing spaces is the same line to
  # git, and an exact comparison would leave it standing next to the new
  # one — then it appears twice instead of migrated.
  local regel
  for regel in "$@"; do
    awk -v weg="$regel" '
      { kaal = $0; sub(/\r$/, "", kaal); sub(/[ \t]+$/, "", kaal) }
      kaal == weg { next }
      { print }
    ' "$tijdelijk" > "$tijdelijk.f"
    mv "$tijdelijk.f" "$tijdelijk"
  done

  # Only removing blank lines at the *end*, otherwise the file grows one
  # blank line per run and adoption stops being idempotent. Blank lines in
  # the middle of the file stay: those separate groups, and discarding
  # them is exactly the unsolicited rewriting of someone else's .gitignore
  # that doesn't belong here.
  #
  # The test is `length($0) == 0`, not `NF`: awk splits on whitespace, so
  # a line with only spaces has NF zero and would be written back as an
  # empty line — with the spaces stripped. That's a change to content
  # outside the block, and this script shouldn't make it.
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
  echo "Managed .gitignore block updated: $*"
}

# Refreshes or creates one skill symlink in doel_map: <doel_map>/<naam> ->
# <bron_map>/<naam>. Only replaced if the existing path is itself a symlink
# or doesn't exist yet — a real directory (belonging to the project or the
# user themselves) is never overwritten.
skill_symlink_bijwerken() {
  local doel_map="$1" naam="$2" bron_map="$3"
  if [ -L "$doel_map/$naam" ] || [ ! -e "$doel_map/$naam" ]; then
    rm -f "$doel_map/$naam"
    ln -s "$bron_map/$naam" "$doel_map/$naam"
  fi
}

# Cleans up one symlink if it's orphaned: it points (resolved) at
# something under bron_echt that no longer exists. An orphaned skill isn't
# inert: Claude Code reports a load error for it every session.
#
# Strict: only symlinks that point at bron_echt *and* whose target no
# longer exists. A symlink pointing somewhere else isn't ours to clean up.
# Comparison happens on resolved paths, not on the symlink's text — a
# relative link to the same place is the same link, and a textual prefix
# comparison wouldn't see that.
#
# If resolving fails, the link is left standing. When in doubt, discard
# nothing: this is someone else's directory.
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
    echo "Orphaned skill symlink cleaned up: $(basename "$link")"
  fi
}

# Installs this repo's skills as individual symlinks in the project.
#
# One symlink per skill in a real directory, not a single directory
# symlink. The latter would make the entire skills namespace owned by
# spec-driven-guardrails, leaving a project unable to ever have its own
# skill without de-adopting.
#
# Without a skills/ directory: do nothing, and leave *no* empty directory
# behind. The installer lands before the content, so this is the normal
# state until that directory is populated.
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

# Installs the native git hooks (W26, F17) as symlinks in
# <project>/.git/hooks/, so the guard rule also applies outside Claude Code
# (plain terminal, IDE, a different agent harness). Symlink, not a copy:
# same reason as CLAUDE.md/settings.json — the rule must always be the
# current version from spec-driven-guardrails, not a snapshot.
#
# AC5/S51: unlike CLAUDE.md/settings.json (deliberately single-purpose
# files), a project having its own pre-commit/pre-push is a real
# scenario — a lint hook, for example — with a purpose entirely different
# from branch protection. backup_if_real_file would silently disable such
# a hook behind a .bak; that's more than "reporting", that's losing
# functionality with no way back. A *real* file (not a symlink) is
# therefore left alone, loudly reported, and not installed.
#
# A symlink only counts as "ours" if it already points at exactly this
# target file — then it's replaced (idempotent: "running twice yields an
# identical tree"). A symlink to something else (the project's own
# dotfiles, for example) is just as much a deliberate choice as a real
# file, and gets the same treatment: left alone, loudly reported.
installeer_git_hooks() {
  local project_dir="$1"
  local git_dir="$project_dir/.git"
  local hooks_dir="$git_dir/hooks"

  # No .git directory: nothing to do. adopt_project already checked this,
  # but this function must also be correct on its own.
  [ -d "$git_dir" ] || return 0
  mkdir -p "$hooks_dir"

  local naam pad bron huidig_doel
  for naam in pre-commit pre-push; do
    bron="$CLAUDE_WORKFLOW_DIR/hooks/$naam"
    [ -f "$bron" ] || continue
    pad="$hooks_dir/$naam"
    if [ -e "$pad" ] || [ -L "$pad" ]; then
      if [ -L "$pad" ]; then
        huidig_doel="$(readlink "$pad" 2>/dev/null)"
      else
        huidig_doel=""
      fi
      if [ "$huidig_doel" = "$bron" ]; then
        rm "$pad"
      else
        echo "Own git hook found at $pad — not touched. git-guardrails' branch protection therefore doesn't apply here outside Claude, unless you include that rule in your own hook."
        continue
      fi
    fi
    ln -s "$bron" "$pad"
    chmod +x "$bron" 2>/dev/null || true
  done
}

# Installs exactly the user-level skill (adopt-workflow) into
# ~/.claude/skills/. F10: this is the only skill that belongs at user
# level, because USER-CLAUDE.md specifically loads in non-adopted
# projects, where .claude/skills/ doesn't exist.
installeer_user_skill() {
  local naam="adopt-workflow"
  local bron="$CLAUDE_WORKFLOW_DIR/skills"
  local doel="$HOME/.claude/skills"

  # Unlike $project_dir/.claude/skills, this isn't a directory this repo
  # fully owns: it's the user's entire personal skill namespace on *this*
  # machine, which may itself already contain symlinks to elsewhere.
  # Blindly replacing it just because it happens to be a symlink doesn't
  # belong here — "when in doubt, discard nothing" applies at user level
  # even more strongly than in a project. mkdir -p here is a safe no-op if
  # the path already exists.
  if [ ! -d "$bron" ]; then
    return 0
  fi
  mkdir -p "$doel"

  # The install step only if the skill exists now; the cleanup step
  # always, even if the skill has since disappeared — that's exactly when
  # the link may be orphaned.
  if [ -d "$bron/$naam" ]; then
    skill_symlink_bijwerken "$doel" "$naam" "$bron"
  fi

  local bron_echt
  bron_echt="$(cd "$bron" && pwd -P)"
  skill_symlink_opruimen_indien_verweesd "$doel/$naam" "$bron_echt"
}

adopt_user_trigger() {
  mkdir -p "$HOME/.claude"
  backup_if_real_file "$HOME/.claude/CLAUDE.md"
  ln -s "$CLAUDE_WORKFLOW_DIR/USER-CLAUDE.md" "$HOME/.claude/CLAUDE.md"
  echo "Done: ~/.claude/CLAUDE.md -> $CLAUDE_WORKFLOW_DIR/USER-CLAUDE.md"

  installeer_user_skill
}

adopt_project() {
  local project_dir="$1"

  if [ ! -d "$project_dir/.git" ]; then
    echo "Error: '$project_dir' is not a git repository (no .git directory found)." >&2
    exit 1
  fi

  # spec-driven-guardrails deliberately adopts itself too (issue #98): no
  # exception here, one mechanism for every target. Without this, this
  # repo's own checkout would go without the git-guardrails hook and the
  # merge guard — F7/F8 would then never apply to the very source that
  # specifies them.
  mkdir -p "$project_dir/.claude"

  backup_if_real_file "$project_dir/CLAUDE.md"
  ln -s "$CLAUDE_WORKFLOW_DIR/WORKFLOW.md" "$project_dir/CLAUDE.md"

  backup_if_real_file "$project_dir/.claude/settings.json"
  ln -s "$CLAUDE_WORKFLOW_DIR/settings/session-hooks.json" "$project_dir/.claude/settings.json"

  # `.claude/skills/` belongs here too: those are symlinks to an absolute
  # path on *this* machine. Committing them yields broken links in every
  # other checkout, and without this line, the first re-adoption after W9
  # would leave a pile of untracked files in all four projects.
  schrijf_gitignore_blok "$project_dir" "CLAUDE.md" ".claude/settings.json" ".claude/skills/"
  installeer_skills "$project_dir"
  installeer_git_hooks "$project_dir"

  scaffold_if_missing "$CLAUDE_WORKFLOW_DIR/templates/PRD.md" "$project_dir/PRD.md"
  scaffold_if_missing "$CLAUDE_WORKFLOW_DIR/templates/TEST-SCENARIOS.md" "$project_dir/TEST-SCENARIOS.md"
  scaffold_if_missing "$CLAUDE_WORKFLOW_DIR/templates/ARCHITECTUUR.md" "$project_dir/ARCHITECTUUR.md"
  scaffold_if_missing "$CLAUDE_WORKFLOW_DIR/templates/check-traceability.sh" "$project_dir/check-traceability.sh"
  # Explicitly making it executable. `cp` inherits the source's
  # permissions, but that's not a guarantee this script may rely on: a
  # non-executable script only fails on its first call, and then the
  # check looks broken instead of wrongly installed. As `if`, not `&&`:
  # under `set -e`, a failing test would abort the entire adoption.
  if [ -f "$project_dir/check-traceability.sh" ]; then
    chmod +x "$project_dir/check-traceability.sh"
  fi
  copy_issue_templates "$project_dir"

  if [ -f "$project_dir/package.json" ]; then
    mkdir -p "$project_dir/.github/workflows"
    scaffold_if_missing "$CLAUDE_WORKFLOW_DIR/templates/ci.yml" "$project_dir/.github/workflows/ci.yml"
    scaffold_if_missing "$CLAUDE_WORKFLOW_DIR/templates/check-pr-issue-link.sh" "$project_dir/check-pr-issue-link.sh"
    if [ -f "$project_dir/check-pr-issue-link.sh" ]; then
      chmod +x "$project_dir/check-pr-issue-link.sh"
    fi
    scaffold_if_missing "$CLAUDE_WORKFLOW_DIR/templates/check-main-via-pr.sh" "$project_dir/check-main-via-pr.sh"
    if [ -f "$project_dir/check-main-via-pr.sh" ]; then
      chmod +x "$project_dir/check-main-via-pr.sh"
    fi
  fi

  seed_adoptietabel "$project_dir"

  # CONTEXT.md is optional (W16b): scaffold only once the project has
  # answered process-context-document with "yes". No predicate like
  # heeft-package-json — the condition lives in the project's own adoption
  # table, so it's read directly here. This works both for a fresh
  # adoption (if Standaard:ja just seeded it) and for a re-adoption after
  # someone later set the row to "yes" anyway.
  #
  # Also checks the pre-migration filename/ID/value (W42/#114): a project
  # that hasn't migrated yet still answers with the old vocabulary, and
  # this scaffold shouldn't wait on that unrelated migration to keep
  # working.
  if grep -qE '^\| *process-context-document *\| *yes *\|' "$project_dir/WORKFLOW-ADOPTION.md" 2>/dev/null \
    || grep -qE '^\| *proces-context-document *\| *ja *\|' "$project_dir/WORKFLOW-ADOPTIE.md" 2>/dev/null; then
    scaffold_if_missing "$CLAUDE_WORKFLOW_DIR/templates/CONTEXT.md" "$project_dir/CONTEXT.md"
  fi

  echo "Done: $project_dir now uses the shared workflow from $CLAUDE_WORKFLOW_DIR"
}

if [ "${1:-}" = "--user" ]; then
  adopt_user_trigger
else
  adopt_project "${1:-.}"
fi
