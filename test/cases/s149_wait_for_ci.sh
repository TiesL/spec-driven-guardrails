#!/usr/bin/env bash
# S149 — wait-for-ci.sh enforces the 5min-then-1min CI-polling cadence
# (#265).
# Covers: F33

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

script="$TEST_REPO_ROOT/wait-for-ci.sh"
[ -x "$script" ] || { fail "S149 — wait-for-ci.sh is missing or not executable"; test_done; }

sandbox_create
trap sandbox_destroy EXIT

jq_expr='.[] | "\(.name)\t\(.state)"'

# Case 1: doesn't check before the initial wait elapses, and does after —
# proven with a real (short, overridden) wait rather than mocking sleep,
# so this is a real behavioral proof, not just an argument check.
fakebin1="$(fake_gh_bin '
case "$*" in
  "pr checks 1 --json name,state --jq .[] | \"\(.name)\t\(.state)\"")
    echo "$(date +%s)" >> "'"$SANDBOX"'/calls1.log"
    printf "check\tSUCCESS\n"
    exit 0 ;;
esac
exit 1
')"
start1=$(date +%s)
PATH="$fakebin1:$PATH" WAIT_FOR_CI_INITIAL_WAIT=2 WAIT_FOR_CI_POLL_INTERVAL=1 "$script" 1 >/dev/null 2>&1
end1=$(date +%s)
elapsed1=$((end1 - start1))
[ "$elapsed1" -ge 2 ] || fail "S149 — wait-for-ci.sh returned before the initial wait elapsed (${elapsed1}s)"
[ -f "$SANDBOX/calls1.log" ] || fail "S149 — no call to gh pr checks was recorded at all"

# Case 2: pending, then a real state -> polls until terminal, exits 0 and
# reports success once every check passes.
counter2="$SANDBOX/counter2"
echo 0 > "$counter2"
fakebin2="$(fake_gh_bin '
case "$*" in
  "pr checks 2 --json name,state --jq .[] | \"\(.name)\t\(.state)\"")
    n="$(cat "'"$counter2"'")"
    if [ "$n" -lt 2 ]; then
      echo $((n+1)) > "'"$counter2"'"
      printf "check\tIN_PROGRESS\n"
    else
      printf "check\tSUCCESS\n"
    fi
    exit 0 ;;
esac
exit 1
')"
output2="$(PATH="$fakebin2:$PATH" WAIT_FOR_CI_INITIAL_WAIT=0 WAIT_FOR_CI_POLL_INTERVAL=1 "$script" 2 2>&1)"; status2=$?
[ "$status2" -eq 0 ] || fail "S149 — expected exit 0 once CI went green, got $status2: $output2"
assert_contains "S149 — reports all checks passed" "all checks passed" "$output2"
assert_contains "S149 — the detail line names the check" "check: SUCCESS" "$output2"

# Case 3: a real failure -> exits non-zero, names the failing check.
fakebin3="$(fake_gh_bin '
case "$*" in
  "pr checks 3 --json name,state --jq .[] | \"\(.name)\t\(.state)\"")
    printf "check\tFAILURE\n"
    exit 0 ;;
esac
exit 1
')"
output3="$(PATH="$fakebin3:$PATH" WAIT_FOR_CI_INITIAL_WAIT=0 "$script" 3 2>&1)"; status3=$?
[ "$status3" -ne 0 ] || fail "S149 — expected non-zero exit on a failed check, got: $output3"
assert_contains "S149 — reports the failure" "did not pass" "$output3"
assert_contains "S149 — the detail line names the failing check" "check: FAILURE" "$output3"

# Case 4: no gh on PATH -> exits non-zero, doesn't silently report
# success. path_without_gh() (test/lib.sh), not a plain "/usr/bin:/bin"
# exclusion: on a GitHub Actions runner, gh is itself preinstalled
# somewhere under /usr/bin, so that naive exclusion doesn't actually
# exclude it there — found when this case passed locally but failed in
# CI.
path_without_gh="$(path_without_gh)"
output4="$(PATH="$path_without_gh" WAIT_FOR_CI_INITIAL_WAIT=0 "$script" 4 2>&1)"; status4=$?
[ "$status4" -ne 0 ] || fail "S149 — expected non-zero exit with no gh on PATH, got: $output4"
assert_contains "S149 — names the missing gh" "gh is missing" "$output4"

# Case 5: the lookup itself fails (bad token, network) -> exits non-zero,
# doesn't silently report success.
fakebin5="$(fake_gh_bin '
echo "gh: authentication failed" >&2
exit 1
')"
output5="$(PATH="$fakebin5:$PATH" WAIT_FOR_CI_INITIAL_WAIT=0 "$script" 5 2>&1)"; status5=$?
[ "$status5" -ne 0 ] || fail "S149 — expected non-zero exit when the gh lookup itself fails, got: $output5"
assert_contains "S149 — reports the lookup failure" "couldn't consult" "$output5"

# Case 6 (found during PR #279's pre-merge-review): a PR with zero checks
# at all must not be reported as "all checks passed" — there is nothing
# to have passed, and this script's whole job is answering whether it's
# actually safe to ask for merge confirmation.
fakebin6="$(fake_gh_bin '
case "$*" in
  "pr checks 6 --json name,state --jq .[] | \"\(.name)\t\(.state)\"")
    printf ""
    exit 0 ;;
esac
exit 1
')"
output6="$(PATH="$fakebin6:$PATH" WAIT_FOR_CI_INITIAL_WAIT=0 "$script" 6 2>&1)"; status6=$?
[ "$status6" -ne 0 ] || fail "S149 — a PR with zero checks was reported as passing, got: $output6"
assert_contains "S149 — reports no checks at all" "no checks at all" "$output6"

test_done
