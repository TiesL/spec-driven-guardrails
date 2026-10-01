#!/usr/bin/env bash
# S157 — The process-multi-agent-roles CHANGES.md entry is well-formed.
# Covers: F37
#
# Issue #369, AC3, plus the CHANGES.md half of AC7's "documented" clause.
# Default and Applies if are read through lib/changes.sh's own
# iterate_entries (the parser adopt.sh and pending-changes.sh share), and
# the PR linkback through pr_links_missing (what ./check runs), so this
# tests what the tools actually see, not a re-parse of our own.
#
# Not testable offline: that the PR field's number is the PR that actually
# delivers #369. Reviewer checks that by REST at review time.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

# shellcheck source=../../lib/changes.sh disable=SC1091
. "$TEST_REPO_ROOT/lib/changes.sh"

sandbox_create
trap sandbox_destroy EXIT

id="process-multi-agent-roles"
changes="$TEST_REPO_ROOT/CHANGES.md"

# Given: exactly one entry with that id.
count="$(grep -cx "## $id" "$changes")"
if [ "$count" -ne 1 ]; then
  fail "S157 — CHANGES.md has $count '## $id' entries, expected exactly 1"
  test_done
fi

# When: the shared parser walks CHANGES.md.
# shellcheck disable=SC2329  # invoked by name, as iterate_entries' callback
capture() {
  if [ "$1" = "$id" ]; then
    printf '%s %s\n' "$2" "$3" > "$SANDBOX/parsed.txt"
  fi
  return 0
}
iterate_entries "$changes" capture 2>"$SANDBOX/parse-warnings.txt"

# Then: Default is question and Applies if is always.
if [ ! -s "$SANDBOX/parsed.txt" ]; then
  fail "S157 — the shared parser yielded no Default/Applies if for $id"
else
  parsed="$(cat "$SANDBOX/parsed.txt")"
  [ "$parsed" = "question always" ] \
    || fail "S157 — parsed Default/Applies if is '$parsed', expected 'question always'"
fi
if grep -qF "$id" "$SANDBOX/parse-warnings.txt"; then
  fail "S157 — the shared parser warned about $id:"
  cat "$SANDBOX/parse-warnings.txt" >&2
fi

# And: ./check's PR-linkback validation does not flag it.
missing="$(pr_links_missing "$changes")"
if grep -qx "$id" <<<"$missing"; then
  fail "S157 — ./check's PR-linkback validation flags $id as missing an https **PR:** field"
fi

# The entry's own text, from its heading up to the next heading or rule.
entry="$(awk -v h="## $id" '
  $0 == h { on = 1; next }
  on && (/^## / || /^---/) { exit }
  on { print }
' "$changes")"

# And: the Question is one line and closed (a yes/no question).
question_line="$(grep -E '^- \*\*Question:\*\*' <<<"$entry")"
next_line="$(awk '/^- \*\*Question:\*\*/ { getline n; print n; exit }' <<<"$entry")"
case "$next_line" in
  '- **'*) ;;
  *) fail "S157 — the Question continues past one line (next line: '$next_line')" ;;
esac
question="${question_line#- \*\*Question:\*\* }"
case "$question" in
  *'?') ;;
  *) fail "S157 — the Question does not end in '?': '$question'" ;;
esac
first_word="${question%% *}"
case "$first_word" in
  Does|Do|Is|Are|Has|Have|Should|Will|Can|Was) ;;
  *) fail "S157 — the Question is not a closed yes/no question (starts with '$first_word')" ;;
esac

# And: the PR field is a full github.com pull-request URL, not a bare number.
if ! grep -qE '^- \*\*PR:\*\* https://github\.com/[^/]+/[^/]+/pull/[0-9]+[[:space:]]*$' <<<"$entry"; then
  fail "S157 — the PR field is not a github.com pull-request URL"
fi

# And (AC7, documented): "Yes means" says the three evidence scripts are run
# by path from the clone, and that a yes means creating the role labels.
yes_means="$(awk '
  /^- \*\*Yes means:\*\*/ { on = 1 }
  on && /^- \*\*/ && !/^- \*\*Yes means:\*\*/ { exit }
  on { print }
' <<<"$entry")"
# shellcheck disable=SC2016  # a literal \$VAR name, not an expansion
for needle in '$SPEC_DRIVEN_GUARDRAILS_DIR/' compliance-evidence.sh role-label-staleness.sh classify-review-depth.sh 'role:'; do
  case "$yes_means" in
    *"$needle"*) ;;
    *) fail "S157 — 'Yes means' does not mention '$needle'" ;;
  esac
done

test_done
