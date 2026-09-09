#!/usr/bin/env bash
# pending-changes.sh — Reports which adoptable changes from CHANGES.md
# still have no answer in a project's WORKFLOW-ADOPTIE.md.
#
# Usage:
#   ./pending-changes.sh [/path/to/project]   # default: current directory
#
# Called by the SessionStart hook (see settings/session-hooks.json). Prints
# nothing when nothing is pending, and always ends with exit 0 — a hook
# must never block a session.
#
# A change is pending when its "Van toepassing als" predicate is true *and*
# there's no row for that ID in WORKFLOW-ADOPTIE.md. So a row's absence
# means "hasn't applied yet": if the condition later becomes true, the
# question surfaces on its own.

set -uo pipefail

workflow_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${1:-.}" 2>/dev/null && pwd)" || exit 0
changes="$workflow_dir/CHANGES.md"

# shellcheck source=lib/changes.sh
. "$workflow_dir/lib/changes.sh"
# shellcheck source=lib/nfr.sh
. "$workflow_dir/lib/nfr.sh"
antwoorden="$project_dir/WORKFLOW-ADOPTIE.md"

[ -f "$changes" ] || exit 0

# shellcheck disable=SC2329  # called from verzamel_openstaand
beantwoord() {
  [ -f "$antwoorden" ] && grep -q "^| *$1 *|" "$antwoorden"
}

openstaand=()

# Callback for itereer_entries. `standaard` is deliberately unused here: an
# unanswered question is pending regardless of whether it started as `ja`
# or `vraag`. adopt.sh does do something with that same field — see the
# callback there.
# shellcheck disable=SC2329  # called indirectly, via itereer_entries
verzamel_openstaand() {
  local id="$1" predicaat="$3"
  if predicaat_waar "$predicaat" "$project_dir" && ! beantwoord "$id"; then
    openstaand+=("$id")
  fi
}

itereer_alle_entries "$workflow_dir" verzamel_openstaand

if [ ${#openstaand[@]} -gt 0 ]; then
  echo "Pending workflow changes for this project (see CHANGES.md in spec-driven-guardrails):"
  for id in "${openstaand[@]}"; do
    vraag="$(awk -v id="## $id" '
      $0 == id { in_entry = 1; next }
      in_entry && /\*\*Vraag:\*\*/ {
        sub(/.*\*\*Vraag:\*\* */, ""); print; exit
      }
      in_entry && /^## / { exit }
    ' "$changes")"
    # If the ID isn't in CHANGES.md, it comes from the NFR register.
    if [ -z "$vraag" ]; then
      vraag="$(nfr_vraag "$workflow_dir/nfr" "$id")"
    fi
    echo "  - $id — $vraag"
  done
  echo "Record a yes/no answer per change in WORKFLOW-ADOPTIE.md."
fi

# A seeded row is not yet a decision. adopt.sh sets every applicable
# `Standaard: ja` change to "ja — vereist onderbouwing": a provisional
# stamp. beantwoord() only sees *that* a row exists, never what's in it, so
# without this signal a freshly adopted project would report nothing
# pending while seventeen provisional stamps sit there.
#
# beantwoord() is deliberately not changed for this: that would change the
# pending set and thereby break R9, the regression test that guards that no
# project ever gets asked a question again. This exists alongside it
# instead.
#
# Phased substantiation is the premise (see F6): not everything at once,
# but on first contact with the topic. This is gate 3 — the signal stays
# visible until a row is genuinely answered.
if [ -f "$antwoorden" ]; then
  # No `|| echo 0`: grep -c itself already prints "0" on zero matches, and
  # also returns exit status 1. Those two together yield the string "0\n0",
  # which trips up the comparison below. The ${wachtend:-0} fallback covers
  # the case where grep writes nothing to stdout at all, for example on
  # missing read permissions.
  #
  # Only table rows count, the same way beantwoord() anchors on the ID
  # column: a stray note above or below the table that happens to contain
  # the same words isn't a pending substantiation.
  wachtend="$(grep -c '^|.*vereist onderbouwing' "$antwoorden" 2>/dev/null)"
  if [ "${wachtend:-0}" -gt 0 ]; then
    echo "$wachtend row(s) in WORKFLOW-ADOPTIE.md are still waiting on substantiation."
    echo "Replace the provisional stamp with a reasoning grounded in this project,"
    echo "or change the row to 'nee' with a reason — while you're already on the topic."
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
  ontbrekend=""
  for skill_pad in "$workflow_dir"/skills/*/; do
    [ -d "$skill_pad" ] || continue
    skill="$(basename "$skill_pad")"
    if [ ! -e "$project_dir/.claude/skills/$skill" ]; then
      # Comma-separated: a skill name with a space in it would otherwise be
      # indistinguishable from multiple separate names.
      if [ -n "$ontbrekend" ]; then
        ontbrekend="$ontbrekend, $skill"
      else
        ontbrekend="$skill"
      fi
    fi
  done
  if [ -n "$ontbrekend" ]; then
    echo "This project is missing the skill(s): $ontbrekend."
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
  echo "  git checkout -b feature/<name>"
fi

# If the local checkout lags behind, the list above may be incomplete.
# Only report, don't pull automatically — a hook shouldn't mutate anything.
if git -C "$workflow_dir" rev-parse --verify --quiet origin/main >/dev/null 2>&1; then
  achter="$(git -C "$workflow_dir" rev-list --count HEAD..origin/main 2>/dev/null || echo 0)"
  if [ "${achter:-0}" -gt 0 ]; then
    echo "Note: spec-driven-guardrails is $achter commit(s) behind origin/main — run 'git pull' there."
  fi
fi

exit 0
