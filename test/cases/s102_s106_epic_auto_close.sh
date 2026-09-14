#!/usr/bin/env bash
# S102-S106 — An epic auto-closes once every issue naming it as its Epic
# is closed; stays open otherwise; never crashes on malformed input.
# Covers: F20

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

script="$TEST_REPO_ROOT/epic-auto-close.sh"
[ -x "$script" ] || { fail "S102 — epic-auto-close.sh is missing or not executable"; test_done; }

fixtures="$SANDBOX/fixtures"
mkdir -p "$fixtures/body" "$fixtures/state"

set_body() { printf '%s' "$2" > "$fixtures/body/$1"; }
set_state() { printf '%s' "$2" > "$fixtures/state/$1"; }
set_issue_list() { printf '%s' "$1" > "$fixtures/issue-list.json"; }

fakebin="$(fake_gh_bin '
case "$1 $2" in
  "issue view")
    n="$3"
    case "$*" in
      *"--json body"*)
        f="'"$fixtures"'/body/$n"
        [ -f "$f" ] && { cat "$f"; exit 0; }
        exit 1 ;;
      *"--json state"*)
        f="'"$fixtures"'/state/$n"
        [ -f "$f" ] && { cat "$f"; exit 0; }
        exit 1 ;;
    esac
    exit 1 ;;
  "issue list")
    f="'"$fixtures"'/issue-list.json"
    [ -f "$f" ] && { cat "$f"; exit 0; }
    exit 1 ;;
  "issue close")
    [ -f "'"$fixtures"'/close-should-fail" ] && exit 1
    n="$3"
    shift 3
    printf "%s|%s\n" "$n" "$*" >> "'"$fixtures"'/closed-log"
    exit 0 ;;
esac
exit 1
')"

run() {
  PATH="$fakebin:$PATH" "$script" "$1" 2>&1
}

closed_log() { cat "$fixtures/closed-log" 2>/dev/null; }
reset_log() { rm -f "$fixtures/closed-log"; }

# AC3 — a non-work-item issue (no Epic field) does nothing.
set_body 30 "Just a plain bug report, no epic field at all."
reset_log
output="$(run 30)"; status=$?
[ "$status" -eq 0 ] || fail "S102/AC3 — plain issue close exited $status: $output"
[ -z "$(closed_log)" ] || fail "S102/AC3 — an epic was closed for an issue with no Epic field"

# AC5 (malformed) — a work item naming itself as its own epic is skipped.
set_body 31 "**Epic:** #31"
reset_log
output="$(run 31)"; status=$?
[ "$status" -eq 0 ] || fail "S102/self-reference — exited $status: $output"
[ -z "$(closed_log)" ] || fail "S102/self-reference — an epic was closed"

# AC5 (dangling) — the named epic doesn't exist / can't be looked up.
set_body 32 "**Epic:** #999"
reset_log
output="$(run 32)"; status=$?
[ "$status" -eq 0 ] || fail "S102/dangling epic — exited $status: $output"
[ -z "$(closed_log)" ] || fail "S102/dangling epic — an epic was closed"

# AC4 — an already-closed epic is left alone (no duplicate close attempt).
set_body 40 "**Epic:** #10"
set_state 10 "CLOSED"
reset_log
output="$(run 40)"; status=$?
[ "$status" -eq 0 ] || fail "S102/AC4 — exited $status: $output"
[ -z "$(closed_log)" ] || fail "S102/AC4 — a close was attempted on an already-closed epic"

# AC2 — closing a work item with an open sibling leaves the epic open.
set_body 50 "**Epic:** #20"
set_body 51 "**Epic:** #20"
set_state 20 "OPEN"
set_issue_list '[
  {"number": 20, "state": "OPEN",   "body": "the epic itself, no Epic field"},
  {"number": 50, "state": "CLOSED", "body": "**Epic:** #20"},
  {"number": 51, "state": "OPEN",   "body": "**Epic:** #20"}
]'
reset_log
output="$(run 50)"; status=$?
[ "$status" -eq 0 ] || fail "S102/AC2 — exited $status: $output"
[ -z "$(closed_log)" ] || fail "S102/AC2 — the epic closed while a sibling work item is still open"

# AC1 — closing the last open work item closes the epic, with both
# work items named in the comment.
set_body 60 "**Epic:** #21"
set_body 61 "**Epic:** #21"
set_state 21 "OPEN"
set_issue_list '[
  {"number": 21, "state": "OPEN",   "body": "the epic itself, no Epic field"},
  {"number": 60, "state": "CLOSED", "body": "**Epic:** #21"},
  {"number": 61, "state": "CLOSED", "body": "**Epic:** #21"}
]'
reset_log
output="$(run 61)"; status=$?
[ "$status" -eq 0 ] || fail "S102/AC1 — exited $status: $output"
log="$(closed_log)"
case "$log" in
  21\|*) ;;
  *) fail "S102/AC1 — epic #21 was not closed (log: $log)" ;;
esac
assert_contains "S102/AC1 — comment names #60" "#60" "$log"
assert_contains "S102/AC1 — comment names #61" "#61" "$log"

# A failed `gh issue close` call (network blip, permissions) is reported
# as a loud failure, not silently treated as success — found during
# pre-merge-review of PR #220.
touch "$fixtures/close-should-fail"
output="$(run 61)"; status=$?
rm -f "$fixtures/close-should-fail"
[ "$status" -ne 0 ] || fail "S102/close-failure — a failed gh issue close was reported as success"

# gh missing entirely: a loud, non-zero failure, not a silent no-op — this
# script has no fail-open the way the merge guard does (see its own header
# comment for why).
nogh="$(path_without_gh)"
output="$(PATH="$nogh" "$script" 60 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "S102 — gh missing gave exit 0 instead of a loud failure"

test_done
