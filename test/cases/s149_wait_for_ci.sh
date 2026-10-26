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

# ---------------------------------------------------------------------------
# Cases 7-13 (#562): the timing is derived from the median of recent
# successful CI runs instead of the hard-coded 300s/60s. A fake `sleep`
# (records its argument, returns at once) and a fake `gh` (history from
# $FAKE_HIST, then a pr-checks answer that is pending twice) stand in for
# the clock and for gh+jq. The real date conversion in gh's jq is covered
# by the Developer's live smoke, not by this suite.

fakesleep_dir="$SANDBOX/fakesleep"
mkdir -p "$fakesleep_dir"
cat > "$fakesleep_dir/sleep" <<'SLEEP'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_SLEEP_LOG"
echo "SLEEP:$*"
exit 0
SLEEP
chmod +x "$fakesleep_dir/sleep"

fakebin_t="$(fake_gh_bin '
case "$*" in
  "run list "*)
    echo "$*" >> "$FAKE_ARGV_LOG"
    [ "${FAKE_HIST_RC:-0}" -eq 0 ] || { echo "gh: boom" >&2; exit "$FAKE_HIST_RC"; }
    printf "%s" "$FAKE_HIST"
    exit 0 ;;
  "pr checks "*)
    n="$(cat "$FAKE_COUNTER")"
    if [ "$n" -lt 2 ]; then
      echo $((n+1)) > "$FAKE_COUNTER"
      printf "check\tIN_PROGRESS\n"
    else
      printf "check\t%s\n" "${FAKE_FINAL:-SUCCESS}"
    fi
    exit 0 ;;
esac
exit 1
')"

# run_wait <history-lines, newline separated> [VAR=value ...]
# Sets T_OUT, T_STATUS, T_SLEEPS (space separated), T_ARGV (run list calls).
# FAKE_HIST_RC and FAKE_FINAL may be passed as VAR=value arguments.
run_wait() {
  local hist="$1"; shift
  export FAKE_SLEEP_LOG="$SANDBOX/sleeps.log" FAKE_ARGV_LOG="$SANDBOX/argv.log" FAKE_COUNTER="$SANDBOX/counter"
  rm -f "$FAKE_SLEEP_LOG" "$FAKE_ARGV_LOG"
  echo 0 > "$FAKE_COUNTER"
  T_OUT="$(env -u WAIT_FOR_CI_INITIAL_WAIT -u WAIT_FOR_CI_POLL_INTERVAL -u WAIT_FOR_CI_WORKFLOW \
    FAKE_HIST="$hist" "$@" PATH="$fakesleep_dir:$fakebin_t:$PATH" "$script" 7 2>&1)"; T_STATUS=$?
  T_SLEEPS=""
  [ -f "$FAKE_SLEEP_LOG" ] && T_SLEEPS="$(tr '\n' ' ' < "$FAKE_SLEEP_LOG" | sed 's/ $//')"
  T_ARGV=""
  [ -f "$FAKE_ARGV_LOG" ] && T_ARGV="$(cat "$FAKE_ARGV_LOG")"
}

expect_sleeps() { # label expected
  [ "$T_SLEEPS" = "$2" ] || fail "S149 — $1: expected sleeps [$2], got [$T_SLEEPS]; output: $T_OUT"
}

nl='
'

# Case 7 (AC1): ten runs, median (1620+1620)/2 = 1620 -> 85% = 1377 first
# check, 5% = 81 poll. Unsorted input. The median and both derived values
# are printed before the first sleep, and the lookup argv starts with the
# pinned prefix.
hist7="1650${nl}1206${nl}1620${nl}1224${nl}1629${nl}1620${nl}1239${nl}1630${nl}1220${nl}1621"
run_wait "$hist7"
expect_sleeps "case 7 median 1620" "1377 81 81"
[ "$T_STATUS" -eq 0 ] || fail "S149 — case 7: expected exit 0, got $T_STATUS: $T_OUT"
before7="${T_OUT%%SLEEP:*}"
assert_contains "S149 — case 7 prints the median before sleeping" "1620" "$before7"
assert_contains "S149 — case 7 prints the first-check delay before sleeping" "1377" "$before7"
assert_contains "S149 — case 7 prints the poll interval before sleeping" "81" "$before7"
case "$T_ARGV" in
  "run list --workflow CI --status success --limit 10 --json createdAt,updatedAt"*) ;;
  *) fail "S149 — case 7: gh run list argv does not start with the pinned prefix: [$T_ARGV]" ;;
esac

# Case 8a (AC2, odd count): five values, the middle one after a NUMERIC
# sort. Lexical sort would give 2000; no sort at all would give 5000-order.
run_wait "5000${nl}900${nl}2000${nl}1100${nl}1200"
expect_sleeps "case 8a odd count, median 1200" "1020 60 60"

# Case 8b (AC2, even count): mean of the middle two with integer
# division: (1565+1580)/2 = 1572 (not 1572.5 or 1573) -> 1336 / 78.
run_wait "1630${nl}1580${nl}1220${nl}1565"
expect_sleeps "case 8b even count, median 1572" "1336 78 78"

# Case 9 (AC2, floor): median 40 -> 34 first check, 5% would be 2 so the
# poll interval is floored at 30.
run_wait "40${nl}40${nl}40${nl}40${nl}40"
expect_sleeps "case 9 poll floor" "34 30 30"

# Case 10 (AC2, outlier): nine runs near 1600 plus one 10800s outlier. The
# median (1605+1610)/2 = 1607 -> 1365 / 80; a mean would give 2526.
run_wait "1590${nl}1595${nl}1600${nl}1600${nl}1605${nl}1610${nl}1615${nl}1620${nl}1625${nl}10800"
expect_sleeps "case 10 outlier ignored" "1365 80 80"

# Case 11 (AC3, AC5): unusable history -> fallback 300 / 60, a one-line
# notice naming "fallback" and the reason, exit code from the checks.
fallback_case() { # label history reason-keyword [VAR=value ...]
  local label="$1" hist="$2" reason="$3"; shift 3
  run_wait "$hist" "$@"
  expect_sleeps "case 11 $label" "300 60 60"
  assert_contains "S149 — case 11 $label notice says fallback" "fallback" "$T_OUT"
  assert_contains "S149 — case 11 $label notice names the reason" "$reason" "$T_OUT"
  assert_contains "S149 — case 11 $label notice states 300" "300" "${T_OUT%%SLEEP:*}"
  assert_contains "S149 — case 11 $label notice states 60" "60" "${T_OUT%%SLEEP:*}"
  [ "$T_STATUS" -eq 0 ] || fail "S149 — case 11 $label: expected exit 0 (checks green), got $T_STATUS: $T_OUT"
}
fallback_case "gh run list fails" "" "failed" FAKE_HIST_RC=1
fallback_case "empty history" "" "only 0"
fallback_case "two runs only" "1600${nl}1700" "only 2"
fallback_case "non-numeric output" "not json at all" "unparseable"
fallback_case "negative value" "-5${nl}1600${nl}1600" "unparseable"
# AC5: a fine history never changes the exit code of a failed check, and a
# fallback does not turn a failed check into success.
run_wait "1620${nl}1620${nl}1620" FAKE_FINAL=FAILURE
[ "$T_STATUS" -ne 0 ] || fail "S149 — case 11: failed check with good history exited 0: $T_OUT"
run_wait "" FAKE_HIST_RC=1 FAKE_FINAL=FAILURE
[ "$T_STATUS" -ne 0 ] || fail "S149 — case 11: failed check with fallback exited 0: $T_OUT"

# Case 12 (AC4): env overrides beat the derived value, per variable.
run_wait "1620${nl}1620${nl}1620" WAIT_FOR_CI_INITIAL_WAIT=2 WAIT_FOR_CI_POLL_INTERVAL=1
expect_sleeps "case 12 both overrides" "2 1 1"
[ -z "$T_ARGV" ] || fail "S149 — case 12: gh run list was called although both values are overridden: [$T_ARGV]"
run_wait "1620${nl}1620${nl}1620" WAIT_FOR_CI_INITIAL_WAIT=7
expect_sleeps "case 12 only INITIAL_WAIT set" "7 81 81"
run_wait "1620${nl}1620${nl}1620" WAIT_FOR_CI_POLL_INTERVAL=5
expect_sleeps "case 12 only POLL_INTERVAL set" "1377 5 5"
run_wait "" WAIT_FOR_CI_INITIAL_WAIT=7 FAKE_HIST_RC=1
expect_sleeps "case 12 override beats the fallback" "7 60 60"

# Case 13 (AC6): three different histories give three different first
# checks; any hard-coded constant (300/60 or otherwise) fails at least two.
run_wait "1620${nl}1620${nl}1620"; first_a="${T_SLEEPS%% *}"; expect_sleeps "case 13 history 1620" "1377 81 81"
run_wait "40${nl}40${nl}40";       first_b="${T_SLEEPS%% *}"; expect_sleeps "case 13 history 40" "34 30 30"
run_wait "1570${nl}1572${nl}1574"; first_c="${T_SLEEPS%% *}"; expect_sleeps "case 13 history 1572" "1336 78 78"
[ "$first_a" != "$first_b" ] && [ "$first_b" != "$first_c" ] && [ "$first_a" != "$first_c" ] \
  || fail "S149 — case 13: first checks not all different ($first_a $first_b $first_c)"
# WAIT_FOR_CI_WORKFLOW selects the workflow name.
run_wait "1620${nl}1620${nl}1620" WAIT_FOR_CI_WORKFLOW=Other
assert_contains "S149 — case 13 uses WAIT_FOR_CI_WORKFLOW" "--workflow Other" "$T_ARGV"

test_done
