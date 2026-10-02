#!/usr/bin/env bash
# S183 — model-record-gate.sh flags a role-played run, in opted-in projects
# only, unless a valid override is recorded.
# Covers: F38
#
# Issue #371, A18, AC3, AC6, AC9 and human decision 3. Seam: the installed
# gate script, run with the project as cwd, against a data-driven fake `gh`
# (fixtures/pipeline-371-helpers.sh), so the gate's own call shapes are not
# pinned. A "role-played run" is: one comment (or the PR body) carrying live
# markers of two or more different stages, or any of the five stages
# missing. Output contract (ratified by the Architect): each finding is a
# stdout line starting "role-played: "; with a valid override (scope
# single-session or skip=<Stage>) there is no such line (a note may be
# printed, never with that prefix). The existing "no record found for stage" lines are
# S130's and stay as they are.
#
# Not asserted here: that a finding BLOCKS the merge (the pre-merge review
# withholds its marker; S185 checks that the skill says so), and that
# forged per-stage comments are caught (accepted undetectable limit).

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"

script="$TEST_REPO_ROOT/skills/pre-merge-review/model-record-gate.sh"
[ -x "$script" ] || { fail "S183 — model-record-gate.sh is missing or not executable"; test_done; }
command -v jq >/dev/null 2>&1 || { fail "S183 — jq is needed by the fake gh"; test_done; }

sandbox_create
trap sandbox_destroy EXIT

id="process-multi-agent-roles"
fakebin="$(fake_gh_rest "$SANDBOX/ghdata")"
export FAKE_GH_DATA="$SANDBOX/ghdata"
mkdir -p "$FAKE_GH_DATA"

yes_p="$(fresh_project optin)"
write_adoption "$yes_p/WORKFLOW-ADOPTION.md" "$id" yes
no_p="$(fresh_project optout)"
write_adoption "$no_p/WORKFLOW-ADOPTION.md" "$id" no
unans_p="$(fresh_project unanswered)"
write_adoption "$unans_p/WORKFLOW-ADOPTION.md" process-prd yes
nofile_p="$(fresh_project nofile)"
old_p="$(fresh_project oldfile)"
write_adoption "$old_p/WORKFLOW-ADOPTIE.md" "$id" ja

# data <pr-body> <issue-239-comments...>: resets PR 246 / issue 239 data.
# Callers then set PR comments / reviews themselves.
reset_data() {
  rm -f "${FAKE_GH_DATA:?}"/*.json
  json_pr "$FAKE_GH_DATA/pr-246.json" "Fix #239: something" "${1:-Closes #239}"
  json_comments "$FAKE_GH_DATA/reviews-246.json"
  json_comments "$FAKE_GH_DATA/comments-246.json"
  json_comments "$FAKE_GH_DATA/comments-239.json" "$(mr Discovery)"
}

gate() { # project -> stdout in $out, status in $status
  out="$(cd "$1" && PATH="$fakebin:$PATH" "$script" 246 2>/dev/null)"
  status=$?
}
flagged() { grep -q '^role-played: ' <<<"$out"; }

dispatched() { # the shape of a real pipeline: Discovery on the issue, one comment per stage
  reset_data
  json_comments "$FAKE_GH_DATA/comments-246.json" "$(mr Planning)" "$(mr Test)" "$(mr Implementation)"
  json_comments "$FAKE_GH_DATA/reviews-246.json" "$(mr Review)"
}
all_in_one() { # one session playing every role: all five markers in one text
  reset_data
  json_comments "$FAKE_GH_DATA/comments-239.json" "no markers here"
  json_comments "$FAKE_GH_DATA/comments-246.json" "$(mr Discovery) $(mr Planning) $(mr Test) $(mr Implementation) $(mr Review)"
}
override_marker() { # decided-by scope reason
  printf '<!-- pipeline-override: decided-by="%s" scope="%s" reason="%s" -->' "$1" "$2" "$3"
}

# 1. A dispatched run is clean everywhere.
dispatched
for p in "$yes_p" "$no_p" "$unans_p" "$nofile_p"; do
  gate "$p"
  [ -z "$out" ] || fail "S183/1 — a dispatched run produced output in ${p##*/}: $out"
done

# 2. All five markers in one comment: flagged only where opted in.
all_in_one
gate "$yes_p"
flagged || fail "S183/2 — opted-in: five stages in one comment were not flagged as role-played (output: $out)"
[ "$status" -eq 0 ] || fail "S183/2 — the gate must exit 0 (findings are output), got $status"
for p in "$no_p" "$unans_p" "$nofile_p"; do
  gate "$p"
  [ -z "$out" ] || fail "S183/2 — ${p##*/} (not opted in) got output for the same run: $out"
done
gate "$old_p"
flagged || fail "S183/2 — ja in the pre-migration WORKFLOW-ADOPTIE.md must count as opted in"

# 3. Two stages in the PR body (PR-creation-time markers), others separate.
reset_data "Closes #239
$(mr Planning) $(mr Test)"
json_comments "$FAKE_GH_DATA/comments-246.json" "$(mr Implementation)"
json_comments "$FAKE_GH_DATA/reviews-246.json" "$(mr Review)"
gate "$yes_p"
flagged || fail "S183/3 — two stages in the PR body were not flagged (output: $out)"
gate "$no_p"
[ -z "$out" ] || fail "S183/3 — not opted in: expected no output, got: $out"

# 4. Two stages inside one PR review body.
reset_data
json_comments "$FAKE_GH_DATA/comments-246.json" "$(mr Planning)" "$(mr Test)"
json_comments "$FAKE_GH_DATA/reviews-246.json" "$(mr Implementation) $(mr Review)"
gate "$yes_p"
flagged || fail "S183/4 — two stages in one review body were not flagged (output: $out)"

# 5. The same stage twice in one comment is not two different stages.
dispatched
json_comments "$FAKE_GH_DATA/reviews-246.json" "$(mr Review) round 2: $(mr Review)"
gate "$yes_p"
flagged && fail "S183/5 — one stage recorded twice in one text was flagged (output: $out)"

# 6. Quoted markers (code fence, blockquote) are illustration, not live.
dispatched
json_comments "$FAKE_GH_DATA/comments-246.json" \
  "$(mr Planning)
Format reminder:
\`\`\`
$(mr Test)
\`\`\`
> $(mr Implementation)" \
  "$(mr Test)" "$(mr Implementation)"
gate "$yes_p"
flagged && fail "S183/6 — markers quoted in a fence or blockquote counted as live stages (output: $out)"

# 7. A stage missing: the existing missing line stays, and opted-in adds the
# role-played finding; not opted in only gets the existing line.
dispatched
json_comments "$FAKE_GH_DATA/reviews-246.json"
gate "$yes_p"
assert_contains "S183/7 — the existing missing-stage line is kept" "stage Review" "$out"
flagged || fail "S183/7 — opted-in: a missing stage was not flagged as role-played (output: $out)"
gate "$no_p"
assert_contains "S183/7 — not opted in: the existing missing-stage line is kept" "stage Review" "$out"
flagged && fail "S183/7 — not opted in: got a role-played finding for a missing stage (output: $out)"

# 8. A valid override record turns the finding into a note.
all_in_one
json_comments "$FAKE_GH_DATA/comments-239.json" \
  "$(override_marker human single-session "human asked for a single session")"
gate "$yes_p"
flagged && fail "S183/8 — a valid override on the issue did not stop the role-played finding (output: $out)"
# ... and an override in the PR body counts as well.
all_in_one
json_pr "$FAKE_GH_DATA/pr-246.json" "Fix #239: x" "Closes #239
$(override_marker human single-session "human asked for a single session")"
gate "$yes_p"
flagged && fail "S183/8 — a valid override in the PR body did not count (output: $out)"
# ... a skip override for the one missing stage.
dispatched
json_comments "$FAKE_GH_DATA/reviews-246.json"
json_comments "$FAKE_GH_DATA/comments-239.json" "$(mr Discovery)" \
  "$(override_marker human skip=Review "human skipped the review stage")"
gate "$yes_p"
flagged && fail "S183/8 — a skip=Review override did not cover the missing Review (output: $out)"

# 9. An override that does not say who or why is not a record.
all_in_one
json_comments "$FAKE_GH_DATA/comments-239.json" \
  '<!-- pipeline-override: decided-by="human" scope="single-session" reason="" -->'
gate "$yes_p"
flagged || fail "S183/9 — an override with an empty reason silenced the finding"
json_comments "$FAKE_GH_DATA/comments-239.json" \
  '<!-- pipeline-override: scope="single-session" reason="because" -->'
gate "$yes_p"
flagged || fail "S183/9 — an override without decided-by silenced the finding"

# 9b. scope must come from the closed vocabulary.
all_in_one
for bad_scope in whenever skip=Bogus skip= single-sessions; do
  json_comments "$FAKE_GH_DATA/comments-239.json" "$(override_marker human "$bad_scope" "because")"
  gate "$yes_p"
  flagged || fail "S183/9b — an override with scope=\"$bad_scope\" silenced the finding"
done
json_comments "$FAKE_GH_DATA/comments-239.json" "$(override_marker human single-session "because")"
gate "$yes_p"
flagged && fail "S183/9b — a valid single-session override did not silence the finding"

# 10. An override quoted for illustration is not a record.
all_in_one
json_comments "$FAKE_GH_DATA/comments-239.json" \
  "> $(override_marker human single-session "quoted example")"
gate "$yes_p"
flagged || fail "S183/10 — a blockquoted override silenced the finding"

# 11. Fail-open: a failing gh, or no gh, never blocks and never invents a finding.
all_in_one
out="$(cd "$yes_p" && FAKE_GH_FAIL=1 PATH="$fakebin:$PATH" "$script" 246 2>/dev/null)"
status=$?
[ "$status" -eq 0 ] || fail "S183/11 — gh failing: exit $status instead of 0"
flagged && fail "S183/11 — gh failing: a role-played finding was invented"
nogh="$(path_without_gh)"
out="$(cd "$yes_p" && PATH="$nogh" "$script" 246 2>/dev/null)"
status=$?
[ "$status" -eq 0 ] || fail "S183/11 — no gh: exit $status instead of 0"
flagged && fail "S183/11 — no gh: a role-played finding was invented"

test_done
