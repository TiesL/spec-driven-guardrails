#!/usr/bin/env bash
# S312 — the dispatch hook denies each non-compliant role dispatch with the
# core's own line (#499 AC8)
# Covers: F38
#
# Seam: the hook's pure core `hooks/agent-dispatch.py <ORCHESTRATOR.md>
# <inventory>` with synthetic PreToolUse JSON on stdin (tool_name Agent, no
# agent_id), the real ORCHESTRATOR.md and inventory. The deny text must be
# byte-equal to the core line the inventory's `hook:` column maps the failed
# check to; no second copy lives in the script.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/agent-dispatch-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/agent-dispatch-helpers.sh"

sandbox_create
trap sandbox_destroy EXIT

for f in "$AD_CORE" "$AD_TSV"; do
  [ -r "$f" ] || { fail "S312 — ${f#"$TEST_REPO_ROOT"/} is missing"; test_done; }
done

# deny_with <case> <json> <ID>... : exit 2, each ID's core line exactly
# once, no other core line, plus the one avoidance line.
deny_with() {
  local name="$1" json="$2" id line n all_ids
  shift 2
  ad_run_core "$json"
  [ "$ad_st" = 2 ] || { fail "S312/$name — expected exit 2, got $ad_st (stderr: $ad_err)"; return; }
  [ -z "$ad_out" ] || fail "S312/$name — stdout must be empty"
  for id in "$@"; do
    line="$(ad_core_line "$id")"
    [ -n "$line" ] || { fail "S312/$name — no core line for $id"; continue; }
    n="$(grep -cxF -- "$line" <<<"$ad_err")"
    [ "$n" = 1 ] || fail "S312/$name — the $id core line appears $n times in stderr"
  done
  all_ids="$(python3 -I "$AD_HARNESS" items --orch "$AD_ORCH" | cut -f1)"
  for id in $all_ids; do
    case " $* " in *" $id "*) continue ;; esac
    line="$(ad_core_line "$id")"
    if grep -qxF -- "$line" <<<"$ad_err"; then fail "S312/$name — unrelated $id line in stderr"; fi
  done
  grep -q 'ROLE SESSION:' <<<"$(grep -vxF -f <(for id in "$@"; do ad_core_line "$id"; done) <<<"$ad_err")" \
    || fail "S312/$name — no line on how a non-role prompt avoids detection"
  case "$ad_err" in *'<!-- session-context: slot -->'*) fail "S312/$name — the marker line is in the deny output" ;; esac
}

good_dev="$(ad_prompt "Fullstack Developer")"

# prefix (OR8)
deny_with prefix-missing "$(ad_input "Please do QA.
$(printf '%s' "$good_dev" | tail -n +2)")" OR8
deny_with prefix-lower "$(ad_input "role session: QA
$(printf '%s' "$good_dev" | tail -n +2)")" OR8
deny_with prefix-unknown-role "$(ad_input "ROLE SESSION: Tester
$(printf '%s' "$good_dev" | tail -n +2)")" OR8
deny_with prefix-line-2 "$(ad_input "Context first.
$good_dev")" OR8
# no-fork (OR7)
deny_with fork "$(ad_input "$good_dev" fork)" OR7
# marker-command (OR31)
deny_with no-stage-command "$(ad_input "ROLE SESSION: QA

ROLE SESSION: is the prefix; marker via model-record-emit.sh, see the skill.")" OR31
deny_with stage-testing "$(ad_input "$(ad_prompt QA Testing)")" OR31
# model (OR30)
deny_with model-absent "$(ad_input "$good_dev" general-purpose -)" OR30
deny_with model-empty "$(ad_input "$good_dev" general-purpose "")" OR30
# Reviewer (OR14): PR, SHA, gate
rv_base="ROLE SESSION: Reviewer

/clone/skills/pre-merge-review/model-record-emit.sh --stage Review --model <id>"
deny_with reviewer-no-pr "$(ad_input "$rv_base
head 0123abc4567def, finding-carryforward-gate.sh first.")" OR14
deny_with reviewer-sha-6 "$(ad_input "$rv_base
PR #42, head 0123ab, finding-carryforward-gate.sh first.")" OR14
deny_with reviewer-sha-41 "$(ad_input "$rv_base
https://github.com/o/r/pull/42 head 0123456789abcdef0123456789abcdef012345678, finding-carryforward-gate.sh.")" OR14
deny_with reviewer-no-gate "$(ad_input "$rv_base
PR #42, head 0123abc4567def.")" OR14
# Reviewer PR and head SHA must be real (review round 1, finding
# reviewer-fields-vacuous). Reading of AC8 where A41 is silent: a PR number
# is `/pull/<n>` or `PR <n>` / `PR #<n>` (the word PR before it); a bare
# `#<n>` is an issue reference and does not count. A head SHA is a 7-40 hex
# run that contains at least one letter a-f, or one introduced by `head`,
# `SHA` or `commit`; an all-digit run with no such label (a comment id)
# does not count. OR15 makes the comment link mandatory in later rounds, so
# such a brief is the normal round-2 brief.
deny_with reviewer-issue-and-comment-only "$(ad_input "$rv_base
Work item #499. Previous round: https://github.com/x/y/issues/499#issuecomment-6269971234
Run finding-carryforward-gate.sh first.")" OR14
deny_with reviewer-issue-ref-with-sha "$(ad_input "$rv_base
Work item #499, head 0123abc4567def, finding-carryforward-gate.sh first.")" OR14
deny_with reviewer-issue-url-with-sha "$(ad_input "$rv_base
https://github.com/o/r/issues/499 head 0123abc4567def, finding-carryforward-gate.sh first.")" OR14
deny_with reviewer-digits-as-sha "$(ad_input "$rv_base
PR #42, comment 6269971234, finding-carryforward-gate.sh first.")" OR14
for pr_form in "PR #42" "PR 42" "see /pull/42"; do
  ad_run_core "$(ad_input "$rv_base
$pr_form, work item #499, head 0123abc4567def, finding-carryforward-gate.sh first.")"
  [ "$ad_st" = 0 ] || fail "S312/reviewer-pr-form-'$pr_form' — a real PR reference must pass ($ad_err)"
done
ad_run_core "$(ad_input "$rv_base
PR #42, head 1234567890, finding-carryforward-gate.sh first.")"
[ "$ad_st" = 0 ] || fail "S312/reviewer-labelled-digit-sha — a SHA introduced by 'head' must pass ($ad_err)"
# Two Reviewer checks on one ID print it once; three checks together.
deny_with reviewer-two-on-or14 "$(ad_input "$rv_base
nothing else")" OR14
deny_with three-checks "$(ad_input "Hello
$(printf '%s' "$good_dev" | tail -n +2)" fork -)" OR8 OR7 OR30

# Compliant dispatch for each role: exit 0, no output at all.
for role in Product Architect QA "Fullstack Developer" Reviewer; do
  ad_run_core "$(ad_input "$(ad_prompt "$role")")"
  [ "$ad_st" = 0 ] && [ -z "$ad_out" ] && [ -z "$ad_err" ] \
    || fail "S312/compliant-$role — expected silent exit 0, got $ad_st ($ad_err)"
done
ad_run_core "$(ad_input "$(ad_prompt Reviewer | sed 's|PR #42|https://github.com/o/r/pull/42|')")"
[ "$ad_st" = 0 ] || fail "S312/compliant-pull-url — /pull/<n> must satisfy the PR check ($ad_err)"

# Not a role dispatch: quoting the rule text, or naming the emit script
# with no --stage command; silent exit 0.
quoted="$(ad_core_line OR8)
$(ad_core_line OR31)
$(ad_core_line OR1)"
ad_run_core "$(ad_input "Summarise these rules for me:
$quoted" fork -)"
[ "$ad_st" = 0 ] && [ -z "$ad_err" ] || fail "S312/quote — quoting rule lines counted as a role dispatch ($ad_st: $ad_err)"
ad_run_core "$(ad_input "Explain what model-record-emit.sh does and why --stage matters? No, just the script." fork -)"
[ "$ad_st" = 0 ] && [ -z "$ad_err" ] || fail "S312/mention — a mention without a --stage command counted as a role dispatch ($ad_st: $ad_err)"

# Negative control: an edited OR8 core line changes the deny text with it.
sed 's/^- OR8 Start every dispatch prompt/- OR8 EDITED-499 Start every dispatch prompt/' "$AD_ORCH" > "$SANDBOX/orch.md"
ad_run_core "$(ad_input "Hello
$(printf '%s' "$good_dev" | tail -n +2)")" "$SANDBOX/orch.md"
[ "$ad_st" = 2 ] && grep -qxF -- "$(ad_core_line OR8 "$SANDBOX/orch.md")" <<<"$ad_err" \
  || fail "S312/edited — the deny text did not follow the edited core line"
grep -q 'EDITED-499' <<<"$ad_err" || fail "S312/edited — deny text is not read from the core"
grep -q 'Start every dispatch prompt' "$AD_CORE" && fail "S312/copy — agent-dispatch.py holds a copy of the OR8 text"

test_done
