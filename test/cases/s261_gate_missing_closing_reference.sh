#!/usr/bin/env bash
# S261 — gate_missing_closing_reference; #427, independent CLI assertions (A31a/A34a/A37).
# Covers: F27, F38, F39, F40
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
. "$TEST_REPO_ROOT/test/fixtures/gate-v2-helpers.sh"

v2_base; v2_pr '' 'Fixes #999999'; v2_run "$v2_yes"
has 'closing reference #999999 does not exist and was ignored'; has 'no record found for stage Discovery'; has 'role-played: stages missing: Discovery'; absent 'role-play-unchecked:'
v2_merge; [ "$v2_status" = 2 ] || fail "404 missing Discovery must block: $v2_err"
v2_pr '' 'Fixes #999999. Closes #239'; v2_run "$v2_yes"; absent 'role-played:'; absent 'role-play-unchecked:'
v2_merge; [ "$v2_status" = 0 ] || fail "valid issue after typo must permit: $v2_err"
v2_comments comments-239.json; v2_pr '' 'Closes #239'; v2_run "$v2_yes"; has 'role-played: stages missing: Discovery'; absent 'does not exist'; absent 'role-play-unchecked:'

test_done
