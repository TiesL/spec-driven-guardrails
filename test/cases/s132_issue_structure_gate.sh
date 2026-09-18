#!/usr/bin/env bash
# S132 — Issue-structure gate (#242): the 4th traceability link, issue ->
# acceptance-criteria structure.
# Covers: F9
#
# Found via #238's portfolio-mgt-agents audit: zero issues had any epic/
# work-item structure — no AC<n>, no Covers: field, no linked work items —
# and check-traceability.sh/scenario-gate.sh/check-pr-issue-link.sh never
# checked for it (they check PRD<->scenario, scenario<->issue, PR<->issue,
# never the issue's own shape).

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
  "pr view 246 --json closingIssuesReferences --jq .closingIssuesReferences[].number")
    printf "%s\n" "100"
    exit 0 ;;
  "issue view 100 --json labels --jq .labels[].name")
    printf "%s\n" "enhancement"
    exit 0 ;;
  "issue view 100 --json body --jq .body")
    printf "%s" "### AC1: does the thing
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
  "pr view 246 --json closingIssuesReferences --jq .closingIssuesReferences[].number")
    printf "%s\n" "104"
    exit 0 ;;
  "issue view 104 --json labels --jq .labels[].name")
    printf "%s\n" ""
    exit 0 ;;
  "issue view 104 --json body --jq .body")
    printf "%s" "### AC1: does the thing
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
  "pr view 246 --json closingIssuesReferences --jq .closingIssuesReferences[].number")
    printf "%s\n" "101"
    exit 0 ;;
  "issue view 101 --json labels --jq .labels[].name")
    printf "%s\n" ""
    exit 0 ;;
  "issue view 101 --json body --jq .body")
    printf "%s" "## Description
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
  "pr view 246 --json closingIssuesReferences --jq .closingIssuesReferences[].number")
    printf "%s\n" "102"
    exit 0 ;;
  "issue view 102 --json labels --jq .labels[].name")
    printf "%s\n" "epic"
    exit 0 ;;
  "issue view 102 --json body --jq .body")
    printf "%s" "## Work items
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
  "pr view 246 --json closingIssuesReferences --jq .closingIssuesReferences[].number")
    printf "%s\n" "103"
    exit 0 ;;
  "issue view 103 --json labels --jq .labels[].name")
    printf "%s\n" "epic"
    exit 0 ;;
  "issue view 103 --json body --jq .body")
    printf "%s" "## Work items
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

# No gh on PATH: fails open, exit 0, just a warning.
path_without_gh="$(path_without_gh)"
output_nogh="$(PATH="$path_without_gh" "$script" 246 2>&1)"; status_nogh=$?
[ "$status_nogh" -eq 0 ] || fail "S132 — without gh the gate gave exit $status_nogh instead of 0"
assert_contains "S132 — a warning appears without gh" "warning" "$output_nogh"

test_done
