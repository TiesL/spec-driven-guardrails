#!/usr/bin/env bash
# S205 — the role-play check's "stages missing" test reads LIVE text: a stage
# named only inside a code span, a fence or a blockquote is not present.
# Covers: F38
#
# Issue #369 (holistic review of the release, blocking finding B2). The
# marker checks (stage presence, S201) and the "stages in one text" check
# drop quoted text; the "stages missing" loop of the role-play check grepped
# the RAW text, so prose that quotes a marker line (an Architect report quoting
# the gate's finding, a skill example) counted as a present stage and the
# merge guard's role-played line was suppressed: a false pass. Required: the
# quoted mention does not count, in the code span, the fence and the
# blockquote forms, and the real-marker control stays clean. Out of scope
# (issue #400): five markers all inside one fence producing no role-played
# line; it is not asserted here, and if the fix of this one line also changes
# that outcome the case is allowed to go either way (not tested).
# Seam: model-record-gate.sh stdout in an opted-in project, against fake gh.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"

script="$TEST_REPO_ROOT/skills/pre-merge-review/model-record-gate.sh"
[ -x "$script" ] || { fail "S205 — model-record-gate.sh is missing or not executable"; test_done; }
command -v jq >/dev/null 2>&1 || { fail "S205 — jq is needed by the fake gh"; test_done; }
sandbox_create
trap sandbox_destroy EXIT

id="process-multi-agent-roles"
fakebin="$(fake_gh_rest "$SANDBOX/ghdata")"
export FAKE_GH_DATA="$SANDBOX/ghdata"
mkdir -p "$FAKE_GH_DATA"
optin="$(fresh_project optin)"
write_adoption "$optin/WORKFLOW-ADOPTION.md" "$id" yes
optout="$(fresh_project optout)"
write_adoption "$optout/WORKFLOW-ADOPTION.md" "$id" no

NL=$'\n'
review_line="$(mr Review)"

# Discovery on the issue; Planning, Test, Implementation one comment each; a
# REVIEW stage that is only quoted in the extra comments given
run_case() { # project, extra comment bodies...
  local proj="$1"
  shift
  rm -f "${FAKE_GH_DATA:?}"/*.json
  json_pr "$FAKE_GH_DATA/pr-246.json" "Fix #239: something" "Closes #239"
  json_comments "$FAKE_GH_DATA/reviews-246.json"
  json_comments "$FAKE_GH_DATA/comments-239.json" "$(mr Discovery)"
  json_comments "$FAKE_GH_DATA/comments-246.json" "$(mr Planning)" "$(mr Test)" "$(mr Implementation)" "$@"
  out="$(cd "$proj" && PATH="$fakebin:$PATH" "$script" 246 2>/dev/null)"
  : "$?"
}
missing_review() { grep -q '^role-played: .*missing.*Review' <<<"$out"; }

# --- control: a real Review marker (in a review body) is a clean run ------------
rm -f "${FAKE_GH_DATA:?}"/*.json
json_pr "$FAKE_GH_DATA/pr-246.json" "Fix #239: something" "Closes #239"
json_comments "$FAKE_GH_DATA/reviews-246.json" "$review_line"
json_comments "$FAKE_GH_DATA/comments-239.json" "$(mr Discovery)"
json_comments "$FAKE_GH_DATA/comments-246.json" "$(mr Planning)" "$(mr Test)" "$(mr Implementation)"
out="$(cd "$optin" && PATH="$fakebin:$PATH" "$script" 246 2>/dev/null)"
grep -q '^role-played: ' <<<"$out" && fail "S205 control — a dispatched run with a real Review marker must be clean, got: $out"

# --- control: no Review at all is reported -----------------------------------------
run_case "$optin"
missing_review || fail "S205 control — no Review marker anywhere: expected 'role-played: stages missing: Review', got: '$out'"

# --- the quoted forms must not count -----------------------------------------------
run_case "$optin" "The gate prints: \`$review_line\` when it is missing."
missing_review || fail "S205 code span — a Review marker quoted in a code span is not a present stage; expected 'role-played: stages missing: Review', got: '$out'"
run_case "$optin" "Example:${NL}\`\`\`${NL}$review_line${NL}\`\`\`"
missing_review || fail "S205 fence — a Review marker inside a fenced block is not a present stage, got: '$out'"
run_case "$optin" "Example:${NL}~~~${NL}$review_line${NL}~~~"
missing_review || fail "S205 tilde fence — got: '$out'"
run_case "$optin" "> The Reviewer wrote:${NL}> $review_line"
missing_review || fail "S205 blockquote — a Review marker in a blockquote is not a present stage, got: '$out'"
# the architect-report shape: prose quoting the finding text of the gate
run_case "$optin" "The gate's finding reads \`model-record: stage=Review marker has no floor-basis\`, and the marker form is \`<!-- model-record: stage=Review model=\"x\" -->\`."
missing_review || fail "S205 report prose — a report quoting the gate's finding and the marker form must not count as a Review record, got: '$out'"
# quoted in the PR body as well (the description is a separate text)
rm -f "${FAKE_GH_DATA:?}"/*.json
json_pr "$FAKE_GH_DATA/pr-246.json" "Fix #239: something" "Closes #239${NL}${NL}Do not paste \`$review_line\` here."
json_comments "$FAKE_GH_DATA/reviews-246.json"
json_comments "$FAKE_GH_DATA/comments-239.json" "$(mr Discovery)"
json_comments "$FAKE_GH_DATA/comments-246.json" "$(mr Planning)" "$(mr Test)" "$(mr Implementation)"
out="$(cd "$optin" && PATH="$fakebin:$PATH" "$script" 246 2>/dev/null)"
missing_review || fail "S205 PR description — a marker quoted in the PR body is not a present stage, got: '$out'"

# --- a role-played run is not masked by a quoted mention ----------------------------
# one comment carrying real markers of several stages stays reported
rm -f "${FAKE_GH_DATA:?}"/*.json
json_pr "$FAKE_GH_DATA/pr-246.json" "Fix #239: something" "Closes #239"
json_comments "$FAKE_GH_DATA/reviews-246.json"
json_comments "$FAKE_GH_DATA/comments-239.json" "$(mr Discovery)"
json_comments "$FAKE_GH_DATA/comments-246.json" "$(mr Planning) $(mr Test) $(mr Implementation)${NL}Quoted: \`$review_line\`"
out="$(cd "$optin" && PATH="$fakebin:$PATH" "$script" 246 2>/dev/null)"
grep -q '^role-played: ' <<<"$out" || fail "S205 masked — three stages in one comment plus a quoted Review mention must still be role-played, got: '$out'"
grep -q '^role-played: .*missing.*Review' <<<"$out" || fail "S205 masked — the missing Review must still be named, got: '$out'"

# --- a project that did not opt in sees no role-played line, and the existing missing-stage line --------
run_case "$optout" "Quoted: \`$review_line\`"
grep -q '^role-played: ' <<<"$out" && fail "S205 not opted in — no role-played line, got: '$out'"
grep -q 'no record found for stage Review' <<<"$out" || fail "S205 not opted in — the existing 'no record found for stage Review' line is expected, got: '$out'"

test_done
