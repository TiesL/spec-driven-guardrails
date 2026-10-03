#!/usr/bin/env bash
# S198 — role-label-staleness.sh recognises a stage marker whose attribute
# values contain `>`, `-->` or `<!--`, through the shared marker parser.
# Covers: F39
#
# Issue #392, round 3 of the PR #397 review (low finding): the script matched
# markers with `[^>]*-->`, so a Review marker with `floor-basis="a > b"` was
# invisible to it and a stale `role:architect` label read as in-sync.
# Behaviour only: the verdict must be `stale` (the marker's stage detected).

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
    *" — stale "*) : ;;
    *) fail "S198 — a Review marker with '$v' in floor-basis must still be detected (role:architect is stale), got: $verdict" ;;
  esac
  case "$verdict" in
    *indeterminate*) fail "S198 — '$v': the marker is well-formed, not malformed, got: $verdict" ;;
  esac
done

# a label AT the evidenced stage stays in-sync with such a marker
verdict_for role:reviewer '<!-- model-record: stage=Review model="claude-sonnet-5" effort="medium" floor-basis="opus > sonnet" -->'
case "$verdict" in
  *" — in-sync "*) : ;;
  *) fail "S198 — role:reviewer with a stage=Review marker (floor-basis with '>') must be in-sync, got: $verdict" ;;
esac

test_done
