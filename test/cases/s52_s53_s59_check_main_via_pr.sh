#!/usr/bin/env bash
# S52, S53, S59 — CI detects commits on main that do not come from a PR.
# Covers: F17

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

script="$TEST_REPO_ROOT/templates/check-main-via-pr.sh"
[ -x "$script" ] || { fail "S52 — templates/check-main-via-pr.sh is missing or not executable"; test_done; }

sandbox_create
trap sandbox_destroy EXIT

fakebin="$(fake_gh_bin '
case "$*" in
  "api repos/{owner}/{repo}/commits/without-pr/pulls --jq length")
    echo 0; exit 0 ;;
  "api repos/{owner}/{repo}/commits/with-pr/pulls --jq length")
    echo 1; exit 0 ;;
  "api repos/{owner}/{repo}/commits/unknown/pulls --jq length")
    exit 1 ;;
esac
exit 1
')"

# S52 — a commit without a PR is reported, with the commit in the message.
output="$(PATH="$fakebin:$PATH" "$script" without-pr 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "S52 — a commit without a PR gave exit 0"
assert_contains "S52 — the message mentions the commit" "without-pr" "$output"

# S52 — a merge commit that does come from a PR is let through.
output="$(PATH="$fakebin:$PATH" "$script" with-pr 2>&1)"; status=$?
[ "$status" -eq 0 ] || fail "S52 — a commit with a PR gave exit $status: $output"

# S53 — the check does not look at history: each call judges exactly the
# given SHA, nothing before or after it. Demonstrated by "without-pr" and
# "with-pr" independently giving their own correct outcome regardless of order.
output="$(PATH="$fakebin:$PATH" "$script" with-pr 2>&1)"; status=$?
[ "$status" -eq 0 ] || fail "S53 — the second call for with-pr deviated from the first"

# S59 — if the origin cannot be established, the check fails, with the
# reason given. Deliberately the opposite of the local git hooks (S58).
output="$(PATH="$fakebin:$PATH" "$script" unknown 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "S59 — an unknown origin gave exit 0 (should fail, no fail-open)"
assert_contains "S59 — the message mentions that the origin could not be established" "couldn't establish" "$output"

# S59 — even without gh the check fails (no fail-open, unlike
# the local hooks).
path_without_gh="$(path_without_gh)"
output="$(PATH="$path_without_gh" "$script" without-pr 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "S59 — without gh the check gave exit 0 instead of failing"

test_done
