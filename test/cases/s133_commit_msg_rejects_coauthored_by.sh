#!/usr/bin/env bash
# S133 — The native commit-msg hook rejects a Co-Authored-By trailer
# written directly into a commit message (#243 AC1), from any source —
# not only what Claude Code's own attribution.commit setting suppresses.
# Covers: F9
#
# Found via #238 (portfolio-mgt-agents): every commit there carried the
# trailer despite settings/session-hooks.json's attribution.commit: ""
# being correctly symlinked in — that setting suppresses a trailer added
# via Claude's own commit template, not one typed literally into -m.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

hook="$TEST_REPO_ROOT/hooks/commit-msg"
[ -x "$hook" ] || { fail "S133 — hooks/commit-msg is missing or not executable"; test_done; }

sandbox_create
trap sandbox_destroy EXIT

project="$(fresh_project coauthor-trailer)"
adopt "$project"
git -C "$project" commit -q --allow-empty -m start
git -C "$project" checkout -q -b feature/1-numbered

output="$(cd "$project" && git commit -q --allow-empty -m "$(printf 'a change\n\nCo-Authored-By: Someone <someone@example.com>')" 2>&1)"
status=$?
[ "$status" -ne 0 ] || fail "S133 — a commit with a Co-Authored-By trailer was not blocked"
assert_contains "S133 — message names the trailer" "Co-Authored-By" "$output"

# And: a legitimate commit with no trailer proceeds.
if ! git -C "$project" commit -q --allow-empty -m "a clean change" 2>&1; then
  fail "S133 — a legitimate commit with no trailer was blocked"
fi

# And: case-insensitivity (co-authored-by vs Co-Authored-By) is caught too.
output_lower="$(cd "$project" && git commit -q --allow-empty -m "$(printf 'a change\n\nco-authored-by: someone <someone@example.com>')" 2>&1)"
status_lower=$?
[ "$status_lower" -ne 0 ] || fail "S133 — a lowercase co-authored-by trailer was not blocked"

# And: the escape hatch still works, same as the other native hooks.
if ! CLAUDE_WORKFLOW_GUARDRAILS_OFF=1 git -C "$project" commit -q --allow-empty -m "$(printf 'urgent\n\nCo-Authored-By: Someone <someone@example.com>')" 2>&1; then
  fail "S133 — the escape hatch did not let a trailer through"
fi

test_done
