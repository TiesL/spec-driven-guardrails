#!/usr/bin/env bash
# S267 — strict model-bearing staleness records.
# Covers: F35
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
. "$TEST_REPO_ROOT/test/fixtures/role-label-v2-helpers.sh"
for good in "$r_good" '<!-- model-record: stage=Review model="Claude Sonnet 5" effort="medium" -->'; do
 r_base; r_rows issue-comments "$r_early" "$good"; r_run; r_status stale; r_has 'expected role:reviewer'
done
for bad in "$r_bad" '<!-- model-record: stage=Review model="" -->' '<!-- model-record: stage=Review model="   " -->' '<!-- model-record: stage=Review model=claude-sonnet-5 -->' '<!-- model-record: stage=Review-draft model="claude-sonnet-5" -->' '<!-- model-record: model="claude-sonnet-5" -->'; do
 r_base; r_rows issue-comments "$r_early" "$bad"; r_run; r_status indeterminate; r_has near-miss
 case "$bad" in *stage=Review\ model*|*stage=Review--*) r_has stage=Review;; *) r_has '?';; esac
done
r_base; r_run; r_status in-sync; r_has 'no model-record marker evidenced yet'; r_absent near-miss
r_base; r_issue role:reviewer; r_rows issue-comments "$r_early" "$r_bad"; r_run; r_status indeterminate; r_has near-miss
test_done
