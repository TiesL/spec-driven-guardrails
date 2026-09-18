#!/usr/bin/env bash
# S130 — Model-record gate (#241 AC1): every pipeline stage's model choice
# must carry a machine-readable marker, not just Review.
# Covers: F9
#
# Found via #238's portfolio-mgt-agents audit: only the Review stage ever
# recorded a model in practice — Discovery/Planning/Test/Implementation
# never did, and CHANGES.md's process-model-choice row had no way to
# check for that mechanically.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

script="$TEST_REPO_ROOT/skills/pre-merge-review/model-record-gate.sh"
[ -x "$script" ] || { fail "S130 — skills/pre-merge-review/model-record-gate.sh is missing or not executable"; test_done; }

sandbox_create
trap sandbox_destroy EXIT

# PR carries Review, Planning, Test, Implementation markers; the issue it
# closes carries Discovery's. All five present -> no findings.
fakebin_complete="$(fake_gh_bin '
case "$*" in
  "pr view 246 --json comments --jq .comments[].body")
    printf "%s\n" "<!-- model-record: stage=Planning model=\"Opus\" effort=\"high\" -->"
    printf "%s\n" "<!-- model-record: stage=Test model=\"Sonnet\" effort=\"medium\" -->"
    printf "%s\n" "<!-- model-record: stage=Implementation model=\"Sonnet\" effort=\"medium\" -->"
    printf "%s\n" "<!-- model-record: stage=Review model=\"Opus\" effort=\"high\" -->"
    exit 0 ;;
  "pr view 246 --json closingIssuesReferences --jq .closingIssuesReferences[].number")
    printf "%s\n" "239"
    exit 0 ;;
  "issue view 239 --json comments --jq .comments[].body")
    printf "%s" "<!-- model-record: stage=Discovery model=\"Sonnet\" effort=\"low\" -->"
    exit 0 ;;
esac
exit 1
')"

output_complete="$(PATH="$fakebin_complete:$PATH" "$script" 246)"
[ -z "$output_complete" ] || fail "S130 — expected no findings when all five stages are recorded, got: $output_complete"

# PR carries only Review's marker; the closed issue carries none. Three
# stages missing (Discovery is on the issue and absent; Planning/Test/
# Implementation are missing from the PR).
fakebin_partial="$(fake_gh_bin '
case "$*" in
  "pr view 246 --json comments --jq .comments[].body")
    printf "%s" "<!-- model-record: stage=Review model=\"Opus\" effort=\"high\" -->"
    exit 0 ;;
  "pr view 246 --json closingIssuesReferences --jq .closingIssuesReferences[].number")
    printf "%s\n" "239"
    exit 0 ;;
  "issue view 239 --json comments --jq .comments[].body")
    printf "%s" ""
    exit 0 ;;
esac
exit 1
')"

output_partial="$(PATH="$fakebin_partial:$PATH" "$script" 246)"
for stage in Discovery Planning Test Implementation; do
  case "$output_partial" in
    *"stage $stage"*) : ;;
    *) fail "S130 — expected a missing-record finding for stage $stage, got: $output_partial" ;;
  esac
done
case "$output_partial" in
  *"stage Review"*) fail "S130 — Review is recorded and should not be reported missing, got: $output_partial" ;;
  *) : ;;
esac

# No gh on PATH: fails open, exit 0, just a warning.
path_without_gh="$(path_without_gh)"
output_nogh="$(PATH="$path_without_gh" "$script" 246 2>&1)"; status_nogh=$?
[ "$status_nogh" -eq 0 ] || fail "S130 — without gh the gate gave exit $status_nogh instead of 0"
assert_contains "S130 — a warning appears without gh" "warning" "$output_nogh"

# The per-issue lookup failing (transient, not "issue has no records")
# must warn, not silently misreport Discovery as missing — found during
# PR #249's pre-merge-review, round 2.
fakebin_issue_fails="$(fake_gh_bin '
case "$*" in
  "pr view 246 --json comments --jq .comments[].body")
    printf "%s" "<!-- model-record: stage=Planning model=\"Sonnet\" effort=\"medium\" -->"
    exit 0 ;;
  "pr view 246 --json closingIssuesReferences --jq .closingIssuesReferences[].number")
    printf "%s\n" "239"
    exit 0 ;;
  "issue view 239 --json comments --jq .comments[].body")
    echo "gh: could not resolve to an Issue" >&2
    exit 1 ;;
esac
exit 1
')"

output_issue_fails="$(PATH="$fakebin_issue_fails:$PATH" "$script" 246 2>&1)"
assert_contains "S130 — a warning appears when the issue lookup fails" "warning" "$output_issue_fails"

test_done
