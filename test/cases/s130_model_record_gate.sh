#!/usr/bin/env bash
# S130 — stage presence, title-only closing references, REST reviews and warnings.
# Covers: F27
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
. "$TEST_REPO_ROOT/test/fixtures/gate-v2-helpers.sh"
v2_base; v2_run; clean
v2_comments comments-246.json; v2_comments comments-239.json
v2_run
for stage in Discovery Planning Test Implementation; do has "no record found for stage $stage"; done
absent 'no record found for stage Review'
v2_base; v2_comments reviews-246.json
v2_pr 'Closes #239' "$(mr Review)"
v2_run; clean
v2_base; export FAKE_GH_FAIL=1; v2_run
[ -n "$v2_err" ] || fail 'fetch failure needs stderr warning'
absent 'no record found'; unset FAKE_GH_FAIL
v2_path="$(path_without_gh)"; v2_run "$v2_yes"
has 'role-play-unchecked:'
assert_contains 'no gh warning' "can't find gh" "$v2_err"
test_done
