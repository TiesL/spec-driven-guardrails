#!/usr/bin/env bash
# S259 — gate_latest_candidate; #427, independent CLI assertions (A31a/A34a/A37).
# Covers: F27, F38, F39, F40
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
. "$TEST_REPO_ROOT/test/fixtures/gate-v2-helpers.sh"

good='<!-- model-record: stage=Review model="m" -->'
bad='<!-- model-record: stage=Review model=m -->'
for reverse in 0 1; do
 v2_base
 if [ "$reverse" = 0 ]; then
 v2_times reviews-246.json "$early" "$good"; v2_times comments-246.json "$late" "$bad" "${early}" "$(mr Planning)" "$early" "$(mr Test)" "$early" "$(mr Implementation)"
 else
 v2_times comments-246.json "$early" "$good" "$early" "$(mr Planning)" "$early" "$(mr Test)" "$early" "$(mr Implementation)"; v2_times reviews-246.json "$late" "$bad"
 fi
 v2_run; has 'the latest stage=Review record is unreadable, so no earlier record is used'; absent 'has no floor-basis'; absent 'no record found for stage Review'; count 'near-miss' 1
done
for stage in Discovery Planning Test Implementation Review; do
 v2_base; v2_times comments-246.json "$late" "<!-- model-record: stage=$stage model=m -->" "$early" "$(mr "$stage")"; v2_run
 has "the latest stage=$stage record is unreadable"; absent "no record found for stage $stage"
done
# Chronology reversed: older near-miss cannot mask latest basis finding.
v2_base; v2_times reviews-246.json "$late" "$good" "$early" "$bad"; v2_run
count 'has no floor-basis' 1; absent 'latest stage=Review record is unreadable'; count 'near-miss' 1
# Description creation, never its newer updated_at.
v2_base; v2_pr 'Fix #239' "$(mr Review)" "$early"; v2_times reviews-246.json "$late" "$good"; v2_run; count 'has no floor-basis' 1
v2_pr 'Fix #239' "$(mr Review)" "$late"; v2_times reviews-246.json "$early" "$good"; v2_run; absent 'has no floor-basis'
# Adjacent source ties: issue < description < comments < reviews.
for pair in issue-description description-comments comments-reviews; do
 v2_base; v2_comments reviews-246.json
 case "$pair" in
 issue-description) v2_times comments-239.json "$late" "$good"; v2_pr 'Fix #239' "$(mr Review)" "$late";;
 description-comments) v2_pr '' "$good" "$late"; v2_times comments-246.json "$late" "$(mr Review)";;
 comments-reviews) v2_times comments-246.json "$late" "$good"; v2_times reviews-246.json "$late" "$(mr Review)";; esac
 # Record actual endpoint calls without substituting the response adapter.
 tracebin="$SANDBOX/traced-gh"; mkdir -p "$tracebin"
 export V2_GH_TRACE="$SANDBOX/gh-trace"
 cat > "$tracebin/gh" <<GHEOF
#!/bin/bash
printf '%s\\n' "\$*" >> "\$V2_GH_TRACE"
exec "$v2_bin/gh" "\$@"
GHEOF
 chmod +x "$tracebin/gh"
 : > "$V2_GH_TRACE"
 v2_path="$tracebin:$PATH"
 v2_run; absent 'has no floor-basis'
 if [ "$pair" = issue-description ]; then
   assert_contains 'S259 — competing issue source was fetched' 'repos/{owner}/{repo}/issues/239/comments' "$(cat "$V2_GH_TRACE")"
 fi
 unset v2_path
done
v2_base; v2_times reviews-246.json "$late" "$(mr Review)"$'\n'"$good"; v2_run; count 'has no floor-basis' 1
v2_times reviews-246.json "$late" "$good"$'\n'"$(mr Review)"; v2_run; absent 'has no floor-basis'

test_done
