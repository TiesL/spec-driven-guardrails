#!/usr/bin/env bash
# S679 — answered process-multi-agent-roles versions resurface once per run until v4; fresh question remains pending (#679).
# Covers: F9, F26, F38, F39, F40
# Seam: real pending-changes.sh and adopt.sh against isolated fixture projects.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT
id=process-multi-agent-roles
question='Does this project carry a change through the five separately dispatched roles'
entry="$(awk '/^## process-multi-agent-roles$/{f=1;next} f && /^## /{exit} f{print}' "$TEST_REPO_ROOT/CHANGES.md")"
grep -qF -- '- **Applies if:** always' <<<"$entry" || fail 'S679 — the row must remain applicable to every project'

for answer in yes no; do
  for version in implicit v1 v2 v3 v4; do
    project="$(fresh_project "answered-$answer-$version")"
    note='original answer'
    [ "$version" = implicit ] || note="confirmed (meaning $version)"
    row="| $id | $answer | 2026-10-01 | $note |"
    printf '%s\n' "$row" > "$project/WORKFLOW-ADOPTION.md"
    first="$("$TEST_REPO_ROOT/pending-changes.sh" "$project" 2>&1)"; status=$?
    [ "$status" -eq 0 ] || fail "S679 $answer/$version — notice blocked the session (exit $status)"
    second="$("$TEST_REPO_ROOT/pending-changes.sh" "$project" 2>&1)"; status=$?
    [ "$status" -eq 0 ] || fail "S679 $answer/$version — repeated notice blocked the session (exit $status)"
    row_lines="$(grep -F "  - $id —" <<<"$first" || true)"
    if [ "$version" = v4 ]; then
      [ -z "$row_lines" ] || fail "S679 $answer/$version — current answer resurfaced: $row_lines"
    else
      old=1; [ "$version" = implicit ] || old="${version#v}"
      expected="  - $id — answered under meaning v$old, now v4 — $question"
      [ "$(grep -cF "$expected" <<<"$row_lines" || true)" -eq 1 ] || fail "S679 $answer/$version — expected one changed-meaning notice, got: $row_lines"
      grep -qF 'Answered, but the meaning has changed since' <<<"$first" || fail "S679 $answer/$version — changed-meaning heading missing"
      [ "$first" = "$second" ] || fail "S679 $answer/$version — notice did not repeat until re-confirmed"
      grep -qF "| $id | $answer |" "$project/WORKFLOW-ADOPTION.md" || fail "S679 $answer/$version — answer was changed by the notice"
      printf '| %s | %s | 2026-10-01 | re-confirmed (meaning v4) |\n' "$id" "$answer" > "$project/WORKFLOW-ADOPTION.md"
      stamped="$("$TEST_REPO_ROOT/pending-changes.sh" "$project" 2>&1)"; status=$?
      [ "$status" -eq 0 ] || fail "S679 $answer/$version — stamped answer blocked the session (exit $status)"
      case "$stamped" in *"  - $id —"*) fail "S679 $answer/$version — notice persisted after v4 stamp";; esac
    fi
    case "$first" in *"Answered before, but this project may no longer be asked"*"$id"*) fail "S679 $answer/$version — always-applicable row was narrowed";; esac
    case "$first" in *"  - $id — $question"*) fail "S679 $answer/$version — answered row appeared as unanswered";; esac
  done
done

fresh="$(fresh_project unanswered)"
adopt "$fresh"
row="$(grep -E '^\| *process-multi-agent-roles *\|' "$fresh/WORKFLOW-ADOPTION.md" || true)"
[ -z "$row" ] || fail "S679 fresh — question-default row was seeded: $row"
out="$("$TEST_REPO_ROOT/pending-changes.sh" "$fresh" 2>&1)"; status=$?
[ "$status" -eq 0 ] || fail "S679 fresh — pending question blocked the session (exit $status)"
grep -qF "  - $id — $question" <<<"$out" || fail 'S679 fresh — ordinary unanswered question missing'
case "$out" in *"$id — answered under meaning"*) fail 'S679 fresh — unanswered row appeared as changed meaning';; esac

test_done
