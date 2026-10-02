#!/usr/bin/env bash
# S186 — The merge guard refuses `gh pr merge` on a role-played run, in
# opted-in projects only.
# Covers: F38
#
# Issue #371, AC9, A18 amendment (Architect ratification) and the human
# decision to keep the block. Seam: hooks/git-guardrails fed a `gh pr merge
# <n>` Bash call, with a fake gh that satisfies the existing review-marker
# check, so only the role-play step decides. When the project answered
# process-multi-agent-roles yes, the guard runs the installed
# model-record-gate.sh and refuses (exit 2) on a line starting
# "role-played: "; it fails open without gh or network; a project that did
# not answer yes is unaffected.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"

command -v jq >/dev/null 2>&1 || { fail "S186 — jq is needed by the fake gh"; test_done; }

sandbox_create
trap sandbox_destroy EXIT

id="process-multi-agent-roles"
fakebin="$(fake_gh_merge_rest "$SANDBOX/ghdata")"
export FAKE_GH_DATA="$SANDBOX/ghdata"
mkdir -p "$FAKE_GH_DATA"

mkproject() { # name answer-or-empty
  local p
  p="$(fresh_project "$1")"
  git -C "$p" commit -q --allow-empty -m start
  git -C "$p" checkout -q -b feature/work
  [ -z "$2" ] || write_adoption "$p/WORKFLOW-ADOPTION.md" "$id" "$2"
  echo "$p"
}

reset_data() {
  rm -f "${FAKE_GH_DATA:?}"/*.json
  json_pr "$FAKE_GH_DATA/pr-246.json" "Fix #239: x" "Closes #239"
  json_comments "$FAKE_GH_DATA/reviews-246.json"
  json_comments "$FAKE_GH_DATA/comments-246.json"
  json_comments "$FAKE_GH_DATA/comments-239.json" "$(mr Discovery)"
}
dispatched() {
  reset_data
  json_comments "$FAKE_GH_DATA/comments-246.json" "$(mr Planning)" "$(mr Test)" "$(mr Implementation)"
  json_comments "$FAKE_GH_DATA/reviews-246.json" "$(mr Review)"
}
all_in_one() {
  reset_data
  json_comments "$FAKE_GH_DATA/comments-239.json" "no markers"
  json_comments "$FAKE_GH_DATA/comments-246.json" "$(mr Discovery) $(mr Planning) $(mr Test) $(mr Implementation) $(mr Review)"
}

merge() { # project [path] [command] -> output in $out, status in $status
  local input path="${2:-$fakebin:$PATH}" cmd="${3:-gh pr merge 246}"
  input='{"tool_name":"Bash","cwd":"'"$1"'","tool_input":{"command":"'"$cmd"'"}}'
  out="$(printf '%s' "$input" | PATH="$path" "$TEST_REPO_ROOT/hooks/git-guardrails" 2>&1)"
  status=$?
}

yes_p="$(mkproject optin yes)"
no_p="$(mkproject optout no)"
un_p="$(mkproject unanswered "")"

# 1. Opted in + role-played run: refused, and the reason names it.
all_in_one
merge "$yes_p"
[ "$status" -eq 2 ] || fail "S186/1 — expected a block (exit 2) for a role-played run, got $status. Output: $out"
assert_contains "S186/1 — the refusal says why" "role-played" "$out"

# 2. Opted in + dispatched run: through.
dispatched
merge "$yes_p"
[ "$status" -eq 0 ] || fail "S186/2 — a dispatched run was blocked (exit $status): $out"

# 3. Opted in + role-played run + valid override record: through.
all_in_one
json_comments "$FAKE_GH_DATA/comments-239.json" \
  '<!-- pipeline-override: decided-by="human" scope="single-session" reason="asked for it" -->'
merge "$yes_p"
[ "$status" -eq 0 ] || fail "S186/3 — a role-played run with a valid override was blocked (exit $status): $out"

# 4. Not opted in (no / never answered): the same run is unaffected.
all_in_one
merge "$no_p"
[ "$status" -eq 0 ] || fail "S186/4 — a project answering no was blocked (exit $status): $out"
merge "$un_p"
[ "$status" -eq 0 ] || fail "S186/4 — a project with no row was blocked (exit $status): $out"

# 5. Fail open: gh failing on the REST calls, and no gh at all.
all_in_one
export FAKE_GH_FAIL=1
merge "$yes_p"
unset FAKE_GH_FAIL
[ "$status" -eq 0 ] || fail "S186/5 — REST calls failing: the merge was blocked (exit $status): $out"
nogh="$(path_without_gh)"
merge "$yes_p" "$nogh"
[ "$status" -eq 0 ] || fail "S186/5 — no gh: the merge was blocked (exit $status): $out"

# 6. The existing review-marker block is unchanged for an opted-in project.
dispatched
nomarker="$(fake_gh_merge_rest "$SANDBOX/ghdata" nomarker)"
merge "$yes_p" "$nomarker:$PATH"
[ "$status" -eq 2 ] || fail "S186/6 — a missing review marker no longer blocks (exit $status): $out"
assert_contains "S186/6 — still the review-marker message" "pre-merge-review" "$out"

# 7. The explicit escape hatch still works for the role-play block.
all_in_one
merge "$yes_p" "$fakebin:$PATH" "CLAUDE_WORKFLOW_MERGE_GUARD_OFF=1 gh pr merge 246"
[ "$status" -eq 0 ] || fail "S186/7 — the explicit merge-guard escape hatch no longer works (exit $status): $out"

test_done
