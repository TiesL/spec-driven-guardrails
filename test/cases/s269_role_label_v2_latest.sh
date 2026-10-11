#!/usr/bin/env bash
# S269 — latest candidate by timestamp and source order.
# Covers: F35
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
. "$TEST_REPO_ROOT/test/fixtures/role-label-v2-helpers.sh"
# Fixed retrieval order, reversed times: both directions falsify global flags.
for latest in bad good; do
 for pair in issue-comments description-comments comments-reviews; do
  r_base; r_link
  a="$r_good"; b="$r_bad"
  if [ "$latest" = bad ]; then ta="$r_early"; tb="$r_late"; else ta="$r_late"; tb="$r_early"; fi
  case "$pair" in
   issue-comments) r_issue role:architect "$a" "$ta"; r_rows issue-comments "$tb" "$b";;
   description-comments) r_pr "$a" "$ta"; r_rows comments "$tb" "$b";;
   comments-reviews) r_rows comments "$ta" "$a"; r_rows reviews "$tb" "$b";;
  esac
  r_run; if [ "$latest" = bad ]; then r_status indeterminate; r_has near-miss; r_has stage=Review; else r_status stale; r_has 'expected role:reviewer'; fi
 done
 r_base; r_rows issue-comments "$tb" "$b" "$ta" "$a"; r_run
 if [ "$latest" = bad ]; then r_status indeterminate; else r_status stale; fi
 if [ "$latest" = bad ]; then a="$r_good"; b="$r_bad"; else a="$r_bad"; b="$r_good"; fi
 # Equal-time source order and line order each select the later candidate.
 r_base; r_link; r_rows comments "$r_early" "$a"; r_rows reviews "$r_early" "$b"; r_run
 if [ "$latest" = bad ]; then r_status indeterminate; else r_status stale; fi
 r_base; r_rows issue-comments "$r_early" "$a"$'\n'"$b"; r_run
 if [ "$latest" = bad ]; then r_status indeterminate; else r_status stale; fi
done
r_base; r_rows issue-comments "$r_early" "$r_bad" "$r_late" $'```\n'"$r_good"$'\n```'; r_run; r_status indeterminate; r_has near-miss
r_base; r_rows issue-comments "$r_early" '<!-- model-record: stage=Test model="m" -->' "$r_late" '<!-- model-record: stage=Review-draft model="m" -->'; r_run; r_status indeterminate; r_has '?'
# A positive unexpected-call control proves the recorder can actually fire.
PATH="$SANDBOX/bin:$PATH" gh api unexpected >/dev/null 2>&1
[ -s "$ROLE_V2_UNEXPECTED" ] || fail 'unmatched-call witness unreachable'
test_done
