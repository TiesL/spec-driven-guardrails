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
own_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/changes.sh
. "$own_dir/lib/changes.sh"
# shellcheck source=lib/nfr.sh
. "$own_dir/lib/nfr.sh"

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

# #240 AC2: process-issue-tracking defaults to "question" (never
# auto-answered, see seed_entry's comment above). Creating
# .github/ISSUE_TEMPLATE/ for the first time is exactly the "yes means"
# action that row gates — doing it unconditionally is what let
# portfolio-mgt-agents' templates exist with that row still unanswered
# (#238 finding 4). But S31/AC3 needs the opposite guarantee once a
# project already has the directory: adopt.sh must always refresh an
# outdated template there, regardless of whether the row was ever
# formally answered — a project with the directory already in place has
# self-evidently opted in, answered or not. So the gate applies only to
# *first creation*, never to refreshing what's already there.
# Whichever answer file this project actually uses (W42/#114) holds a
# yes/ja answer for process-issue-tracking. Id and value are checked
# independently, not paired (current id + yes, old id + ja) — same
# decoupled pattern as lib/nfr.sh's nfr_missing_subsection, which exists
# for this identical yes/ja-across-a-rename problem. A row could plausibly
# carry the current id with the Dutch value, or vice versa, from a partial
# manual migration; pairing them would silently miss that. Found during
# PR #247's pre-merge-review (round 2).
issue_tracking_answered_yes() {
  local project_dir="$1" answers row_id answer
  answers="$project_dir/WORKFLOW-ADOPTION.md"
  [ -f "$answers" ] || answers="$project_dir/WORKFLOW-ADOPTIE.md"
  [ -f "$answers" ] || return 1

  while IFS='|' read -r _ raw_id raw_answer _; do
    row_id="$(printf '%s' "$raw_id" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ "$(changes_current_id "$row_id")" = "process-issue-tracking" ] || continue
    answer="$(printf '%s' "$raw_answer" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    if [ "$answer" = "yes" ] || [ "$answer" = "ja" ]; then
      return 0
    fi
  done < "$answers"
  return 1
}

copy_issue_templates() {
  local project_dir="$1"
  local template_src="$CLAUDE_WORKFLOW_DIR/templates/ISSUE_TEMPLATE"
  [ -d "$template_src" ] || return 0

  if [ ! -d "$project_dir/.github/ISSUE_TEMPLATE" ]; then
    issue_tracking_answered_yes "$project_dir" || return 0
  fi

  mkdir -p "$project_dir/.github/ISSUE_TEMPLATE"
  cp -f "$template_src"/*.md "$project_dir/.github/ISSUE_TEMPLATE/"
  [ -f "$template_src/config.yml" ] && cp -f "$template_src/config.yml" "$project_dir/.github/ISSUE_TEMPLATE/"
  echo "Issue templates copied to $project_dir/.github/ISSUE_TEMPLATE/"
}

# Callback for iterate_entries. The input comes via _seed_* globals instead
# of dynamic scope, so it's visible where it comes from.
#
# `default: question` is skipped here: those entries are never answered
# automatically. pending-changes.sh, on the other hand, ignores that same
# field — see the callback there. That asymmetry is deliberate and so
# lives at both callers, not hidden in lib/changes.sh.
seed_entry() {
  local id="$1" default="$2" predicate="$3" version
  if [ "$default" = "question" ]; then
    return 0
  fi
  if ! predicate_true "$predicate" "$_seed_project_dir"; then
    return 0
  fi
  # #254: a row seeded today is answered against *today's* CHANGES.md, not
  # implicitly version 1 — stamping the current version here is what stops
  # pending-changes.sh's meaning-version check from immediately flagging
  # a just-seeded row as if it were an old, stale answer.
  version="$(changes_meaning_version "$id" "$CLAUDE_WORKFLOW_DIR/CHANGES.md")"
  echo "| $id | yes | $_seed_today | at adoption — requires substantiation during PRD/architecture (meaning v$version) |" >> "$_seed_target"
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
seed_adoption_table() {
  local project_dir="$1"
  local target="$project_dir/WORKFLOW-ADOPTION.md"
  local old_file="$project_dir/WORKFLOW-ADOPTIE.md"
  local changes="$CLAUDE_WORKFLOW_DIR/CHANGES.md"

  [ -e "$target" ] && return 0
  [ -e "$old_file" ] && return 0
  [ -f "$changes" ] || return 0

  {
    echo "# Adoption of shared workflow changes"
    echo
    echo "Per change from \`CHANGES.md\` in [spec-driven-guardrails](https://github.com/TiesL/spec-driven-guardrails)"
    echo "whether this project applies it. No row means: not (yet) applicable —"
    echo "the question shows up on its own once that changes."
    echo
    echo "A \`no\` answer covers two different cases — say which one in the Notes:"
    echo "a permanent decline (the change doesn't fit this project), or **not yet**"
    echo "(the change applies, but its precondition doesn't hold yet — e.g. no"
    echo "architecture decision has been made, so \`architecture-document\` can't"
    echo "honestly be \`yes\`). A \"not yet\" row names a concrete trigger to revisit,"
    echo "same shape as \`PRD.md\`'s Technical debt table — never \`yes\` on the"
    echo "strength of intent alone."
    echo
    echo "| Change | Answer | Date | Notes |"
    echo "|---|---|---|---|"
  } > "$target"

  _seed_project_dir="$project_dir"
  _seed_target="$target"
  _seed_today="$(date +%Y-%m-%d)"
  iterate_all_entries "$CLAUDE_WORKFLOW_DIR" seed_entry

  echo "Adoption table created: $target"
}

GITIGNORE_BEGIN="# claude-workflow: begin — managed block, do not edit by hand"
GITIGNORE_END="# claude-workflow: end"

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
# #243 AC2: a managed path already tracked *before* adoption ran makes
# the .gitignore entry write_gitignore_block adds a no-op — git doesn't
# stop tracking a path just because it later appears in .gitignore. Found
# via #238 (portfolio-mgt-agents): CLAUDE.md was committed as an absolute,
# machine-local symlink before adoption, and the gitignore entry did
# nothing retroactively.
#
# git rm --cached keeps the working-tree file (needed locally) and only
# removes it from the index — after this, the .gitignore entry actually
# takes effect. Checked with plain `git ls-files`, not `--error-unmatch`:
# the latter's directory-pathspec behavior is a poor fit for
# ".claude/skills/", where any file underneath, not an exact match, is
# what "tracked" means here.
untrack_managed_paths() {
  local project_dir="$1"; shift
  local path tracked
  for path in "$@"; do
    tracked="$(cd "$project_dir" && git ls-files -- "$path" 2>/dev/null)"
    [ -n "$tracked" ] || continue
    if (cd "$project_dir" && git rm -r --cached --quiet -- "$path" >/dev/null 2>&1); then
      echo "Untracked already-tracked managed path: $project_dir/$path (kept locally, now git-ignored)"
    fi
  done
}

write_gitignore_block() {
  local project_dir="$1"; shift
  local gitignore="$project_dir/.gitignore"
  local temp_file="$gitignore.claude-workflow-tmp"

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
  if ! marker_problem="$(awk -v begin="$GITIGNORE_BEGIN" -v end="$GITIGNORE_END" '
    $0 == begin {
      if (depth > 0) { print "a second begin marker on line " NR " while the previous block is not closed yet"; exit 1 }
      depth++; next
    }
    $0 == end {
      if (depth == 0) { print "an end marker on line " NR " with no matching begin marker"; exit 1 }
      depth--; next
    }
    END { if (depth > 0) { print "a begin marker with no end marker"; exit 1 } }
  ' "$gitignore")"; then
    echo "adopt.sh: $gitignore has a corrupted managed block — $marker_problem." >&2
    echo "adopt.sh: the file was not touched. Fix the markers by hand and run again." >&2
    return 1
  fi

  # Existing content, without the old block and without the loose variants
  # of the managed lines.
  awk -v begin="$GITIGNORE_BEGIN" -v end="$GITIGNORE_END" '
    $0 == begin { in_block = 1; next }
    in_block { if ($0 == end) in_block = 0; next }
    { print }
  ' "$gitignore" > "$temp_file"

  # Removing the loose variants. Comparison happens on the line stripped
  # of line-ending clutter and trailing whitespace: `CLAUDE.md` with a
  # leftover carriage return or three trailing spaces is the same line to
  # git, and an exact comparison would leave it standing next to the new
  # one — then it appears twice instead of migrated.
  local line
  for line in "$@"; do
    awk -v to_remove="$line" '
      { stripped = $0; sub(/\r$/, "", stripped); sub(/[ \t]+$/, "", stripped) }
      stripped == to_remove { next }
      { print }
    ' "$temp_file" > "$temp_file.f"
    mv "$temp_file.f" "$temp_file"
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
    length($0) > 0 { for (i = 1; i <= blank_run; i++) print ""; blank_run = 0; print; next }
    { blank_run++ }
  ' "$temp_file" > "$temp_file.f"
  mv "$temp_file.f" "$temp_file"

  {
    if [ -s "$temp_file" ]; then
      cat "$temp_file"
      echo
    fi
    echo "$GITIGNORE_BEGIN"
    for line in "$@"; do
      echo "$line"
    done
    echo "$GITIGNORE_END"
  } > "$gitignore"

  rm -f "$temp_file"
  echo "Managed .gitignore block updated: $*"
}

# Refreshes or creates one skill symlink in target_dir: <target_dir>/<name> ->
# <source_dir>/<name>. Only replaced if the existing path is itself a symlink
# or doesn't exist yet — a real directory (belonging to the project or the
# user themselves) is never overwritten.
skill_symlink_update() {
  local target_dir="$1" name="$2" source_dir="$3"
  if [ -L "$target_dir/$name" ] || [ ! -e "$target_dir/$name" ]; then
    rm -f "$target_dir/$name"
    ln -s "$source_dir/$name" "$target_dir/$name"
  fi
}

# Cleans up one symlink if it's orphaned: it points (resolved) at
# something under source_real that no longer exists. An orphaned skill isn't
# inert: Claude Code reports a load error for it every session.
#
# Strict: only symlinks that point at source_real *and* whose target no
# longer exists. A symlink pointing somewhere else isn't ours to clean up.
# Comparison happens on resolved paths, not on the symlink's text — a
# relative link to the same place is the same link, and a textual prefix
# comparison wouldn't see that.
#
# If resolving fails, the link is left standing. When in doubt, discard
# nothing: this is someone else's directory.
skill_symlink_cleanup_if_orphaned() {
  local link="$1" source_real="$2"
  [ -L "$link" ] || return 0

  local destination dir dir_real
  destination="$(readlink "$link")"
  case "$destination" in
    /*) ;;
    *) destination="$(dirname "$link")/$destination" ;;
  esac

  dir="$(dirname "$destination")"
  dir_real="$(cd "$dir" 2>/dev/null && pwd -P)" || return 0
  [ -n "$dir_real" ] || return 0

  case "$dir_real/$(basename "$destination")" in
    "$source_real"/*) ;;
    *) return 0 ;;
  esac

  if [ ! -e "$destination" ]; then
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
install_skills() {
  local project_dir="$1"
  local source="$CLAUDE_WORKFLOW_DIR/skills"
  local target="$project_dir/.claude/skills"

  if [ ! -d "$source" ]; then
    return 0
  fi

  if [ -L "$target" ]; then
    rm "$target"
  fi
  mkdir -p "$target"

  local path name
  for path in "$source"/*/; do
    [ -d "$path" ] || continue
    name="$(basename "$path")"
    skill_symlink_update "$target" "$name" "$source"
  done

  local source_real
  source_real="$(cd "$source" && pwd -P)"

  local link
  for link in "$target"/*; do
    skill_symlink_cleanup_if_orphaned "$link" "$source_real"
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
install_git_hooks() {
  local project_dir="$1"
  local git_dir="$project_dir/.git"
  local hooks_dir="$git_dir/hooks"

  # No .git directory: nothing to do. adopt_project already checked this,
  # but this function must also be correct on its own.
  [ -d "$git_dir" ] || return 0
  mkdir -p "$hooks_dir"

  local name path source current_target
  for name in pre-commit pre-push commit-msg; do
    source="$CLAUDE_WORKFLOW_DIR/hooks/$name"
    [ -f "$source" ] || continue
    path="$hooks_dir/$name"
    if [ -e "$path" ] || [ -L "$path" ]; then
      if [ -L "$path" ]; then
        current_target="$(readlink "$path" 2>/dev/null)"
      else
        current_target=""
      fi
      if [ "$current_target" = "$source" ]; then
        rm "$path"
      else
        echo "Own git hook found at $path — not touched. git-guardrails' branch protection therefore doesn't apply here outside Claude, unless you include that rule in your own hook."
        continue
      fi
    fi
    ln -s "$source" "$path"
    chmod +x "$source" 2>/dev/null || true
  done
}

# Installs exactly the user-level skill (adopt-workflow) into
# ~/.claude/skills/. F10: this is the only skill that belongs at user
# level, because USER-CLAUDE.md specifically loads in non-adopted
# projects, where .claude/skills/ doesn't exist.
install_user_skill() {
  local name="adopt-workflow"
  local source="$CLAUDE_WORKFLOW_DIR/skills"
  local target="$HOME/.claude/skills"

  # Unlike $project_dir/.claude/skills, this isn't a directory this repo
  # fully owns: it's the user's entire personal skill namespace on *this*
  # machine, which may itself already contain symlinks to elsewhere.
  # Blindly replacing it just because it happens to be a symlink doesn't
  # belong here — "when in doubt, discard nothing" applies at user level
  # even more strongly than in a project. mkdir -p here is a safe no-op if
  # the path already exists.
  if [ ! -d "$source" ]; then
    return 0
  fi
  mkdir -p "$target"

  # The install step only if the skill exists now; the cleanup step
  # always, even if the skill has since disappeared — that's exactly when
  # the link may be orphaned.
  if [ -d "$source/$name" ]; then
    skill_symlink_update "$target" "$name" "$source"
  fi

  local source_real
  source_real="$(cd "$source" && pwd -P)"
  skill_symlink_cleanup_if_orphaned "$target/$name" "$source_real"
}

adopt_user_trigger() {
  mkdir -p "$HOME/.claude"
  backup_if_real_file "$HOME/.claude/CLAUDE.md"
  ln -s "$CLAUDE_WORKFLOW_DIR/USER-CLAUDE.md" "$HOME/.claude/CLAUDE.md"
  echo "Done: ~/.claude/CLAUDE.md -> $CLAUDE_WORKFLOW_DIR/USER-CLAUDE.md"

  install_user_skill
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
  untrack_managed_paths "$project_dir" "CLAUDE.md" ".claude/settings.json" ".claude/skills/"
  write_gitignore_block "$project_dir" "CLAUDE.md" ".claude/settings.json" ".claude/skills/"
  install_skills "$project_dir"
  install_git_hooks "$project_dir"

  scaffold_if_missing "$CLAUDE_WORKFLOW_DIR/templates/PRD.md" "$project_dir/PRD.md"
  scaffold_if_missing "$CLAUDE_WORKFLOW_DIR/templates/TEST-SCENARIOS.md" "$project_dir/TEST-SCENARIOS.md"
  # #156: the template was renamed from ARCHITECTUUR.md to ARCHITECTURE.md.
  # A project that already scaffolded (and filled in) the old-named file
  # keeps it as-is — scaffold_if_missing's own "only if missing" check
  # can't see it, since the filename itself changed, and would otherwise
  # create a second, blank file alongside the real one.
  if [ -e "$project_dir/ARCHITECTUUR.md" ]; then
    echo "Found $project_dir/ARCHITECTUUR.md (pre-rename name, #156) — left as-is, not scaffolding ARCHITECTURE.md alongside it."
  else
    scaffold_if_missing "$CLAUDE_WORKFLOW_DIR/templates/ARCHITECTURE.md" "$project_dir/ARCHITECTURE.md"
  fi
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

  # #248 AC1: the real precondition for CI is an executable `check` at the
  # project root — check-convention's own contract, any stack — not
  # `package.json` specifically. `package.json` alone used to gate this,
  # which meant a project with a real check script but a different stack
  # (portfolio-mgt-agents: docs-only, plain shell `check`, #238 finding)
  # never got CI scaffolded at all, and check-pr-issue-link.sh/
  # check-main-via-pr.sh — already stack-agnostic, pure `gh` calls, no
  # npm — stayed trapped behind an unrelated npm check alongside it.
  if [ -x "$project_dir/check" ]; then
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
    # #265: enforces WORKFLOW.md's 5min-then-1min CI-polling cadence as a
    # script instead of a prose instruction an agent could improvise
    # around. Same has-check-command gate as the two above — meaningless
    # without CI to poll.
    scaffold_if_missing "$CLAUDE_WORKFLOW_DIR/templates/wait-for-ci.sh" "$project_dir/wait-for-ci.sh"
    if [ -f "$project_dir/wait-for-ci.sh" ]; then
      chmod +x "$project_dir/wait-for-ci.sh"
    fi
  elif [ -f "$project_dir/package.json" ]; then
    # Found during PR #257's pre-merge-review: a project with package.json
    # but only an npm "check" script (no root executable `check`) used to
    # get CI scaffolded under the old gate and silently doesn't anymore —
    # this is deliberate (check-convention wants a real, stack-neutral
    # `check` command CI can call directly), but silent narrowing is worse
    # than a stated reason.
    echo "Not scaffolding CI: $project_dir/package.json exists, but no executable check at $project_dir/check — add one (see check-convention skill) and run adopt.sh again."
  fi

  seed_adoption_table "$project_dir"

  # CONTEXT.md is optional (W16b): scaffold only once the project has
  # answered process-context-document with "yes". No predicate like
  # has-package-json — the condition lives in the project's own adoption
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
