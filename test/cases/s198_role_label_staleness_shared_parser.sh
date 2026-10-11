#!/usr/bin/env bash
# S198 — record-v2 rejects forbidden delimiters in attribute values.
# Covers: F39
# #428 rewrites the old shared-parser acceptance case: valid Review controls
# evidence the stage, but forbidden value delimiters are named near-misses.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

script="$TEST_REPO_ROOT/role-label-staleness.sh"
[ -x "$script" ] || { fail "S198 — role-label-staleness.sh is missing or not executable"; test_done; }
sandbox_create
trap sandbox_destroy EXIT
# shellcheck source=../fixtures/role-label-fake-gh.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/role-label-fake-gh.sh"

# run <label-on-the-issue> <marker text on PR #501>: sets verdict
verdict_for() {
  local label="$1" marker="$2" bin
  run_build_fake_gh > "$FAKEGH_OUT" <<GHEOF
__CALL_ISSUE__)
  printf 'LABEL\t$label\n'
  exit 0 ;;
__CALL_ISSUE_COMMENTS__)
  exit 0 ;;
__CALL_REPO_IDENTITY__)
  printf 'owner/repo\n'
  exit 0 ;;
__CALL_TIMELINE__)
  printf 'PR\t501\n'
  exit 0 ;;
__CALL_PR501_TITLEBODY__)
  printf 'TITLE\t\nBODY\tCloses #400\n'
  exit 0 ;;
__CALL_PR501_COMMENTS__)
  printf 'TEXT\t%s\n' '$marker'
  exit 0 ;;
__CALL_PR501_REVIEWS__)
  exit 0 ;;
GHEOF
  bin="$(cat "$FAKEGH_OUT")"
  verdict="$(PATH="$bin:$PATH" "$script" 400 2>/dev/null)"
  verdict_rc=$?
}

# control: a plain Review marker makes role:architect stale
verdict_for role:architect '<!-- model-record: stage=Review model="claude-sonnet-5" effort="medium" floor-basis="ok" -->'
case "$verdict" in
  *" — stale "*) : ;;
  *) fail "S198 control — role:architect behind a stage=Review marker must be stale, got: $verdict" ;;
esac

for v in 'opus > sonnet' 'a --> b' 'a <!-- b' 'x < y -- z' '<!-- x --> > <'; do
  verdict_for role:architect "<!-- model-record: stage=Review model=\"claude-sonnet-5\" effort=\"medium\" floor-basis=\"$v\" -->"
  [ "$verdict_rc" -eq 0 ] || fail "S198 — '$v': exit $verdict_rc"
  case "$verdict" in
    *" — indeterminate "*) : ;;
    *) fail "S198 — a Review marker with '$v' in floor-basis must be named as a near-miss, got: $verdict" ;;
  esac
  case "$verdict" in
    *near-miss*) : ;;
    *) fail "S198 — '$v': near-miss cause absent: $verdict" ;;
  esac
done

# a label AT the evidenced stage stays in-sync with a valid value
verdict_for role:reviewer '<!-- model-record: stage=Review model="claude-sonnet-5" effort="medium" floor-basis="opus exceeds sonnet" -->'
case "$verdict" in
  *" — in-sync "*) : ;;
  *) fail "S198 — role:reviewer with a stage=Review marker (valid floor-basis) must be in-sync, got: $verdict" ;;
esac

test_done
