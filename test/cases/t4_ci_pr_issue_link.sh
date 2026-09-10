#!/usr/bin/env bash
# T4 — CI check "PR references issue" (link 3, hard block).
# Dekt: F13
#
# templates/check-pr-issue-link.sh judges only the PR that triggers the CI
# run (W19b) — no audit over history, that would keep failing forever on
# the 27 issue-less PRs from before this work item.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

script="$TEST_REPO_ROOT/templates/check-pr-issue-link.sh"
[ -x "$script" ] || { fail "T4 — templates/check-pr-issue-link.sh is missing or not executable"; test_klaar; }

sandbox_create
trap sandbox_destroy EXIT

fixtures="$SANDBOX/fixtures"
mkdir -p "$fixtures"

fakebin="$(fake_gh_bin '
nummer="$3"
bestand="'"$fixtures"'/$nummer"
if [ -f "$bestand" ]; then
  cat "$bestand"
  exit 0
fi
exit 1
')"

# AC2 — a PR without a linked issue fails, with the PR number in the message.
echo 0 > "$fixtures/42"
uitvoer="$(PATH="$fakebin:$PATH" "$script" 42 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "T4/AC2 — PR without a linked issue gave exit 0"
assert_contains "T4/AC2 — the PR number is in the message" "42" "$uitvoer"

# AC3 — a PR with a linked issue passes.
echo 1 > "$fixtures/43"
uitvoer="$(PATH="$fakebin:$PATH" "$script" 43 2>&1)"; status=$?
[ "$status" -eq 0 ] || fail "T4/AC3 — PR with a linked issue gave exit $status: $uitvoer"

# AC4 — only the current PR is judged: PR 42 (issue-less, already checked
# above) still sits that way in the fixtures, and a call for PR 43 does not
# touch that.
uitvoer="$(PATH="$fakebin:$PATH" "$script" 43 2>&1)"; status=$?
[ "$status" -eq 0 ] || fail "T4/AC4 — the earlier PR 42 affected the judgment of PR 43"

# No fail-open on unexpected gh output (found in pre-merge-review on
# PR #70): "null" or other junk instead of a number must not silently let
# this hard block pass.
echo null > "$fixtures/44"
uitvoer="$(PATH="$fakebin:$PATH" "$script" 44 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "T4 — non-numeric gh output ('null') gave exit 0 instead of a hard error"

test_klaar
