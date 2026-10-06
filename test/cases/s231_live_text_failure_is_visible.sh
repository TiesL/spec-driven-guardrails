#!/usr/bin/env bash
# S231 — a live_text failure is visible in every caller: a model-record: finding in the gate, indeterminate in the collector and in the staleness script.
# Covers: F34, F35, F39
#
# Issue #423 AC3 (slice V2 of #411; A32a "a failure prints nothing on stdout and
# one stderr line, and returns non-zero", A35a R6, D10). Today the gate's main
# path reports the failure, but its role-play path (check_text) ignores it, and
# the collector and the staleness script read an empty live text as "no
# marker": a false not-evidenced or in-sync. This closes the PRD debt row at
# PRD.md:1712.
#
# Seam: a PATH shim named awk that COUNTS its own invocations in a file and
# exits 2 for the calls selected by AWK_SHIM_FAIL_FROM/TO; any other call runs
# the real awk. Failure is injected at the external tool, never by editing
# the code under test. Per script:
#   - baseline: the shim passes everything through; the count must be above
#     zero (a script that never reaches awk makes every arm below vacuous) and
#     the verdict is the clean one;
#   - all calls fail (the literal AC3): the visible signal, count above zero;
#   - sweep: each single awk call k of the baseline run fails alone, and every
#     one of them must give the visible signal (gate: a model-record: finding;
#     collector and staleness: never an absence claim, because positive
#     evidence read from another body stays positive: rows evidenced or
#     indeterminate, verdict stale or indeterminate). The sweep is what reaches the
#     gate's role-play read, which is the LAST awk calls of its run, and what
#     covers each of the collector's and the staleness script's several
#     live_text call sites without naming them. Call numbers are measured on
#     the baseline, not hard-coded.
# Red today: the gate's role-play calls, the collector's rows 1-3 and the
# staleness verdict. Regression arms (green on arrival): the gate's main-path
# calls and the marker parser's calls in all three.
# Not asserted: the wording of a finding or evidence line (messages only).
#
# Review round 1 of PR #443: the gate sweep also asserts that a single failed
# read never adds a blocking `role-played:` line to a complete record set
# (finding gate-frame-failure-test; mutation: the gate's `live_frame` stops
# returning a failure, which only prints a misleading "no record found" AND a
# false "stages missing" line). The unreadable-lib arm is a regression arm: the
# gate's "lib not readable" branch is redundant with the 127 of the first
# live_text call, so removing its `live_failed=1` is an equivalent mutant.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/markdown-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/markdown-helpers.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"

command -v jq >/dev/null 2>&1 || { fail "S231 — jq is needed by the fake gh"; test_done; }
sandbox_create
trap sandbox_destroy EXIT

AWK_SHIM_REAL="$(command -v awk)"
export AWK_SHIM_REAL
AWK_SHIM_COUNT="$SANDBOX/awk-count"
export AWK_SHIM_COUNT
shimdir="$SANDBOX/awkshim"
make_awk_shim "$shimdir"

# shim_count: the number of awk calls the last run made (0 if it made none).
shim_count() { if [ -r "$AWK_SHIM_COUNT" ]; then cat "$AWK_SHIM_COUNT"; else echo 0; fi; }
# with_shim <from> <to> <cmd...>: runs the command with the shim first on PATH
# (then $GH_BIN, the fake gh), failing calls from..to (0 0 = none). Stdout is
# the command's; the count is reset first.
with_shim() {
  local from="$1" to="$2"
  shift 2
  rm -f "$AWK_SHIM_COUNT"
  env AWK_SHIM_FAIL_FROM="$from" AWK_SHIM_FAIL_TO="$to" PATH="$shimdir:$GH_BIN:$PATH" "$@"
}
GH_BIN=""

ALL=999999

# =========================================================================
# 1. the gate (opted-in project: main path AND role-play path run)
# =========================================================================
gate="$TEST_REPO_ROOT/skills/pre-merge-review/model-record-gate.sh"
[ -x "$gate" ] || { fail "S231 — model-record-gate.sh is missing or not executable"; test_done; }
id="process-multi-agent-roles"
gh_bin="$(fake_gh_rest "$SANDBOX/ghdata")"
export FAKE_GH_DATA="$SANDBOX/ghdata"
mkdir -p "$FAKE_GH_DATA"
optin="$(fresh_project optin)"
write_adoption "$optin/WORKFLOW-ADOPTION.md" "$id" yes
json_pr "$FAKE_GH_DATA/pr-246.json" "Fix #239: something" "Closes #239"
json_comments "$FAKE_GH_DATA/reviews-246.json" "$(mr Review)"
json_comments "$FAKE_GH_DATA/comments-239.json" "$(mr Discovery)"
json_comments "$FAKE_GH_DATA/comments-246.json" "$(mr Planning)" "$(mr Test)" "$(mr Implementation)"

gate_run() { # from to: sets g_out
  GH_BIN="$gh_bin"
  g_out="$(cd "$optin" && with_shim "$1" "$2" "$gate" 246 2>/dev/null)"
}
# a visible finding is a line starting with `model-record:`
gate_visible() { LC_ALL=C grep -aq '^model-record:' <<<"$g_out"; }

gate_run 0 0
g_total="$(shim_count)"
[ "$g_total" -gt 0 ] || fail "S231 gate — the gate never called awk in the baseline run (count $g_total): every failure arm would be vacuous"
gate_visible && fail "S231 gate — baseline (all five stages, no failure) must print no model-record: finding, got: $g_out"
LC_ALL=C grep -aq '^role-played:' <<<"$g_out" && fail "S231 gate — baseline must print no role-played: line, got: $g_out"

gate_run 1 "$ALL"
[ "$(shim_count)" -gt 0 ] || fail "S231 gate/all — the shim was never invoked (vacuous pass)"
gate_visible || fail "S231 gate/all — every awk call fails: expected a model-record: finding, got: '$g_out'"

k=1
while [ "$k" -le "$g_total" ]; do
  gate_run "$k" "$k"
  [ "$(shim_count)" -ge "$k" ] || fail "S231 gate/call $k — the run made fewer than $k awk calls this time (the count is not stable): $(shim_count)"
  gate_visible || fail "S231 gate/call $k of $g_total — awk call $k alone fails and the gate prints no model-record: finding (a silent failure), got: '$g_out'"
  # round 1 of PR #443 (finding gate-frame-failure-test): a single failed
  # read must never ALSO print a blocking `role-played:` line. With every
  # stage recorded, "stages missing" can only come from a body that was
  # read as empty (the main path's `live_frame` ignoring a failure).
  LC_ALL=C grep -aq '^role-played:' <<<"$g_out" && fail "S231 gate/call $k of $g_total — awk call $k alone fails and the gate prints a blocking role-played: line on a complete, opted-in record set (a failed read taken as 'stages missing'), got: '$g_out'"
  k=$((k + 1))
done

# The lib cannot be read (a gate copied without lib/model-record.sh): a
# visible model-record: finding, never a silent pass. Regression arm.
nolib="$SANDBOX/nolib"
mkdir -p "$nolib/skills/pre-merge-review" "$nolib/lib"
cp "$gate" "$nolib/skills/pre-merge-review/model-record-gate.sh"
for lf in "$TEST_REPO_ROOT"/lib/*.sh; do
  case "$lf" in */model-record.sh | */markdown.sh) : ;; *) cp "$lf" "$nolib/lib/" ;; esac
done
GH_BIN="$gh_bin"
g_out="$(cd "$optin" && with_shim 0 0 "$nolib/skills/pre-merge-review/model-record-gate.sh" 246 2>/dev/null)"
gate_visible || fail "S231 gate/no-lib — lib/model-record.sh unreadable: expected a model-record: finding, got: '$g_out'"

# =========================================================================
# 2. the collector: rows 1-3 read live text
# =========================================================================
# shellcheck source=../compliance-evidence-fixture.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../compliance-evidence-fixture.sh"
# shellcheck source=../fixtures/ce-review-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/ce-review-helpers.sh"
ce_script="$TEST_REPO_ROOT/compliance-evidence.sh"
export CE_ID=S231

# One stage record per reading site, so that a read that fails at ANY site
# hides evidence the rows need: the PR body holds Planning and the done
# marker, a PR comment holds Test and Review, a PR review holds
# Implementation, and the closing issue's comment holds Discovery.
ce_spread() {
  local body pr_c pr_r issue_c
  body="$(mk Planning claude-sonnet-5 medium)${MD_LF}<!-- pre-merge-review:done sha=$SHA -->"
  body="${body//$'\n'/$'\001'}"
  pr_c="$(mk Test claude-sonnet-5 medium)
$(mk Review claude-sonnet-5 medium "$FB")"
  pr_r="$(mk Implementation claude-sonnet-5 medium)"
  issue_c="$(mk Discovery claude-sonnet-5 low)"
  {
    echo 'case "$*" in'
    echo '  __CALL_A__)'
    printf "    printf 'HEAD\\\\t%s\\\\n'\n" "$SHA"
    printf "    printf 'STATE\\\\tOPEN\\\\n'\n"
    printf "    printf 'TITLE\\\\t%%s\\\\n' 'Closes #265'\n"
    printf "    printf 'TEXT\\\\t%%s\\\\n' '%s'\n" "$body"
    echo '    exit 0 ;;'
    echo '  __CALL_A_COMMENTS__)'
    emit "$pr_c"
    echo '  __CALL_A_REVIEWS__)'
    emit "$pr_r"
    echo '  __CALL_B__)'
    printf "    printf 'check\\\\tSUCCESS\\\\tpass\\\\n'\n"
    echo '    exit 0 ;;'
    echo '  __CALL_C265__)'
    emit "$issue_c"
    echo 'esac'
    echo 'exit 1'
  } | run_build_fake_gh "$SHA"
  ce_bin="$(cat "$FAKEGH_OUT")"
}
ce_spread

ce_run() { # from to: sets c_rows (row 1-3 statuses)
  local out
  GH_BIN="$ce_bin"
  out="$(with_shim "$1" "$2" "$ce_script" 279 2>/dev/null)"
  c_rows="$(row_status "$out" 1)/$(row_status "$out" 2)/$(row_status "$out" 3)"
}
ce_run 0 0
c_total="$(shim_count)"
[ "$c_total" -gt 0 ] || fail "S231 collector — the collector never called awk in the baseline run (count $c_total): every failure arm would be vacuous"
[ "$c_rows" = "evidenced/evidenced/evidenced" ] || fail "S231 collector — baseline rows 1-3 should be evidenced/evidenced/evidenced, got $c_rows (a broken fixture)"

ce_run 1 "$ALL"
[ "$(shim_count)" -gt 0 ] || fail "S231 collector/all — the shim was never invoked (vacuous pass)"
[ "$c_rows" = "indeterminate/indeterminate/indeterminate" ] || fail "S231 collector/all — every awk call fails: rows 1-3 (all read live text) must be indeterminate, got $c_rows"

k=1
while [ "$k" -le "$c_total" ]; do
  ce_run "$k" "$k"
  # positive evidence found in another body stays positive; what a failure
  # must never become is an absence claim: each row is evidenced (as in the
  # baseline) or indeterminate, never not-evidenced
  case "$c_rows" in
    *not-evidenced* | *unverifiable-from-artifacts*) fail "S231 collector/call $k of $c_total — awk call $k alone fails and a row of 1-3 turns into an absence claim (rows: $c_rows): a failure was read as 'no record'" ;;
  esac
  k=$((k + 1))
done

# =========================================================================
# 3. the staleness script
# =========================================================================
st_script="$TEST_REPO_ROOT/role-label-staleness.sh"
[ -x "$st_script" ] || { fail "S231 — role-label-staleness.sh is missing or not executable"; test_done; }
# shellcheck source=../fixtures/role-label-fake-gh.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/role-label-fake-gh.sh"
st_marker='<!-- model-record: stage=Review model="claude-sonnet-5" effort="medium" floor-basis="ok" -->'
# st_build <where>: the Review record sits at one site only, so a failed read
# at that site is the one that hides it. where: issue-body, issue-comment,
# pr-title-body (the PR description), pr-comment, pr-review, and
# pr-title-keyword (the closing keyword is only in the PR TITLE, as in this
# repo's own release-branch PRs, and the record is in a PR comment: a failed
# read of the title drops the whole PR from the evidence).
st_build() {
  local where="$1" ib="" ic="plain comment" pt="Fix: something" pb="Closes #400" pc="plain" pr="plain"
  case "$where" in
    issue-body) ib="$st_marker" ;;
    issue-comment) ic="$st_marker" ;;
    pr-title-body) pb="Closes #400 $st_marker" ;;
    pr-comment) pc="$st_marker" ;;
    pr-review) pr="$st_marker" ;;
    pr-title-keyword) pt="Closes #400: something"; pb="no keyword here"; pc="$st_marker" ;;
  esac
  run_build_fake_gh > "$FAKEGH_OUT" <<GHEOF
__CALL_ISSUE__)
  printf 'LABEL\trole:architect\n'
  printf 'BODY\t%s\n' '$ib'
  exit 0 ;;
__CALL_ISSUE_COMMENTS__)
  printf 'TEXT\t%s\n' '$ic'
  exit 0 ;;
__CALL_REPO_IDENTITY__)
  printf 'owner/repo\n'
  exit 0 ;;
__CALL_TIMELINE__)
  printf 'PR\t501\n'
  exit 0 ;;
__CALL_PR501_TITLEBODY__)
  printf 'TITLE\t%s\n' '$pt'
  printf 'BODY\t%s\n' '$pb'
  exit 0 ;;
__CALL_PR501_COMMENTS__)
  printf 'TEXT\t%s\n' '$pc'
  exit 0 ;;
__CALL_PR501_REVIEWS__)
  printf 'TEXT\t%s\n' '$pr'
  exit 0 ;;
GHEOF
  st_bin="$(cat "$FAKEGH_OUT")"
}
st_run() { # from to: sets s_out
  GH_BIN="$st_bin"
  s_out="$(with_shim "$1" "$2" "$st_script" 400 2>/dev/null)"
}
st_status() { printf '%s' "$s_out" | LC_ALL=C sed -E 's/^role-label-staleness: issue #400 — ([a-z-]+) \(.*$/\1/'; }
for where in issue-body issue-comment pr-title-body pr-comment pr-review pr-title-keyword; do
  st_build "$where"
  st_run 0 0
  s_total="$(shim_count)"
  [ "$s_total" -gt 0 ] || fail "S231 staleness/$where — the script never called awk in the baseline run (count $s_total): every failure arm would be vacuous"
  [ "$(st_status)" = "stale" ] || fail "S231 staleness/$where — baseline: role:architect behind a stage=Review marker must be stale, got: $s_out"

  st_run 1 "$ALL"
  [ "$(shim_count)" -gt 0 ] || fail "S231 staleness/$where/all — the shim was never invoked (vacuous pass)"
  [ "$(st_status)" = "indeterminate" ] || fail "S231 staleness/$where/all — every awk call fails: the verdict must be indeterminate, got: $s_out"

  k=1
  while [ "$k" -le "$s_total" ]; do
    st_run "$k" "$k"
    # the Review marker is read at one site; a failed read elsewhere may
    # leave `stale` standing. What a failure must never become is an
    # absence claim (in-sync, not-started) or a different stage
    case "$(st_status)" in
      stale | indeterminate) : ;;
      *) fail "S231 staleness/$where/call $k of $s_total — awk call $k alone fails and the verdict is neither stale nor indeterminate (a failure read as no marker), got: $s_out" ;;
    esac
    k=$((k + 1))
  done
done

test_done
