#!/usr/bin/env bash
# S731 — #724 portability and adoption through delivered text and the public read-only CLI.
# Covers: F77
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT
python_bin="$(command -v python3)"
printf -v fake_body 'exec %q -I %q "$@"' "$python_bin" "$TEST_REPO_ROOT/test/fixtures/backlog-724-gh.py"
fakebin="$(fake_gh_bin "$fake_body")"
export PATH="$fakebin:$PATH"
export BACKLOG_724_NOGH="$(path_without_gh)"
# Remove gh alone: jq remains available when installed in the normal PATH.
jq_bin="$(command -v jq || true)"
[ -z "$jq_bin" ] || ln -s "$jq_bin" "$BACKLOG_724_NOGH/jq"
python3 -I "$TEST_REPO_ROOT/test/fixtures/backlog-724-cases.py" "$TEST_REPO_ROOT" 731 || fail "S731 — CLI obligations absent"
python3 -I "$TEST_REPO_ROOT/test/fixtures/backlog-724-text.py" "$TEST_REPO_ROOT" 731 || fail "S731 — delivered maintenance obligations absent"
# D5: version semantics use the existing parser, not copied comparison logic.
. "$TEST_REPO_ROOT/lib/changes.sh"
[ "$(changes_meaning_version process-issue-tracking "$TEST_REPO_ROOT/CHANGES.md")" = 2 ] || fail 'S731/D5/parser — issue-tracking must resolve to meaning v2'
for answer in yes no; do
  for version in implicit v1; do
    project="$SANDBOX/answer-$answer-$version"
    mkdir -p "$project"
    note='original answer'
    [ "$version" = implicit ] || note='confirmed (meaning v1)'
    printf '| process-issue-tracking | %s | 2026-11-27 | %s |\n' "$answer" "$note" > "$project/WORKFLOW-ADOPTION.md"
    before="$(cat "$project/WORKFLOW-ADOPTION.md")"
    out="$("$TEST_REPO_ROOT/pending-changes.sh" "$project" 2>&1)"; status=$?
    [ "$status" -eq 0 ] || fail "S731/D5/$answer/$version — notice must remain advisory"
    assert_contains "S731/D5/$answer/$version" 'process-issue-tracking — answered under meaning v1, now v2' "$out"
    [ "$(cat "$project/WORKFLOW-ADOPTION.md")" = "$before" ] || fail "S731/D5/$answer/$version — notice changed the answer"
    printf '| process-issue-tracking | %s | 2026-11-27 | re-confirmed (meaning v2) |\n' "$answer" > "$project/WORKFLOW-ADOPTION.md"
    current="$("$TEST_REPO_ROOT/pending-changes.sh" "$project" 2>&1)"
    case "$current" in *'process-issue-tracking — answered under meaning'*) fail "S731/D5/$answer/$version — v2 still resurfaced" ;; esac
  done
done
test_done
