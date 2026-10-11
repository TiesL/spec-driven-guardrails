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
r_base; r_rows issue-comments "$r_early" '<!-- model-record: stage=Test model="m" -->' "$r_late" '<!-- model-record: stage=Review-draft model="m" -->'; r_run; r_status indeterminate; r_has 'stage=Review'
# All adjacent equal-time source ties choose the later source, both directions.
for latest in bad good; do
 if [ "$latest" = bad ]; then a="$r_good"; b="$r_bad"; else a="$r_bad"; b="$r_good"; fi
 for pair in issue-description description-comments; do
  r_base; r_link
  case "$pair" in
   issue-description) r_issue role:architect "$a" "$r_early"; r_pr "$b" "$r_early";;
   description-comments) r_pr "$a" "$r_early"; r_rows comments "$r_early" "$b";;
  esac
  r_run; if [ "$latest" = bad ]; then r_status indeterminate; else r_status stale; fi
 done
 # A newer quoted candidate does not replace older valid evidence either.
 r_base; r_rows issue-comments "$r_early" "$r_good" "$r_late" $'```\n'"$r_bad"$'\n```'; r_run; r_status stale
 # Unknown stage is not hidden by an older Review or a lower-stage Test.
 r_base; r_rows issue-comments "$r_early" "$r_good" "$r_early" '<!-- model-record: stage=Test model="m" -->' "$r_late" '<!-- model-record: stage=Unknown model="m" -->'; r_run; r_status indeterminate; r_has '?'
done
# Two linked PRs in either timeline retrieval order, timestamp precedence
# deliberately opposes numeric PR collection order; both latest directions.
for latest in bad good; do
 for order in '501 502' '502 501'; do
  r_base
  jq -n '$ARGS.positional | map({event:"cross-referenced",source:{issue:{number:tonumber,repository:{full_name:"owner/repo"},pull_request:{}}}})' --args $order > "$ROLE_V2_DATA/timeline.json"
  r_pr ''; cp "$ROLE_V2_DATA/pr.json" "$ROLE_V2_DATA/pr2.json"
  if [ "$latest" = bad ]; then ta="$r_late"; tb="$r_early"; else ta="$r_early"; tb="$r_late"; fi
  r_rows reviews "$ta" "$r_bad"; r_rows reviews2 "$tb" "$r_good"
  r_run; if [ "$latest" = bad ]; then r_status indeterminate; else r_status stale; fi
  for endpoint in pulls/501/reviews pulls/502/reviews; do grep -F "$endpoint " "$ROLE_V2_LOG" >/dev/null || fail "not reached: $endpoint"; done
 done
done
# A positive unexpected-call control proves the recorder can actually fire.
PATH="$SANDBOX/bin:$PATH" gh api unexpected >/dev/null 2>&1
[ -s "$ROLE_V2_UNEXPECTED" ] || fail 'unmatched-call witness unreachable'
test_done
