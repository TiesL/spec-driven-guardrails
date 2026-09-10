#!/usr/bin/env bash
# S52, S53, S59 — CI detects commits on main that do not come from a PR.
# Covers: F17

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

script="$TEST_REPO_ROOT/templates/check-main-via-pr.sh"
[ -x "$script" ] || { fail "S52 — templates/check-main-via-pr.sh is missing or not executable"; test_klaar; }

sandbox_create
trap sandbox_destroy EXIT

fakebin="$(fake_gh_bin '
case "$*" in
  "api repos/{owner}/{repo}/commits/zonder-pr/pulls --jq length")
    echo 0; exit 0 ;;
  "api repos/{owner}/{repo}/commits/met-pr/pulls --jq length")
    echo 1; exit 0 ;;
  "api repos/{owner}/{repo}/commits/onbekend/pulls --jq length")
    exit 1 ;;
esac
exit 1
')"

# S52 — a commit without a PR is reported, with the commit in the message.
uitvoer="$(PATH="$fakebin:$PATH" "$script" zonder-pr 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "S52 — a commit without a PR gave exit 0"
assert_contains "S52 — the message mentions the commit" "zonder-pr" "$uitvoer"

# S52 — a merge commit that does come from a PR is let through.
uitvoer="$(PATH="$fakebin:$PATH" "$script" met-pr 2>&1)"; status=$?
[ "$status" -eq 0 ] || fail "S52 — a commit with a PR gave exit $status: $uitvoer"

# S53 — the check does not look at history: each call judges exactly the
# given SHA, nothing before or after it. Demonstrated by "zonder-pr" and
# "met-pr" independently giving their own correct outcome regardless of order.
uitvoer="$(PATH="$fakebin:$PATH" "$script" met-pr 2>&1)"; status=$?
[ "$status" -eq 0 ] || fail "S53 — the second call for met-pr deviated from the first"

# S59 — if the origin cannot be established, the check fails, with the
# reason given. Deliberately the opposite of the local git hooks (S58).
uitvoer="$(PATH="$fakebin:$PATH" "$script" onbekend 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "S59 — an unknown origin gave exit 0 (should fail, no fail-open)"
assert_contains "S59 — the message mentions that the origin could not be established" "couldn't establish" "$uitvoer"

# S59 — even without gh the check fails (no fail-open, unlike
# the local hooks).
padzondergh="$(pad_zonder_gh)"
uitvoer="$(PATH="$padzondergh" "$script" zonder-pr 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "S59 — without gh the check gave exit 0 instead of failing"

test_klaar
