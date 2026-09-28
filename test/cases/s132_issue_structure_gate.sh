#!/usr/bin/env bash
# S132 — Issue-structure gate (#242): the 4th traceability link, issue ->
# acceptance-criteria structure.
# Covers: F29
#
# Found via #238's portfolio-mgt-agents audit: zero issues had any epic/
# work-item structure — no AC<n>, no Covers: field, no linked work items —
# and check-traceability.sh/scenario-gate.sh/check-pr-issue-link.sh never
# checked for it (they check PRD<->scenario, scenario<->issue, PR<->issue,
# never the issue's own shape).
#
# REST-only fixtures (issue #323): every `gh pr view --json ...`/`gh
# issue view --json ...` call this gate used to make is GraphQL-backed
# and 403s from inside a Claude Code session, and `closingIssuesReferences`
# additionally misses every release-branch PR even where it isn't
# blocked (same defect class as #318). Fixtures below mock the REST
# replacement: one combined `pulls/<pr>` call for title+body (the closing
# issue number now comes from a keyword scan of that text, title carrying
# "Closes #N" — this repo's own release-branch PR convention), and one
# combined `issues/<n>` call per closing issue for labels+body, both
# argv shapes captured by actually running the script against a
# recording fake `gh` rather than hand-retyped (this repo's own
# fixture-hygiene convention).

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

script="$TEST_REPO_ROOT/skills/pre-merge-review/issue-structure-gate.sh"
[ -x "$script" ] || { fail "S132 — skills/pre-merge-review/issue-structure-gate.sh is missing or not executable"; test_done; }

sandbox_create
trap sandbox_destroy EXIT

# Case 1: a well-formed work item (AC + Covers present) -> no findings.
fakebin_good_wi="$(fake_gh_bin '
case "$*" in
  "api repos/{owner}/{repo}/pulls/246 --jq (.title//\"\")+\"\\u0001\"+(.body//\"\")")
    printf "Closes #100\001"
    exit 0 ;;
  "api repos/{owner}/{repo}/issues/100 --jq [(.labels|map(.name)|join(\",\")), (.body//\"\")] | join(\"\\u0001\")")
    printf "enhancement\001### AC1: does the thing
- Given x
- When y
- Then z

**Covers:** S1"
    exit 0 ;;
esac
exit 1
')"
output_good_wi="$(PATH="$fakebin_good_wi:$PATH" "$script" 246)"
[ -z "$output_good_wi" ] || fail "S132 — expected no findings for a well-formed work item, got: $output_good_wi"

# W42/#114 (found during PR #251's pre-merge-review): a historical issue
# using the pre-migration Dekt: field, not Covers:, must count the same —
# same permanent exception scenario-gate.sh already carries.
fakebin_dekt="$(fake_gh_bin '
case "$*" in
  "api repos/{owner}/{repo}/pulls/246 --jq (.title//\"\")+\"\\u0001\"+(.body//\"\")")
    printf "Fixes #104\001"
    exit 0 ;;
  "api repos/{owner}/{repo}/issues/104 --jq [(.labels|map(.name)|join(\",\")), (.body//\"\")] | join(\"\\u0001\")")
    printf "\001### AC1: does the thing
- Given x
- When y
- Then z

**Dekt:** S1"
    exit 0 ;;
esac
exit 1
')"
output_dekt="$(PATH="$fakebin_dekt:$PATH" "$script" 246)"
[ -z "$output_dekt" ] || fail "S132 — expected no findings for a historical issue using Dekt:, got: $output_dekt"

# Case 2: a work item with neither AC nor Covers -> both findings.
fakebin_bad_wi="$(fake_gh_bin '
case "$*" in
  "api repos/{owner}/{repo}/pulls/246 --jq (.title//\"\")+\"\\u0001\"+(.body//\"\")")
    printf "Resolves #101\001"
    exit 0 ;;
  "api repos/{owner}/{repo}/issues/101 --jq [(.labels|map(.name)|join(\",\")), (.body//\"\")] | join(\"\\u0001\")")
    printf "\001## Description
Just some prose, no structure at all."
    exit 0 ;;
esac
exit 1
')"
output_bad_wi="$(PATH="$fakebin_bad_wi:$PATH" "$script" 246)"
case "$output_bad_wi" in
  *"#101"*"no AC<n> heading"*) : ;;
  *) fail "S132 — expected an AC-heading finding for #101, got: $output_bad_wi" ;;
esac
case "$output_bad_wi" in
  *"#101"*"no Covers: field"*) : ;;
  *) fail "S132 — expected a Covers-field finding for #101, got: $output_bad_wi" ;;
esac

# Case 3: an epic with a real linked work item -> no findings.
fakebin_good_epic="$(fake_gh_bin '
case "$*" in
  "api repos/{owner}/{repo}/pulls/246 --jq (.title//\"\")+\"\\u0001\"+(.body//\"\")")
    printf "Closes #102\001"
    exit 0 ;;
  "api repos/{owner}/{repo}/issues/102 --jq [(.labels|map(.name)|join(\",\")), (.body//\"\")] | join(\"\\u0001\")")
    printf "epic\001## Work items
- [x] #100
- [ ] #101"
    exit 0 ;;
esac
exit 1
')"
output_good_epic="$(PATH="$fakebin_good_epic:$PATH" "$script" 246)"
[ -z "$output_good_epic" ] || fail "S132 — expected no findings for an epic with real linked work items, got: $output_good_epic"

# Case 4: an epic whose Work items list is still the unfilled template
# placeholder ("- [ ] #") -> a finding.
fakebin_empty_epic="$(fake_gh_bin '
case "$*" in
  "api repos/{owner}/{repo}/pulls/246 --jq (.title//\"\")+\"\\u0001\"+(.body//\"\")")
    printf "Closes #103\001"
    exit 0 ;;
  "api repos/{owner}/{repo}/issues/103 --jq [(.labels|map(.name)|join(\",\")), (.body//\"\")] | join(\"\\u0001\")")
    printf "epic\001## Work items
- [ ] #"
    exit 0 ;;
esac
exit 1
')"
output_empty_epic="$(PATH="$fakebin_empty_epic:$PATH" "$script" 246)"
case "$output_empty_epic" in
  *"#103"*"no linked work items"*) : ;;
  *) fail "S132 — expected a no-linked-work-items finding for #103, got: $output_empty_epic" ;;
esac

# Case 5 (issue #323 AC1): a PR into a non-default base branch, where
# GitHub never populates closingIssuesReferences at all — the closing
# issue is only discoverable via the title/body keyword scan. Same shape
# as this repo's own release-branch PRs (#311/#312/#314/#316): the
# keyword sits only in the title.
fakebin_release_branch="$(fake_gh_bin '
case "$*" in
  "api repos/{owner}/{repo}/pulls/246 --jq (.title//\"\")+\"\\u0001\"+(.body//\"\")")
    printf "Closes #105\001Some unrelated PR description with no closing keyword in it."
    exit 0 ;;
  "api repos/{owner}/{repo}/issues/105 --jq [(.labels|map(.name)|join(\",\")), (.body//\"\")] | join(\"\\u0001\")")
    printf "\001## Description
No AC, no Covers."
    exit 0 ;;
esac
exit 1
')"
output_release_branch="$(PATH="$fakebin_release_branch:$PATH" "$script" 246)"
case "$output_release_branch" in
  *"#105"*"no AC<n> heading"*) : ;;
  *) fail "S132 — expected the title-only closing keyword to be found and #105 flagged, got: $output_release_branch" ;;
esac

# No gh on PATH: fails open, exit 0, just a warning.
path_without_gh="$(path_without_gh)"
output_nogh="$(PATH="$path_without_gh" "$script" 246 2>&1)"; status_nogh=$?
[ "$status_nogh" -eq 0 ] || fail "S132 — without gh the gate gave exit $status_nogh instead of 0"
assert_contains "S132 — a warning appears without gh" "warning" "$output_nogh"

# gh present but the PR title/body call fails (no network/access): fails
# open, exit 0, just a warning — not a false "no findings" silently.
fakebin_pr_fail="$(fake_gh_bin '
case "$*" in
  "api repos/{owner}/{repo}/pulls/246 --jq (.title//\"\")+\"\\u0001\"+(.body//\"\")")
    echo "HTTP 403" >&2
    exit 1 ;;
esac
exit 1
')"
output_pr_fail="$(PATH="$fakebin_pr_fail:$PATH" "$script" 246 2>&1)"; status_pr_fail=$?
[ "$status_pr_fail" -eq 0 ] || fail "S132 — a failed PR fetch gave exit $status_pr_fail instead of 0"
assert_contains "S132 — a warning appears when the PR fetch fails" "warning" "$output_pr_fail"

test_done
