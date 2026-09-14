#!/usr/bin/env bash
# pending-changes.sh — Reports which adoptable changes from CHANGES.md
# still have no answer in a project's WORKFLOW-ADOPTION.md (or its
# pre-migration name, WORKFLOW-ADOPTIE.md — see W42/#114).
#
# Usage:
#   ./pending-changes.sh [/path/to/project]   # default: current directory
#
# Called by the SessionStart hook (see settings/session-hooks.json). Prints
# nothing when nothing is pending, and always ends with exit 0 — a hook
# must never block a session.
#
# A change is pending when its "Applies if" predicate is true *and*
# there's no row for that ID in the answer file. So a row's absence means
# "hasn't applied yet": if the condition later becomes true, the question
# surfaces on its own.
#
# One deliberate exception to "no network, no mutation" (W42/#114): a
# project still on the pre-migration filename gets a tracking issue filed
# on its own repo, idempotently. See the block below for why.

set -uo pipefail

workflow_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${1:-.}" 2>/dev/null && pwd)" || exit 0
changes="$workflow_dir/CHANGES.md"

# shellcheck source=lib/changes.sh
. "$workflow_dir/lib/changes.sh"
# shellcheck source=lib/nfr.sh
. "$workflow_dir/lib/nfr.sh"
# W42/#114: the new filename takes priority; fall back to the pre-migration
# name so a not-yet-migrated project still gets a normal pending report
# (in addition to the migration notice below), instead of being read as
# if it had never answered anything.
answers="$project_dir/WORKFLOW-ADOPTION.md"
[ -f "$answers" ] || answers="$project_dir/WORKFLOW-ADOPTIE.md"

[ -f "$changes" ] || exit 0

# shellcheck disable=SC2329  # called from collect_pending
answered() {
  local id="$1" old_id
  [ -f "$answers" ] || return 1
  grep -q "^| *$id *|" "$answers" && return 0
  # #156: also accept the pre-rename ID for a project that answered
  # before an NFR was renamed — same spirit as W42/#114's filename
  # fallback above, applied to the ID instead of the filename.
  old_id="$(nfr_old_id "$id")"
  [ -n "$old_id" ] && grep -q "^| *$old_id *|" "$answers" && return 0
  # #175: same alias, for the thirteen renamed CHANGES.md entry IDs.
  old_id="$(changes_old_id "$id")"
  [ -n "$old_id" ] && grep -q "^| *$old_id *|" "$answers"
}

pending=()

# Callback for iterate_entries. `default` is deliberately unused here: an
# unanswered question is pending regardless of whether it started as `yes`
# or `question`. adopt.sh does do something with that same field — see the
# callback there.
# shellcheck disable=SC2329  # called indirectly, via iterate_entries
collect_pending() {
  local id="$1" predicate="$3"
  if predicate_true "$predicate" "$project_dir" && ! answered "$id"; then
    pending+=("$id")
  fi
}

iterate_all_entries "$workflow_dir" collect_pending

if [ ${#pending[@]} -gt 0 ]; then
  echo "Pending workflow changes for this project (see CHANGES.md in spec-driven-guardrails):"
  for id in "${pending[@]}"; do
    question="$(awk -v id="## $id" '
      $0 == id { in_entry = 1; next }
      in_entry && /\*\*Question:\*\*/ {
        sub(/.*\*\*Question:\*\* */, ""); print; exit
      }
      in_entry && /^## / { exit }
    ' "$changes")"
    # If the ID isn't in CHANGES.md, it comes from the NFR register.
    if [ -z "$question" ]; then
      question="$(nfr_question "$workflow_dir/nfr" "$id")"
    fi
    echo "  - $id — $question"
  done
  # Instruction matches whichever format is actually in play (W42/#114):
  # yes/no in the new file, ja/nee if this project hasn't migrated yet.
  case "$answers" in
    */WORKFLOW-ADOPTIE.md) echo "Record a ja/nee answer per change in WORKFLOW-ADOPTIE.md." ;;
    *) echo "Record a yes/no answer per change in WORKFLOW-ADOPTION.md." ;;
  esac
fi

# A seeded row is not yet a decision. adopt.sh sets every applicable
# `Default: yes` change to "yes — requires substantiation": a provisional
# stamp. answered() only sees *that* a row exists, never what's in it, so
# without this signal a freshly adopted project would report nothing
# pending while seventeen provisional stamps sit there.
#
# answered() is deliberately not changed for this: that would change the
# pending set and thereby break R9, the regression test that guards that no
# project ever gets asked a question again. This exists alongside it
# instead.
#
# Phased substantiation is the premise (see F6): not everything at once,
# but on first contact with the topic. This is gate 3 — the signal stays
# visible until a row is genuinely answered.
if [ -f "$answers" ]; then
  # No `|| echo 0`: grep -c itself already prints "0" on zero matches, and
  # also returns exit status 1. Those two together yield the string "0\n0",
  # which trips up the comparison below. The ${pending_count:-0} fallback covers
  # the case where grep writes nothing to stdout at all, for example on
  # missing read permissions.
  #
  # Only table rows count, the same way answered() anchors on the ID
  # column: a stray note above or below the table that happens to contain
  # the same words isn't a pending substantiation.
  pending_count="$(grep -cE '^\|.*(vereist onderbouwing|requires substantiation)' "$answers" 2>/dev/null)"
  if [ "${pending_count:-0}" -gt 0 ]; then
    echo "$pending_count row(s) in ${answers#"$project_dir"/} are still waiting on substantiation."
    echo "Replace the provisional stamp with a reasoning grounded in this project,"
    echo "or change the row to 'no' (or 'nee' in the pre-migration format) with a"
    echo "reason — while you're already on the topic."
  fi
fi

# W42/#114: a project still on the pre-migration filename hasn't cut over
# yet. Reports each affected row and files a tracking issue on the
# project's own repo — a deliberate exception to this script's usual
# no-network, no-mutation rule (see module comment), because a
# session-only notice would otherwise be easy to miss across sessions.
# Idempotent via a literal marker in the issue body, checked locally
# rather than through gh's own (fuzzy) search — same reasoning as the
# pre-merge-review marker check elsewhere in this repo.
old_file="$project_dir/WORKFLOW-ADOPTIE.md"
new_file="$project_dir/WORKFLOW-ADOPTION.md"
if [ -f "$old_file" ] && [ ! -f "$new_file" ]; then
  old_rows="$(grep -E '^\| *[a-z][a-z0-9-]* *\|' "$old_file" | sed 's/^| *//; s/ *|.*//')"
  if [ -n "$old_rows" ]; then
    # Deliberately not "  - $id" (two spaces, dash): that's the exact
    # prefix the pending-question list above uses, and test/lib.sh's
    # pending_ids() greps for it. An old-format row that already has
    # a real answer (not actually pending) must never be swept into that
    # set just because this notice used the same bullet shape.
    echo "The following rows in WORKFLOW-ADOPTIE.md still use the pre-migration format (see #114):"
    printf '%s\n' "$old_rows" | while IFS= read -r row_id; do
      [ -n "$row_id" ] || continue
      echo "    * $row_id"
    done
    echo "Rename WORKFLOW-ADOPTIE.md to WORKFLOW-ADOPTION.md and change each row's"
    echo "answer from ja/nee to yes/no."

    # Guard before ever calling gh, in two independent layers:
    #
    # 1. $project_dir must be its own git root, not a directory nested
    #    inside a different repo with no .git of its own (e.g. a test
    #    fixture living inside this repo's tree). Both sides resolved with
    #    `pwd -P`: `git rev-parse --show-toplevel` always resolves symlinks
    #    physically, but $project_dir may not have (e.g. on macOS, where
    #    /var is itself a symlink to /private/var) — comparing an
    #    unresolved path against a resolved one would make this guard
    #    reject a perfectly real git root.
    #
    # 2. The repo target is pinned explicitly via `-R owner/repo`, parsed
    #    from the project's own `origin` remote — never left to gh's own
    #    cwd-based detection. That detection also honors GH_REPO, which
    #    overrides cwd entirely: with GH_REPO set in the environment, layer
    #    1 alone would still let `gh` silently target whatever GH_REPO
    #    names instead of this project. Pinning `-R` explicitly closes that
    #    hole regardless of GH_REPO. If origin isn't a github.com remote
    #    (or there's no origin at all — true for every sandboxed test
    #    project), there is nothing to pin to, so gh is never called at
    #    all — the same fail-closed direction as everywhere else in this
    #    script.
    own_git_root="$(git -C "$project_dir" rev-parse --show-toplevel 2>/dev/null)"
    project_dir_real="$(cd "$project_dir" 2>/dev/null && pwd -P)"
    remote_url="$(git -C "$project_dir" remote get-url origin 2>/dev/null)"
    # Host-qualified (`github.com/owner/repo`), not bare `owner/repo`: gh's
    # `-R`/`--repo` flag accepts an optional `HOST/` prefix, and without it
    # resolves the host from GH_HOST — the exact same class of override as
    # GH_REPO, just one field over. The origin URL already states the host
    # is github.com; discarding that would leave the call pinned to the
    # right path on whatever host GH_HOST happens to name.
    repo_target="$(printf '%s' "$remote_url" | sed -nE \
      's#^(git@github\.com:|https://github\.com/)([^/]+/[^/]+)(\.git)?$#github.com/\2#p')"
    repo_target="${repo_target%.git}"
    if command -v gh >/dev/null 2>&1 && [ -n "$own_git_root" ] \
      && [ "$own_git_root" = "$project_dir_real" ] && [ -n "$repo_target" ]; then
      migration_marker='<!-- workflow-adoptie-migratie -->'
      migration_title="Migrate WORKFLOW-ADOPTIE.md to the English format (workflow language migration, #114)"
      list_status=0
      existing_bodies="$(gh issue list -R "$repo_target" --state open --limit 200 --json body --jq '.[].body' 2>/dev/null)" \
        || list_status=$?
      # Fail closed: if the lookup itself failed (bad token, network,
      # rate limit), that's indistinguishable from "no marker found" by
      # content alone — but must not be treated the same, or a transient
      # failure files a duplicate tracking issue every single session.
      if [ "$list_status" -ne 0 ]; then
        echo "warning: could not check for an existing migration-tracking issue (gh issue list failed) — skipping this session, not filing a possible duplicate." >&2
      elif ! printf '%s' "$existing_bodies" | grep -qF "$migration_marker"; then
        migration_list="$(printf '%s\n' "$old_rows" | sed 's/^/- /')"
        migration_body="This project's \`WORKFLOW-ADOPTIE.md\` still uses the pre-migration Dutch vocabulary (\`ja\`/\`nee\`), which spec-driven-guardrails no longer supports as of the W42 migration (#114 in spec-driven-guardrails).

Rows still on the old format:
$migration_list

To migrate: rename \`WORKFLOW-ADOPTIE.md\` to \`WORKFLOW-ADOPTION.md\`, and change each row's answer from \`ja\`/\`nee\` to \`yes\`/\`no\`.

$migration_marker"
        if gh issue create -R "$repo_target" --title "$migration_title" --body "$migration_body" >/dev/null 2>&1; then
          echo "Filed a tracking issue for this migration on this project's repo."
        else
          echo "warning: could not file a tracking issue for this migration (no network, no access, or gh not configured for this repo)."
        fi
      fi
    fi
  fi
fi

# If the project is missing skills this repo does have, the adoption is
# out of date.
#
# NOTE: this message advises re-running `adopt.sh`. That only helps once
# adopt.sh actually installs skills — that lands in W8 (#20). Until then,
# this whole check is a no-op, because `skills/` doesn't exist yet. So
# don't add that directory before W8, or this advises a fix that does
# nothing.
# What's symlinked (WORKFLOW.md, the hook configuration) is active
# immediately after a `git pull`; what adopt.sh installs lags behind until
# someone re-runs it. Without this message, a project would silently keep
# the old world.
if [ -d "$workflow_dir/skills" ]; then
  missing_skills=""
  for skill_path in "$workflow_dir"/skills/*/; do
    [ -d "$skill_path" ] || continue
    skill="$(basename "$skill_path")"
    if [ ! -e "$project_dir/.claude/skills/$skill" ]; then
      # Comma-separated: a skill name with a space in it would otherwise be
      # indistinguishable from multiple separate names.
      if [ -n "$missing_skills" ]; then
        missing_skills="$missing_skills, $skill"
      else
        missing_skills="$skill"
      fi
    fi
  done
  if [ -n "$missing_skills" ]; then
    echo "This project is missing the skill(s): $missing_skills."
    echo "Run adopt.sh again from spec-driven-guardrails to install them."
  fi
fi

# If main is checked out, that's the moment branching off is still free
# (W23, F18/S54/S55). The commit block in hooks/git-guardrails only kicks
# in once there's already work — Edit, Write, git add, and git stash all go
# through on main. Purely informational: no mutation, no block, exit 0 and
# nothing on stderr, the same requirement as the substantiation signal
# above (S43).
if branch="$(git -C "$project_dir" symbolic-ref --short HEAD 2>/dev/null)" \
  && [ "$branch" = "main" ]; then
  echo "You are on main. New work belongs on its own branch:"
  echo "  git checkout -b feature/<issue-number>-<name>"
fi

# If the local checkout lags behind, the list above may be incomplete.
# Only report, don't pull automatically — a hook shouldn't mutate anything.
if git -C "$workflow_dir" rev-parse --verify --quiet origin/main >/dev/null 2>&1; then
  behind_count="$(git -C "$workflow_dir" rev-list --count HEAD..origin/main 2>/dev/null || echo 0)"
  if [ "${behind_count:-0}" -gt 0 ]; then
    echo "Note: spec-driven-guardrails is $behind_count commit(s) behind origin/main — run 'git pull' there."
  fi
fi

exit 0
