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

# The full matched row's text (whichever id/alias actually matched), or
# empty if never answered. Factored out of the old boolean answered() so
# #254 can also read what a row's Notes actually say, not just that a row
# exists.
answered_row() {
  local id="$1" old_id row
  [ -f "$answers" ] || { echo ""; return; }
  row="$(grep "^| *$id *|" "$answers" | head -1)"
  if [ -n "$row" ]; then printf '%s\n' "$row"; return; fi
  # #156: also accept the pre-rename ID for a project that answered
  # before an NFR was renamed — same spirit as W42/#114's filename
  # fallback above, applied to the ID instead of the filename.
  old_id="$(nfr_old_id "$id")"
  if [ -n "$old_id" ]; then
    row="$(grep "^| *$old_id *|" "$answers" | head -1)"
    if [ -n "$row" ]; then printf '%s\n' "$row"; return; fi
  fi
  # #175: same alias, for the thirteen renamed CHANGES.md entry IDs.
  old_id="$(changes_old_id "$id")"
  if [ -n "$old_id" ]; then
    row="$(grep "^| *$old_id *|" "$answers" | head -1)"
    if [ -n "$row" ]; then printf '%s\n' "$row"; return; fi
  fi
  echo ""
}

# shellcheck disable=SC2329  # called from collect_pending
answered() {
  [ -n "$(answered_row "$1")" ]
}

# The Question field for an id, from CHANGES.md, falling back to the NFR
# register — same lookup the pending-report loop already did inline;
# factored out so #254's resurfaced-row report can reuse it too.
entry_question() {
  local id="$1" question
  question="$(awk -v id="## $id" '
    $0 == id { in_entry = 1; next }
    in_entry && /\*\*Question:\*\*/ {
      sub(/.*\*\*Question:\*\* */, ""); print; exit
    }
    in_entry && /^## / { exit }
  ' "$changes")"
  if [ -z "$question" ]; then
    question="$(nfr_question "$workflow_dir/nfr" "$id")"
  fi
  printf '%s\n' "$question"
}

# #254: a row's "Yes means" can be materially tightened after a project
# already answered it — quality-review-before-merge/#244 is the first
# real case (added the different-model requirement). changes_meaning_version
# (lib/changes.sh, shared with adopt.sh's seed_entry) reads the entry's
# optional **Meaning version:** field, bumped by hand only when an edit is
# material (never for wording/prose-only changes — #254 AC2 is exactly why
# this isn't automatic diffing); absent means version 1. Not meaningful for
# an NFR id (nfr_question's ids aren't CHANGES.md entries) — it returns "1"
# for those too, so they simply never resurface via this mechanism,
# matching this issue's stated scope.

# The version a row's *answer* was recorded against — a trailing
# "(meaning v<N>)" in the row's own text (any column; free text, not a
# fixed position). Absent means version 1: every row answered before this
# mechanism existed implicitly answered under whatever CHANGES.md said at
# the time, which for every existing entry today is version 1.
answered_meaning_version() {
  local id="$1" row version
  row="$(answered_row "$id")"
  # tail -1, not the first match: a row's own final word wins if more
  # than one marker somehow ended up in it (found during PR #261's
  # pre-merge-review — this repo's own re-confirmed row briefly had the
  # version mentioned twice, once in prose and once as the real trailing
  # marker; grep -o's multiple lines then broke the numeric comparison
  # below, which silently swallowed the error and never resurfaced the
  # row at all — the exact failure this mechanism exists to prevent).
  version="$(printf '%s' "$row" | grep -oE '\(meaning v[0-9]+\)' | grep -oE '[0-9]+' | tail -1)"
  echo "${version:-1}"
}

pending=()
resurfaced=()
narrowed=()

# Callback for iterate_entries. `default` is deliberately unused here: an
# unanswered question is pending regardless of whether it started as `yes`
# or `question`. adopt.sh does do something with that same field — see the
# callback there.
#
# #258: the mirror image of #254 — a row's "Applies if" predicate can
# *narrow* after a project already answered it (e.g. #248 restricted
# ci-convention/ci-on-pr-and-main/ci-link-3-hard-block/
# ci-detects-main-outside-pr from has-package-json to has-check-command),
# silently dropping that project out of the asked set with no notice.
# Deliberately the same signal as #254 (the row's **Meaning version**,
# bumped by hand only for a material edit — never automatic diffing, same
# reasoning as #254's own AC2) rather than a second, parallel mechanism:
# whoever edits an "Applies if" predicate in a way that could narrow who
# it applies to bumps that field exactly like a "Yes means" edit would.
# What differs is only which bucket a version bump lands in, decided by
# whether the predicate still holds for *this* project right now.
# shellcheck disable=SC2329  # called indirectly, via iterate_entries
collect_pending() {
  local id="$1" predicate="$3" applies=1
  predicate_true "$predicate" "$project_dir" || applies=0

  if [ "$applies" -eq 1 ] && ! answered "$id"; then
    pending+=("$id")
    return 0
  fi

  # A row that's inapplicable *and* never answered is simply not pending —
  # nothing to report, same as always. Only an answered row can be
  # resurfaced (still applies) or narrowed (no longer applies).
  answered "$id" || return 0

  local current_version answered_version
  current_version="$(changes_meaning_version "$id" "$changes")"
  answered_version="$(answered_meaning_version "$id")"
  # Found during PR #261's pre-merge-review: a malformed version (from
  # either side) must not silently fall through as "nothing to report" —
  # for a mechanism whose only job is surfacing a question, an unparseable
  # comparison is itself something to surface, not swallow.
  # changes_meaning_version genuinely returns empty for a malformed
  # (present but non-numeric) field, distinct from its own "1" default for
  # a field that's simply absent (#261 round 2) — so this branch is a real
  # catch, not dead code behind a fallback that already sanitized its way
  # past it.
  case "$current_version" in
    ''|*[!0-9]*)
      echo "warning: pending-changes couldn't read $id's meaning version from CHANGES.md (got \"$current_version\") — skipping the meaning-version check for this row." >&2
      return 0 ;;
  esac
  case "$answered_version" in
    ''|*[!0-9]*)
      echo "warning: pending-changes couldn't read $id's answered meaning version from $answers (got \"$answered_version\") — skipping the meaning-version check for this row." >&2
      return 0 ;;
  esac
  if [ "$current_version" -gt "$answered_version" ]; then
    if [ "$applies" -eq 1 ]; then
      resurfaced+=("$id|$answered_version|$current_version")
    else
      narrowed+=("$id|$answered_version|$current_version")
    fi
  fi
}

iterate_all_entries "$workflow_dir" collect_pending

if [ ${#pending[@]} -gt 0 ]; then
  echo "Pending workflow changes for this project (see CHANGES.md in spec-driven-guardrails):"
  for id in "${pending[@]}"; do
    echo "  - $id — $(entry_question "$id")"
  done
  # Instruction matches whichever format is actually in play (W42/#114):
  # yes/no in the new file, ja/nee if this project hasn't migrated yet.
  case "$answers" in
    */WORKFLOW-ADOPTIE.md) echo "Record a ja/nee answer per change in WORKFLOW-ADOPTIE.md." ;;
    *) echo "Record a yes/no answer per change in WORKFLOW-ADOPTION.md." ;;
  esac
fi

# #254: a row already answered, but whose meaning has since been
# materially tightened — re-surfaced separately from "never answered"
# (above), since the project *did* make a decision, just against an
# older meaning. Never blocking (same fail-open spirit as the rest of
# this script), always visible.
if [ ${#resurfaced[@]} -gt 0 ]; then
  echo "Answered, but the meaning has changed since (see CHANGES.md in spec-driven-guardrails):"
  for entry in "${resurfaced[@]}"; do
    id="${entry%%|*}"
    rest="${entry#*|}"
    old_version="${rest%%|*}"
    new_version="${rest#*|}"
    echo "  - $id — answered under meaning v$old_version, now v$new_version — $(entry_question "$id")"
  done
  echo "Re-confirm each row above: keep the answer if it still holds, change it if it"
  echo "doesn't, and add \"(meaning v<N>)\" to the row so it isn't asked again for the"
  echo "same version."
fi

# #258: the mirror image of the resurfaced block above — a row this
# project already answered, whose "Applies if" predicate no longer holds
# for it. Unlike "resurfaced", the answer itself isn't necessarily stale;
# the precondition that made the question relevant is what changed. Still
# never blocking, still always visible, same fail-open spirit.
if [ ${#narrowed[@]} -gt 0 ]; then
  echo "Answered before, but this project may no longer be asked (see CHANGES.md in spec-driven-guardrails):"
  for entry in "${narrowed[@]}"; do
    id="${entry%%|*}"
    rest="${entry#*|}"
    old_version="${rest%%|*}"
    new_version="${rest#*|}"
    echo "  - $id — answered under meaning v$old_version, now v$new_version, and its 'Applies if'" \
      "condition no longer matches this project — $(entry_question "$id")"
  done
  echo "Check why: if this project genuinely no longer needs to answer this, add"
  echo "\"(meaning v<N>)\" to the row so it isn't reported again for the same version. If"
  echo "something in this project changed that shouldn't have, that's worth investigating"
  echo "instead."
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
      # <<< here-string, not a piped printf | grep -q: SIGPIPE/pipefail
      # race, see issue #218.
      elif ! grep -qF "$migration_marker" <<<"$existing_bodies"; then
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
