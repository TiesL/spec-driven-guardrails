#!/usr/bin/env bash
# S131 — Finding carry-forward gate (#241 AC2): an open finding from the
# previous review round must reappear in the next one, not vanish because
# that round ran fresh-context.
# Covers: F9
#
# Found via #238 (portfolio-mgt-agents PR #4): round 1 flagged a missing
# Decision Log entry; round 2 (fresh context) never carried it forward;
# the PR merged 17 seconds later.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

script="$TEST_REPO_ROOT/skills/pre-merge-review/finding-carryforward-gate.sh"
[ -x "$script" ] || { fail "S131 — skills/pre-merge-review/finding-carryforward-gate.sh is missing or not executable"; test_done; }

sandbox_create
trap sandbox_destroy EXIT

# Case 1: round 1 left "missing-decision-log" open; round 2 dropped it
# entirely. That must be reported.
fakebin_dropped="$(fake_gh_bin '
case "$*" in
  "pr view 246 --json comments --jq .comments[] | select(.body | contains(\"pre-merge-review:done\")) | .body")
    printf "round 1 findings:\n- missing Decision Log entry\n<!-- finding:missing-decision-log status=open -->\n<!-- pre-merge-review:done sha=aaa -->\n"
    printf "round 2 findings:\nnone\n<!-- pre-merge-review:done sha=bbb -->\n"
    exit 0 ;;
esac
exit 1
')"

output_dropped="$(PATH="$fakebin_dropped:$PATH" "$script" 246)"
case "$output_dropped" in
  *"missing-decision-log"*"missing from this one"*) : ;;
  *) fail "S131 — expected a carry-forward finding for missing-decision-log, got: $output_dropped" ;;
esac

# Case 2: round 2 explicitly re-flags it as still open — not dropped, no
# finding.
fakebin_carried="$(fake_gh_bin '
case "$*" in
  "pr view 246 --json comments --jq .comments[] | select(.body | contains(\"pre-merge-review:done\")) | .body")
    printf "round 1 findings:\n- missing Decision Log entry\n<!-- finding:missing-decision-log status=open -->\n<!-- pre-merge-review:done sha=aaa -->\n"
    printf "round 2 findings:\n- still missing Decision Log entry\n<!-- finding:missing-decision-log status=open -->\n<!-- pre-merge-review:done sha=bbb -->\n"
    exit 0 ;;
esac
exit 1
')"

output_carried="$(PATH="$fakebin_carried:$PATH" "$script" 246)"
[ -z "$output_carried" ] || fail "S131 — expected no findings when the prior round's finding is re-flagged, got: $output_carried"

# Case 3: round 2 marks it resolved — also not dropped, no finding.
fakebin_resolved="$(fake_gh_bin '
case "$*" in
  "pr view 246 --json comments --jq .comments[] | select(.body | contains(\"pre-merge-review:done\")) | .body")
    printf "round 1 findings:\n- missing Decision Log entry\n<!-- finding:missing-decision-log status=open -->\n<!-- pre-merge-review:done sha=aaa -->\n"
    printf "round 2: fixed\n<!-- finding:missing-decision-log status=resolved -->\n<!-- pre-merge-review:done sha=bbb -->\n"
    exit 0 ;;
esac
exit 1
')"

output_resolved="$(PATH="$fakebin_resolved:$PATH" "$script" 246)"
[ -z "$output_resolved" ] || fail "S131 — expected no findings when the prior round's finding is marked resolved, got: $output_resolved"

# Case 4: only one review round so far -> nothing to carry forward.
fakebin_first="$(fake_gh_bin '
case "$*" in
  "pr view 246 --json comments --jq .comments[] | select(.body | contains(\"pre-merge-review:done\")) | .body")
    printf "round 1 findings:\n- missing Decision Log entry\n<!-- finding:missing-decision-log status=open -->\n<!-- pre-merge-review:done sha=aaa -->\n"
    exit 0 ;;
esac
exit 1
')"

output_first="$(PATH="$fakebin_first:$PATH" "$script" 246)"
[ -z "$output_first" ] || fail "S131 — expected no findings with only one review round, got: $output_first"

# Case 5: no gh on PATH -> fails open, exit 0, warning.
path_without_gh="$(path_without_gh)"
output_nogh="$(PATH="$path_without_gh" "$script" 246 2>&1)"; status_nogh=$?
[ "$status_nogh" -eq 0 ] || fail "S131 — without gh the gate gave exit $status_nogh instead of 0"
assert_contains "S131 — a warning appears without gh" "warning" "$output_nogh"

test_done
