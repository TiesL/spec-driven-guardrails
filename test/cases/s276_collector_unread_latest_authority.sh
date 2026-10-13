#!/usr/bin/env bash
# S276 — unread sources cannot certify latest model authority.
# Covers: F27, F34, F39
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
. "$TEST_REPO_ROOT/test/fixtures/collector-v2-helpers.sh"
positive_done='<!-- pre-merge-review:done sha=6e00a8c38bf18f19cd53084b5c77ae476c1e74e6 -->'
authority_base() {
 cv_base
 cv_pr "$(cv_mark Discovery)
$(cv_mark Planning)
$(cv_mark Test)
$(cv_mark Implementation)
$(cv_mark Review)
$positive_done" "${1:-Closes #265}" "${2:-$cv_early}"
 cv_rows comments
}
for title in 'Closes #265' 'Closes #265, closes #266'; do
 for review in claude-sonnet-5 claude-opus-5; do
  authority_base "$title"
  cv_rows comments "$cv_late" "$(cv_mark Review "$review")"
  export CV_FAIL_FILE=issue265
  cv_run
  cv_status 1 indeterminate; cv_status 2 indeterminate; cv_has 1 'lookup failed'; cv_has 2 'lookup failed'; cv_has 1 latest; cv_has 2 latest
  cv_status 3 evidenced
  [ "$(grep -cFx issue265 "$CV_FAILURE_LOG")" = 1 ] || fail 'unread issue adapter not reached exactly once'
  [ "$(grep -cF 'issues/265/comments ' "$CV_LOG")" = 1 ] || fail 'closing-issue lookup bypassed'
 done
done
# Failure is absent when actual closing source succeeds, including an empty array.
authority_base; cv_run; cv_status 1 evidenced; cv_status 2 evidenced; cv_status 3 evidenced
[ ! -s "$CV_FAILURE_LOG" ] || fail 'empty successful issue confused with failure'
authority_base 'No closing reference'; export CV_FAIL_FILE=issue265; cv_run
cv_status 1 evidenced; cv_status 2 evidenced; cv_status 3 evidenced
[ ! -s "$CV_FAILURE_LOG" ] || fail 'non-closing issue was fetched'
# Actual source dates, not unconditional PR priority, decide readable candidates.
bad='<!-- model-record: stage=Planning -->
<!-- model-record: stage=Review -->'
cv_older=2026-10-01T09:00:00Z
authority_base; cv_rows issue265 "$cv_older" "$bad"; cv_run
cv_status 1 evidenced; cv_status 2 evidenced; cv_status 3 evidenced
authority_base; cv_rows issue265 "$cv_late" "$bad"; cv_run
cv_status 1 indeterminate; cv_status 2 indeterminate; cv_status 3 evidenced
cv_has 1 stage=Planning; cv_has 2 stage=Review; cv_has 1 'no quoted, non-blank model'; cv_has 2 'no quoted, non-blank model'
for review in claude-sonnet-5 claude-opus-5; do
 authority_base; cv_rows issue265 "$cv_late" "$(cv_mark Review "$review")"; cv_run
 cv_status 1 evidenced; cv_status 3 evidenced
 if [ "$review" = claude-sonnet-5 ]; then cv_status 2 evidenced; else cv_status 2 unverifiable-from-artifacts; cv_has 2 claude-opus-5; cv_has 2 claude-sonnet-5; fi
 cv_rows issue265 "$cv_older" "$(cv_mark Review "$review")"; cv_run; cv_status 2 evidenced
done
# Newest good Planning is cited; an older issue cannot displace the PR model.
authority_base; cv_rows issue265 "$cv_late" "$(cv_mark Planning claude-opus-5)"; cv_run
cv_status 1 evidenced; cv_has 1 'Planning=`claude-opus-5`'
cv_rows issue265 "$cv_older" "$(cv_mark Planning claude-opus-5)"; cv_run
cv_status 1 evidenced; cv_absent 1 claude-opus-5
# Successful empty issue restores the readable differing-model outcome.
authority_base; cv_rows comments "$cv_late" "$(cv_mark Review claude-opus-5)"; cv_run
cv_status 2 unverifiable-from-artifacts
# Done-marker absence remains its existing independent incomplete-lookup result.
authority_base; cv_pr "$(cv_mark Discovery)
$(cv_mark Planning)
$(cv_mark Test)
$(cv_mark Implementation)
$(cv_mark Review)" 'Closes #265'; export CV_FAIL_FILE=issue265; cv_run
cv_status 3 indeterminate; cv_has 3 'absence'
# Both PR comments and reviews participate in the same latest uncertainty.
for file in comments reviews; do
 authority_base 'No closing reference'; export CV_FAIL_FILE="$file"; cv_run
 cv_status 1 indeterminate; cv_status 2 indeterminate; cv_status 3 evidenced
 [ "$(grep -cFx "$file" "$CV_FAILURE_LOG")" = 1 ] || fail 'PR source failure not reached'
done
PATH="$SANDBOX/bin:$PATH" gh api unexpected --jq . >/dev/null 2>&1
[ -s "$CV_UNEXPECTED" ] || fail 'unexpected-call witness not reached'
test_done
