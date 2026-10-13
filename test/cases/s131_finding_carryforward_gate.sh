#!/usr/bin/env bash
# S131 — Finding carry-forward gate (#241 AC2): an open finding from the
# previous review round must reappear in the next one, not vanish because
# that round ran fresh-context.
# Covers: F28
#
# Found via #238 (portfolio-mgt-agents PR #4): round 1 flagged a missing
# Decision Log entry; round 2 (fresh context) never carried it forward;
# the PR merged 17 seconds later.
#
# Edited for #426 (V5 of #411): the fake gh used to be keyed to
# `gh pr view --json comments` (GraphQL-backed, 403 inside Claude Code, #318);
# the gate now reads REST (`gh api repos/{owner}/{repo}/issues/N/comments` and
# `.../pulls/N/reviews`), so the fixtures serve REST data (the recording fake of
# test/fixtures/review-rounds-helpers.sh). Each round is now an A37 round: a body
# with a Review record or a legacy done marker with a 40-hex sha (the old `sha=aaa`
# is no marker any more). The five original cases keep their meaning; S251 to S253
# hold the new behaviour.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"
# shellcheck source=../fixtures/review-floor-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/review-floor-helpers.sh"
# shellcheck source=../fixtures/review-rounds-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/review-rounds-helpers.sh"

script="$TEST_REPO_ROOT/skills/pre-merge-review/finding-carryforward-gate.sh"
[ -x "$script" ] || { fail "S131 — skills/pre-merge-review/finding-carryforward-gate.sh is missing or not executable"; test_done; }
command -v jq >/dev/null 2>&1 || { fail "S131 — jq is needed by the fake gh"; test_done; }

sandbox_create
trap sandbox_destroy EXIT
rr_setup

rr_out="" rr_err=""
rr_status=0
NL=$'\n'
T1=2026-10-01T10:00:00Z T2=2026-10-02T10:00:00Z
rev="$(rr_review)"
dn="$(rr_done)"
r1="round 1 findings:${NL}- missing Decision Log entry${NL}$(rr_finding missing-decision-log open)${NL}${rev}${NL}${dn}"

# Case 1: round 1 left "missing-decision-log" open; round 2 dropped it
# entirely. That must be reported.
rr_reset
rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at "$T1" "$r1" "$T2" "round 2 findings:${NL}none${NL}${rev}${NL}${dn}"
rr_script_run "$script" "$RR_PR"
case "$rr_out" in
  *"missing-decision-log"*"missing from this one"*) : ;;
  *) fail "S131 — expected a carry-forward finding for missing-decision-log, got: $rr_out (stderr: $rr_err)" ;;
esac

# Case 2: round 2 explicitly re-flags it as still open — not dropped, no
# finding.
rr_reset
rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at "$T1" "$r1" \
  "$T2" "round 2 findings:${NL}- still missing Decision Log entry${NL}$(rr_finding missing-decision-log open)${NL}${rev}${NL}${dn}"
rr_script_run "$script" "$RR_PR"
[ -z "$rr_out" ] || fail "S131 — expected no findings when the prior round's finding is re-flagged, got: $rr_out"

# Case 3: round 2 marks it resolved — also not dropped, no finding.
rr_reset
rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at "$T1" "$r1" \
  "$T2" "round 2: fixed${NL}$(rr_finding missing-decision-log resolved)${NL}${rev}${NL}${dn}"
rr_script_run "$script" "$RR_PR"
[ -z "$rr_out" ] || fail "S131 — expected no findings when the prior round's finding is marked resolved, got: $rr_out"

# Case 4: only one review round so far -> nothing to carry forward.
rr_reset
rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at "$T1" "$r1"
rr_script_run "$script" "$RR_PR"
[ -z "$rr_out" ] || fail "S131 — expected no findings with only one review round, got: $rr_out"

# Case 5: no gh on PATH -> fails open, exit 0, warning.
path_without_gh="$(path_without_gh)"
output_nogh="$(PATH="$path_without_gh" "$script" "$RR_PR" 2>&1)"; status_nogh=$?
[ "$status_nogh" -eq 0 ] || fail "S131 — without gh the gate gave exit $status_nogh instead of 0"
assert_contains "S131 — a warning appears without gh" "warning" "$output_nogh"

# Case 6 (new with the REST move): the fetch fails -> fails open, exit 0, a warning, no finding.
rr_reset
rr_json "$FAKE_GH_DATA/comments-$RR_PR.json" created_at "$T1" "$r1" "$T2" "round 2 findings:${NL}none${NL}${rev}${NL}${dn}"
FAKE_GH_FAIL=1 rr_script_run "$script" "$RR_PR"
[ "$rr_status" -eq 0 ] || fail "S131 — a failed fetch gave exit $rr_status instead of 0"
assert_contains "S131 — a failed fetch warns" "warning" "$rr_err"
[ -z "$rr_out" ] || fail "S131 — a failed fetch printed a verdict: $rr_out"

test_done
