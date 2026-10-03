#!/usr/bin/env bash
# S130 — Model-record gate (#241 AC1): every pipeline stage's model choice
# must carry a machine-readable marker, not just Review.
# Covers: F27
#
# Found via #238's portfolio-mgt-agents audit: only the Review stage ever
# recorded a model in practice — Discovery/Planning/Test/Implementation
# never did, and CHANGES.md's process-model-choice row had no way to
# check for that mechanically.
#
# REST-only fixtures (issue #318): every `gh pr view --json ...`/`gh
# issue view --json ...` call this gate used to make is GraphQL-backed
# and 403s from inside a Claude Code session; `closingIssuesReferences`
# additionally misses every release-branch PR even where it isn't
# blocked. Fixtures below mock the REST replacement: one combined
# `pulls/<pr>` call for title+body (title carries "Closes #239" in
# place of the old direct closingIssuesReferences=239 fixture —
# matching this repo's own release-branch PR convention, title-only),
# `issues/<pr>/comments` for PR comments, `pulls/<pr>/reviews` for PR
# reviews (a new source this gate never read before either — see
# model-record-gate.sh's own comment), and `issues/239/comments` for
# the closing issue.
#
# Issue #392, round 4 of the PR #397 review: the gate now frames every
# comment/review body with U+001E for all projects (after removing that byte
# from the body), so the marker parser keeps a malformed marker inside its
# own comment. The `--jq` in the arms below is that framing expression; what
# this test pins is unchanged: REST endpoints only, `--paginate`, the exact
# call set (any other call falls through to `exit 1`).
#
# Issue #392: the same-model arms below now exercise the effort rule (Review at
# LOWER effort than Implementation is the finding; a legacy same-model-exception
# neither waives it nor is required) and every Review marker carries a
# floor-basis. The full floor rule (floor-basis presence, unknown efforts,
# different models) is S189.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

script="$TEST_REPO_ROOT/skills/pre-merge-review/model-record-gate.sh"
[ -x "$script" ] || { fail "S130 — skills/pre-merge-review/model-record-gate.sh is missing or not executable"; test_done; }

sandbox_create
trap sandbox_destroy EXIT
# #371: the gate now reads the working directory's WORKFLOW-ADOPTION.md
# (role-play detection, opted-in projects only, S183). These fixtures put
# several stages in one text on purpose and pin the not-opted-in call
# shapes, so run from the sandbox, not from whatever checkout launched the
# suite (this repo answers process-multi-agent-roles yes).
cd "$SANDBOX" || exit 1

# PR carries Review, Planning, Test, Implementation markers; the issue it
# closes carries Discovery's. All five present -> no findings.
fakebin_complete="$(fake_gh_bin '
case "$*" in
  "api repos/{owner}/{repo}/pulls/246 --jq (.title//\"\")+\"\\u0001\"+(.body//\"\")")
    printf "Closes #239\001"
    exit 0 ;;
  "api repos/{owner}/{repo}/issues/246/comments --paginate --jq .[] | (.body // \"\" | gsub(\"\\u001e\"; \"\")) + \"\\u001e\"")
    printf "%s\n" "<!-- model-record: stage=Planning model=\"Opus\" effort=\"high\" -->"
    printf "%s\n" "<!-- model-record: stage=Test model=\"Sonnet\" effort=\"medium\" -->"
    printf "%s\n" "<!-- model-record: stage=Implementation model=\"Sonnet\" effort=\"medium\" -->"
    printf "%s\n" "<!-- model-record: stage=Review model=\"Opus\" effort=\"high\" floor-basis=\"stronger model than Implementation\" -->"
    exit 0 ;;
  "api repos/{owner}/{repo}/pulls/246/reviews --paginate --jq .[] | (.body // \"\" | gsub(\"\\u001e\"; \"\")) + \"\\u001e\"")
    printf "%s" ""
    exit 0 ;;
  "api repos/{owner}/{repo}/issues/239/comments --paginate --jq .[] | (.body // \"\" | gsub(\"\\u001e\"; \"\")) + \"\\u001e\"")
    printf "%s" "<!-- model-record: stage=Discovery model=\"Sonnet\" effort=\"low\" -->"
    exit 0 ;;
esac
exit 1
')"

output_complete="$(PATH="$fakebin_complete:$PATH" "$script" 246)"
[ -z "$output_complete" ] || fail "S130 — expected no findings when all five stages are recorded, got: $output_complete"

# PR carries only Review's marker; the closed issue carries none. Three
# stages missing (Discovery is on the issue and absent; Planning/Test/
# Implementation are missing from the PR).
fakebin_partial="$(fake_gh_bin '
case "$*" in
  "api repos/{owner}/{repo}/pulls/246 --jq (.title//\"\")+\"\\u0001\"+(.body//\"\")")
    printf "Closes #239\001"
    exit 0 ;;
  "api repos/{owner}/{repo}/issues/246/comments --paginate --jq .[] | (.body // \"\" | gsub(\"\\u001e\"; \"\")) + \"\\u001e\"")
    printf "%s" "<!-- model-record: stage=Review model=\"Opus\" effort=\"high\" floor-basis=\"stronger model than Implementation\" -->"
    exit 0 ;;
  "api repos/{owner}/{repo}/pulls/246/reviews --paginate --jq .[] | (.body // \"\" | gsub(\"\\u001e\"; \"\")) + \"\\u001e\"")
    printf "%s" ""
    exit 0 ;;
  "api repos/{owner}/{repo}/issues/239/comments --paginate --jq .[] | (.body // \"\" | gsub(\"\\u001e\"; \"\")) + \"\\u001e\"")
    printf "%s" ""
    exit 0 ;;
esac
exit 1
')"

output_partial="$(PATH="$fakebin_partial:$PATH" "$script" 246)"
for stage in Discovery Planning Test Implementation; do
  case "$output_partial" in
    *"stage $stage"*) : ;;
    *) fail "S130 — expected a missing-record finding for stage $stage, got: $output_partial" ;;
  esac
done
case "$output_partial" in
  *"stage Review"*) fail "S130 — Review is recorded and should not be reported missing, got: $output_partial" ;;
  *) : ;;
esac

# No gh on PATH: fails open, exit 0, just a warning.
path_without_gh="$(path_without_gh)"
output_nogh="$(PATH="$path_without_gh" "$script" 246 2>&1)"; status_nogh=$?
[ "$status_nogh" -eq 0 ] || fail "S130 — without gh the gate gave exit $status_nogh instead of 0"
assert_contains "S130 — a warning appears without gh" "warning" "$output_nogh"

# The PR comments lookup failing (transient) must warn and skip the
# whole check, same as before — this is the first call the gate makes.
fakebin_comments_fail="$(fake_gh_bin '
case "$*" in
  "api repos/{owner}/{repo}/issues/246/comments --paginate --jq .[] | (.body // \"\" | gsub(\"\\u001e\"; \"\")) + \"\\u001e\"")
    echo "gh: could not resolve to a PullRequest" >&2
    exit 1 ;;
esac
exit 1
')"
output_comments_fail="$(PATH="$fakebin_comments_fail:$PATH" "$script" 246 2>&1)"; status_comments_fail=$?
[ "$status_comments_fail" -eq 0 ] || fail "S130 — a failed PR-comments lookup gave exit $status_comments_fail instead of 0"
assert_contains "S130 — a warning appears when the PR-comments lookup fails" "warning" "$output_comments_fail"

# The per-issue lookup failing (transient, not "issue has no records")
# must warn, not silently misreport Discovery as missing — found during
# PR #249's pre-merge-review, round 2.
fakebin_issue_fails="$(fake_gh_bin '
case "$*" in
  "api repos/{owner}/{repo}/pulls/246 --jq (.title//\"\")+\"\\u0001\"+(.body//\"\")")
    printf "Closes #239\001"
    exit 0 ;;
  "api repos/{owner}/{repo}/issues/246/comments --paginate --jq .[] | (.body // \"\" | gsub(\"\\u001e\"; \"\")) + \"\\u001e\"")
    printf "%s" "<!-- model-record: stage=Planning model=\"Sonnet\" effort=\"medium\" -->"
    exit 0 ;;
  "api repos/{owner}/{repo}/pulls/246/reviews --paginate --jq .[] | (.body // \"\" | gsub(\"\\u001e\"; \"\")) + \"\\u001e\"")
    printf "%s" ""
    exit 0 ;;
  "api repos/{owner}/{repo}/issues/239/comments --paginate --jq .[] | (.body // \"\" | gsub(\"\\u001e\"; \"\")) + \"\\u001e\"")
    echo "gh: could not resolve to an Issue" >&2
    exit 1 ;;
esac
exit 1
')"

output_issue_fails="$(PATH="$fakebin_issue_fails:$PATH" "$script" 246 2>&1)"
assert_contains "S130 — a warning appears when the issue lookup fails" "warning" "$output_issue_fails"

# A marker posted directly in the PR's own description, not a comment,
# must still be found — found during PR #251's pre-merge-review: the gate
# only ever scanned comments, missing markers added at PR-creation time.
fakebin_body_marker="$(fake_gh_bin '
case "$*" in
  "api repos/{owner}/{repo}/pulls/246 --jq (.title//\"\")+\"\\u0001\"+(.body//\"\")")
    printf "Closes #239\001%s\n%s\n%s" \
      "<!-- model-record: stage=Planning model=\"Sonnet\" effort=\"medium\" -->" \
      "<!-- model-record: stage=Test model=\"Sonnet\" effort=\"medium\" -->" \
      "<!-- model-record: stage=Implementation model=\"Sonnet\" effort=\"medium\" -->"
    exit 0 ;;
  "api repos/{owner}/{repo}/issues/246/comments --paginate --jq .[] | (.body // \"\" | gsub(\"\\u001e\"; \"\")) + \"\\u001e\"")
    printf "%s" "<!-- model-record: stage=Review model=\"Opus\" effort=\"high\" floor-basis=\"stronger model than Implementation\" -->"
    exit 0 ;;
  "api repos/{owner}/{repo}/pulls/246/reviews --paginate --jq .[] | (.body // \"\" | gsub(\"\\u001e\"; \"\")) + \"\\u001e\"")
    printf "%s" ""
    exit 0 ;;
  "api repos/{owner}/{repo}/issues/239/comments --paginate --jq .[] | (.body // \"\" | gsub(\"\\u001e\"; \"\")) + \"\\u001e\"")
    printf "%s" "<!-- model-record: stage=Discovery model=\"Sonnet\" effort=\"low\" -->"
    exit 0 ;;
esac
exit 1
')"

output_body_marker="$(PATH="$fakebin_body_marker:$PATH" "$script" 246)"
[ -z "$output_body_marker" ] || fail "S130 — expected no findings when markers live in the PR description, got: $output_body_marker"

# A marker posted as a PR review's own body (issue #318, the same F-6
# class finding role-label-staleness.sh's review already surfaced) must
# also be found — a source this gate never read under the old design
# either.
fakebin_review_marker="$(fake_gh_bin '
case "$*" in
  "api repos/{owner}/{repo}/pulls/246 --jq (.title//\"\")+\"\\u0001\"+(.body//\"\")")
    printf "Closes #239\001"
    exit 0 ;;
  "api repos/{owner}/{repo}/issues/246/comments --paginate --jq .[] | (.body // \"\" | gsub(\"\\u001e\"; \"\")) + \"\\u001e\"")
    printf "%s\n" "<!-- model-record: stage=Planning model=\"Sonnet\" effort=\"medium\" -->"
    printf "%s\n" "<!-- model-record: stage=Test model=\"Sonnet\" effort=\"medium\" -->"
    printf "%s\n" "<!-- model-record: stage=Implementation model=\"Sonnet\" effort=\"medium\" -->"
    exit 0 ;;
  "api repos/{owner}/{repo}/pulls/246/reviews --paginate --jq .[] | (.body // \"\" | gsub(\"\\u001e\"; \"\")) + \"\\u001e\"")
    printf "%s" "<!-- model-record: stage=Review model=\"Opus\" effort=\"high\" floor-basis=\"stronger model than Implementation\" -->"
    exit 0 ;;
  "api repos/{owner}/{repo}/issues/239/comments --paginate --jq .[] | (.body // \"\" | gsub(\"\\u001e\"; \"\")) + \"\\u001e\"")
    printf "%s" "<!-- model-record: stage=Discovery model=\"Sonnet\" effort=\"low\" -->"
    exit 0 ;;
esac
exit 1
')"

output_review_marker="$(PATH="$fakebin_review_marker:$PATH" "$script" 246)"
[ -z "$output_review_marker" ] || fail "S130 — expected no findings when the Review marker lives in a PR review body, got: $output_review_marker"

# #392 (replaces #244 AC2): Review and Implementation recording the same
# model, with Review at LOWER effort (low vs. medium), is a finding that
# names the model and no longer mentions same-model-exception.
fakebin_same_model="$(fake_gh_bin '
case "$*" in
  "api repos/{owner}/{repo}/pulls/246 --jq (.title//\"\")+\"\\u0001\"+(.body//\"\")")
    printf "Closes #239\001"
    exit 0 ;;
  "api repos/{owner}/{repo}/issues/246/comments --paginate --jq .[] | (.body // \"\" | gsub(\"\\u001e\"; \"\")) + \"\\u001e\"")
    printf "%s\n" "<!-- model-record: stage=Planning model=\"Sonnet\" effort=\"medium\" -->"
    printf "%s\n" "<!-- model-record: stage=Test model=\"Sonnet\" effort=\"medium\" -->"
    printf "%s\n" "<!-- model-record: stage=Implementation model=\"Sonnet\" effort=\"medium\" -->"
    printf "%s\n" "<!-- model-record: stage=Review model=\"Sonnet\" effort=\"low\" floor-basis=\"stronger model than Implementation\" -->"
    exit 0 ;;
  "api repos/{owner}/{repo}/pulls/246/reviews --paginate --jq .[] | (.body // \"\" | gsub(\"\\u001e\"; \"\")) + \"\\u001e\"")
    printf "%s" ""
    exit 0 ;;
  "api repos/{owner}/{repo}/issues/239/comments --paginate --jq .[] | (.body // \"\" | gsub(\"\\u001e\"; \"\")) + \"\\u001e\"")
    printf "%s" "<!-- model-record: stage=Discovery model=\"Sonnet\" effort=\"low\" -->"
    exit 0 ;;
esac
exit 1
')"
output_same_model="$(PATH="$fakebin_same_model:$PATH" "$script" 246)"
case "$output_same_model" in
  *"same model"*"Sonnet"*) : ;;
  *) fail "S130 — expected a same-model lower-effort finding, got: $output_same_model" ;;
esac
case "$output_same_model" in
  *same-model-exception*) fail "S130 — the finding must not ask for a same-model-exception any more (#392), got: $output_same_model" ;;
esac

# ...and a legacy same-model-exception on that lower-effort Review is NOT a
# waiver any more (#392 AC5: the attribute is ignored completely).
fakebin_same_model_excepted="$(fake_gh_bin '
case "$*" in
  "api repos/{owner}/{repo}/pulls/246 --jq (.title//\"\")+\"\\u0001\"+(.body//\"\")")
    printf "Closes #239\001"
    exit 0 ;;
  "api repos/{owner}/{repo}/issues/246/comments --paginate --jq .[] | (.body // \"\" | gsub(\"\\u001e\"; \"\")) + \"\\u001e\"")
    printf "%s\n" "<!-- model-record: stage=Planning model=\"Sonnet\" effort=\"medium\" -->"
    printf "%s\n" "<!-- model-record: stage=Test model=\"Sonnet\" effort=\"medium\" -->"
    printf "%s\n" "<!-- model-record: stage=Implementation model=\"Sonnet\" effort=\"medium\" -->"
    printf "%s\n" "<!-- model-record: stage=Review model=\"Sonnet\" effort=\"low\" same-model-exception=\"only one model available\" floor-basis=\"stronger model than Implementation\" -->"
    exit 0 ;;
  "api repos/{owner}/{repo}/pulls/246/reviews --paginate --jq .[] | (.body // \"\" | gsub(\"\\u001e\"; \"\")) + \"\\u001e\"")
    printf "%s" ""
    exit 0 ;;
  "api repos/{owner}/{repo}/issues/239/comments --paginate --jq .[] | (.body // \"\" | gsub(\"\\u001e\"; \"\")) + \"\\u001e\"")
    printf "%s" "<!-- model-record: stage=Discovery model=\"Sonnet\" effort=\"low\" -->"
    exit 0 ;;
esac
exit 1
')"
output_excepted="$(PATH="$fakebin_same_model_excepted:$PATH" "$script" 246)"
case "$output_excepted" in
  *"same model"*"Sonnet"*) : ;;
  *) fail "S130 — a legacy same-model-exception must not waive a lower-effort same-model Review, got: $output_excepted" ;;
esac

# Found during PR #253's pre-merge-review: the latest marker per stage
# must win, not the first. Round 1 recorded a genuine different-model
# Review; round 2's fixup re-recorded Review with the same model as
# Implementation, no exception. The violation is in round 2 and must be
# caught, even though round 1's marker (different model) appears earlier
# in the text.
fakebin_latest_wins="$(fake_gh_bin '
case "$*" in
  "api repos/{owner}/{repo}/pulls/246 --jq (.title//\"\")+\"\\u0001\"+(.body//\"\")")
    printf "Closes #239\001"
    exit 0 ;;
  "api repos/{owner}/{repo}/issues/246/comments --paginate --jq .[] | (.body // \"\" | gsub(\"\\u001e\"; \"\")) + \"\\u001e\"")
    printf "%s\n" "<!-- model-record: stage=Implementation model=\"Sonnet\" effort=\"medium\" -->"
    printf "%s\n" "<!-- model-record: stage=Review model=\"Opus\" effort=\"medium\" floor-basis=\"stronger model than Implementation\" -->"
    printf "%s\n" "<!-- model-record: stage=Review model=\"Sonnet\" effort=\"low\" floor-basis=\"stronger model than Implementation\" -->"
    exit 0 ;;
  "api repos/{owner}/{repo}/pulls/246/reviews --paginate --jq .[] | (.body // \"\" | gsub(\"\\u001e\"; \"\")) + \"\\u001e\"")
    printf "%s" ""
    exit 0 ;;
  "api repos/{owner}/{repo}/issues/239/comments --paginate --jq .[] | (.body // \"\" | gsub(\"\\u001e\"; \"\")) + \"\\u001e\"")
    printf "%s\n" "<!-- model-record: stage=Discovery model=\"Sonnet\" effort=\"low\" -->"
    printf "%s\n" "<!-- model-record: stage=Planning model=\"Sonnet\" effort=\"medium\" -->"
    printf "%s\n" "<!-- model-record: stage=Test model=\"Sonnet\" effort=\"medium\" -->"
    exit 0 ;;
esac
exit 1
')"
output_latest_wins="$(PATH="$fakebin_latest_wins:$PATH" "$script" 246)"
case "$output_latest_wins" in
  *"same model"*) : ;;
  *) fail "S130 — expected the latest (round-2) Review marker to be checked, not the first, got: $output_latest_wins" ;;
esac

# An unquoted marker (model=Sonnet, no quotes) must not be silently
# folded into a false "same model" or "different model" claim — the
# comparison is skipped, not guessed at.
fakebin_unquoted="$(fake_gh_bin '
case "$*" in
  "api repos/{owner}/{repo}/pulls/246 --jq (.title//\"\")+\"\\u0001\"+(.body//\"\")")
    printf "Closes #239\001"
    exit 0 ;;
  "api repos/{owner}/{repo}/issues/246/comments --paginate --jq .[] | (.body // \"\" | gsub(\"\\u001e\"; \"\")) + \"\\u001e\"")
    printf "%s\n" "<!-- model-record: stage=Implementation model=Sonnet effort=medium -->"
    printf "%s\n" "<!-- model-record: stage=Review model=Sonnet effort=medium -->"
    exit 0 ;;
  "api repos/{owner}/{repo}/pulls/246/reviews --paginate --jq .[] | (.body // \"\" | gsub(\"\\u001e\"; \"\")) + \"\\u001e\"")
    printf "%s" ""
    exit 0 ;;
  "api repos/{owner}/{repo}/issues/239/comments --paginate --jq .[] | (.body // \"\" | gsub(\"\\u001e\"; \"\")) + \"\\u001e\"")
    printf "%s\n" "<!-- model-record: stage=Discovery model=\"Sonnet\" effort=\"low\" -->"
    printf "%s\n" "<!-- model-record: stage=Planning model=\"Sonnet\" effort=\"medium\" -->"
    printf "%s\n" "<!-- model-record: stage=Test model=\"Sonnet\" effort=\"medium\" -->"
    exit 0 ;;
esac
exit 1
')"
output_unquoted="$(PATH="$fakebin_unquoted:$PATH" "$script" 246)"
case "$output_unquoted" in
  *"same model"*) fail "S130 — expected an unquoted marker to skip the same-model comparison, not claim a match, got: $output_unquoted" ;;
  *) : ;;
esac

# A legacy empty-reason exception (same-model-exception="") is ignored
# (#392 AC5): same model at EQUAL effort with a floor-basis is no finding,
# and the attribute does not break anything.
fakebin_empty_exception="$(fake_gh_bin '
case "$*" in
  "api repos/{owner}/{repo}/pulls/246 --jq (.title//\"\")+\"\\u0001\"+(.body//\"\")")
    printf "Closes #239\001"
    exit 0 ;;
  "api repos/{owner}/{repo}/issues/246/comments --paginate --jq .[] | (.body // \"\" | gsub(\"\\u001e\"; \"\")) + \"\\u001e\"")
    printf "%s\n" "<!-- model-record: stage=Implementation model=\"Sonnet\" effort=\"medium\" -->"
    printf "%s\n" "<!-- model-record: stage=Review model=\"Sonnet\" effort=\"medium\" same-model-exception=\"\" floor-basis=\"stronger model than Implementation\" -->"
    exit 0 ;;
  "api repos/{owner}/{repo}/pulls/246/reviews --paginate --jq .[] | (.body // \"\" | gsub(\"\\u001e\"; \"\")) + \"\\u001e\"")
    printf "%s" ""
    exit 0 ;;
  "api repos/{owner}/{repo}/issues/239/comments --paginate --jq .[] | (.body // \"\" | gsub(\"\\u001e\"; \"\")) + \"\\u001e\"")
    printf "%s\n" "<!-- model-record: stage=Discovery model=\"Sonnet\" effort=\"low\" -->"
    printf "%s\n" "<!-- model-record: stage=Planning model=\"Sonnet\" effort=\"medium\" -->"
    printf "%s\n" "<!-- model-record: stage=Test model=\"Sonnet\" effort=\"medium\" -->"
    exit 0 ;;
esac
exit 1
')"
output_empty_exception="$(PATH="$fakebin_empty_exception:$PATH" "$script" 246)"
[ -z "$output_empty_exception" ] || fail "S130 — a legacy empty same-model-exception must be ignored (same model, equal effort, floor-basis present: no finding), got: $output_empty_exception"

# Case-insensitive: "Claude Sonnet 5" and "claude sonnet 5" are the same
# model spelled differently, still compared (Review effort lower: a finding).
fakebin_case_insensitive="$(fake_gh_bin '
case "$*" in
  "api repos/{owner}/{repo}/pulls/246 --jq (.title//\"\")+\"\\u0001\"+(.body//\"\")")
    printf "Closes #239\001"
    exit 0 ;;
  "api repos/{owner}/{repo}/issues/246/comments --paginate --jq .[] | (.body // \"\" | gsub(\"\\u001e\"; \"\")) + \"\\u001e\"")
    printf "%s\n" "<!-- model-record: stage=Implementation model=\"Claude Sonnet 5\" effort=\"medium\" -->"
    printf "%s\n" "<!-- model-record: stage=Review model=\"claude sonnet 5\" effort=\"low\" floor-basis=\"stronger model than Implementation\" -->"
    exit 0 ;;
  "api repos/{owner}/{repo}/pulls/246/reviews --paginate --jq .[] | (.body // \"\" | gsub(\"\\u001e\"; \"\")) + \"\\u001e\"")
    printf "%s" ""
    exit 0 ;;
  "api repos/{owner}/{repo}/issues/239/comments --paginate --jq .[] | (.body // \"\" | gsub(\"\\u001e\"; \"\")) + \"\\u001e\"")
    printf "%s\n" "<!-- model-record: stage=Discovery model=\"Sonnet\" effort=\"low\" -->"
    printf "%s\n" "<!-- model-record: stage=Planning model=\"Sonnet\" effort=\"medium\" -->"
    printf "%s\n" "<!-- model-record: stage=Test model=\"Sonnet\" effort=\"medium\" -->"
    exit 0 ;;
esac
exit 1
')"
output_case_insensitive="$(PATH="$fakebin_case_insensitive:$PATH" "$script" 246)"
case "$output_case_insensitive" in
  *"same model"*) : ;;
  *) fail "S130 — expected a case-only spelling difference to still be flagged as the same model, got: $output_case_insensitive" ;;
esac

# Found during PR #253's pre-merge-review (round 2): a stray, older
# Review marker on the closing issue must not outrank a genuinely newer
# one on the PR itself just because issue text used to be concatenated
# last. The issue's marker (Sonnet, same as Implementation) is the older,
# wrong one; the PR's own marker (Opus, genuinely different) is what
# actually reflects this PR's real review and must be what's checked.
fakebin_issue_marker_stale="$(fake_gh_bin '
case "$*" in
  "api repos/{owner}/{repo}/pulls/246 --jq (.title//\"\")+\"\\u0001\"+(.body//\"\")")
    printf "Closes #239\001"
    exit 0 ;;
  "api repos/{owner}/{repo}/issues/246/comments --paginate --jq .[] | (.body // \"\" | gsub(\"\\u001e\"; \"\")) + \"\\u001e\"")
    printf "%s\n" "<!-- model-record: stage=Implementation model=\"Sonnet\" effort=\"medium\" -->"
    printf "%s\n" "<!-- model-record: stage=Review model=\"Opus\" effort=\"medium\" floor-basis=\"stronger model than Implementation\" -->"
    exit 0 ;;
  "api repos/{owner}/{repo}/pulls/246/reviews --paginate --jq .[] | (.body // \"\" | gsub(\"\\u001e\"; \"\")) + \"\\u001e\"")
    printf "%s" ""
    exit 0 ;;
  "api repos/{owner}/{repo}/issues/239/comments --paginate --jq .[] | (.body // \"\" | gsub(\"\\u001e\"; \"\")) + \"\\u001e\"")
    printf "%s\n" "<!-- model-record: stage=Discovery model=\"Sonnet\" effort=\"low\" -->"
    printf "%s\n" "<!-- model-record: stage=Planning model=\"Sonnet\" effort=\"medium\" -->"
    printf "%s\n" "<!-- model-record: stage=Test model=\"Sonnet\" effort=\"medium\" -->"
    printf "%s\n" "<!-- model-record: stage=Review model=\"Sonnet\" effort=\"medium\" floor-basis=\"stronger model than Implementation\" -->"
    exit 0 ;;
esac
exit 1
')"
output_issue_marker_stale="$(PATH="$fakebin_issue_marker_stale:$PATH" "$script" 246)"
case "$output_issue_marker_stale" in
  *"same model"*) fail "S130 — a stray older Review marker on the issue wrongly outranked the PR's own, got: $output_issue_marker_stale" ;;
  *) : ;;
esac

# #268: a display-name label and an API model-id label for the same
# underlying model must still be compared on effort (low vs. medium: flagged) — the exact failure case found
# during PR #267's pre-merge-review, round 2 (Review recorded "Sonnet 5",
# Implementation recorded "claude-sonnet-5" — plain case-folding didn't
# equate those either, only normalize_model's structural fold does).
fakebin_label_mismatch="$(fake_gh_bin '
case "$*" in
  "api repos/{owner}/{repo}/pulls/246 --jq (.title//\"\")+\"\\u0001\"+(.body//\"\")")
    printf "Closes #239\001"
    exit 0 ;;
  "api repos/{owner}/{repo}/issues/246/comments --paginate --jq .[] | (.body // \"\" | gsub(\"\\u001e\"; \"\")) + \"\\u001e\"")
    printf "%s\n" "<!-- model-record: stage=Implementation model=\"claude-sonnet-5\" effort=\"medium\" -->"
    printf "%s\n" "<!-- model-record: stage=Review model=\"Sonnet 5\" effort=\"low\" floor-basis=\"stronger model than Implementation\" -->"
    exit 0 ;;
  "api repos/{owner}/{repo}/pulls/246/reviews --paginate --jq .[] | (.body // \"\" | gsub(\"\\u001e\"; \"\")) + \"\\u001e\"")
    printf "%s" ""
    exit 0 ;;
  "api repos/{owner}/{repo}/issues/239/comments --paginate --jq .[] | (.body // \"\" | gsub(\"\\u001e\"; \"\")) + \"\\u001e\"")
    printf "%s\n" "<!-- model-record: stage=Discovery model=\"Sonnet 5\" effort=\"low\" -->"
    printf "%s\n" "<!-- model-record: stage=Planning model=\"Sonnet 5\" effort=\"medium\" -->"
    printf "%s\n" "<!-- model-record: stage=Test model=\"Sonnet 5\" effort=\"medium\" -->"
    exit 0 ;;
esac
exit 1
')"
output_label_mismatch="$(PATH="$fakebin_label_mismatch:$PATH" "$script" 246)"
case "$output_label_mismatch" in
  *"same model"*) : ;;
  *) fail "S130 — expected a display-name/API-id label mismatch for the same model to still be flagged, got: $output_label_mismatch" ;;
esac

# ...but genuinely different models under different label styles (Opus
# vs. Sonnet) must not be flagged — normalize_model folds format, not
# model identity, away.
fakebin_different_models_different_labels="$(fake_gh_bin '
case "$*" in
  "api repos/{owner}/{repo}/pulls/246 --jq (.title//\"\")+\"\\u0001\"+(.body//\"\")")
    printf "Closes #239\001"
    exit 0 ;;
  "api repos/{owner}/{repo}/issues/246/comments --paginate --jq .[] | (.body // \"\" | gsub(\"\\u001e\"; \"\")) + \"\\u001e\"")
    printf "%s\n" "<!-- model-record: stage=Implementation model=\"claude-sonnet-5\" effort=\"medium\" -->"
    printf "%s\n" "<!-- model-record: stage=Review model=\"Opus 5\" effort=\"medium\" floor-basis=\"stronger model than Implementation\" -->"
    exit 0 ;;
  "api repos/{owner}/{repo}/pulls/246/reviews --paginate --jq .[] | (.body // \"\" | gsub(\"\\u001e\"; \"\")) + \"\\u001e\"")
    printf "%s" ""
    exit 0 ;;
  "api repos/{owner}/{repo}/issues/239/comments --paginate --jq .[] | (.body // \"\" | gsub(\"\\u001e\"; \"\")) + \"\\u001e\"")
    printf "%s\n" "<!-- model-record: stage=Discovery model=\"Sonnet 5\" effort=\"low\" -->"
    printf "%s\n" "<!-- model-record: stage=Planning model=\"Sonnet 5\" effort=\"medium\" -->"
    printf "%s\n" "<!-- model-record: stage=Test model=\"Sonnet 5\" effort=\"medium\" -->"
    exit 0 ;;
esac
exit 1
')"
output_different_models="$(PATH="$fakebin_different_models_different_labels:$PATH" "$script" 246)"
case "$output_different_models" in
  *"same model"*) fail "S130 — genuinely different models under different label styles were wrongly flagged as the same, got: $output_different_models" ;;
  *) : ;;
esac

# Issue #318 regression guard: the closing-issue reference now comes from
# a closing keyword in the PR's title (this repo's own release-branch PR
# convention — #311/#312/#314/#316 all carry it there, never in the
# body), not from a direct closingIssuesReferences fixture. Confirm a
# title-only reference is actually followed to the issue.
fakebin_title_only_reference="$(fake_gh_bin '
case "$*" in
  "api repos/{owner}/{repo}/pulls/246 --jq (.title//\"\")+\"\\u0001\"+(.body//\"\")")
    printf "Closes #239: some change\001some unrelated body text"
    exit 0 ;;
  "api repos/{owner}/{repo}/issues/246/comments --paginate --jq .[] | (.body // \"\" | gsub(\"\\u001e\"; \"\")) + \"\\u001e\"")
    printf "%s\n" "<!-- model-record: stage=Implementation model=\"Sonnet\" effort=\"medium\" -->"
    printf "%s\n" "<!-- model-record: stage=Review model=\"Opus\" effort=\"medium\" floor-basis=\"stronger model than Implementation\" -->"
    exit 0 ;;
  "api repos/{owner}/{repo}/pulls/246/reviews --paginate --jq .[] | (.body // \"\" | gsub(\"\\u001e\"; \"\")) + \"\\u001e\"")
    printf "%s" ""
    exit 0 ;;
  "api repos/{owner}/{repo}/issues/239/comments --paginate --jq .[] | (.body // \"\" | gsub(\"\\u001e\"; \"\")) + \"\\u001e\"")
    printf "%s\n" "<!-- model-record: stage=Discovery model=\"Sonnet\" effort=\"low\" -->"
    printf "%s\n" "<!-- model-record: stage=Planning model=\"Sonnet\" effort=\"medium\" -->"
    printf "%s\n" "<!-- model-record: stage=Test model=\"Sonnet\" effort=\"medium\" -->"
    exit 0 ;;
esac
exit 1
')"
output_title_only="$(PATH="$fakebin_title_only_reference:$PATH" "$script" 246)"
[ -z "$output_title_only" ] || fail "S130 — expected a title-only closing-keyword reference to be followed to issue #239, got: $output_title_only"

test_done
