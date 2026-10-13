#!/usr/bin/env bash
# S258 — gate_quoted_evidence; #427, independent CLI assertions (A31a/A34a/A37).
# Covers: F27, F38, F39, F40
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
. "$TEST_REPO_ROOT/test/fixtures/gate-v2-helpers.sh"

five="$(mr Discovery)"$'\n'"$(mr Planning)"$'\n'"$(mr Test)"$'\n'"$(mr Implementation)"$'\n'"$(mr Review)"
for form in fence tilde span block indent; do
 case "$form" in
 fence) q=$'```\n'"$five"$'\n```';; tilde) q=$'~~~\n'"$five"$'\n~~~';;
 span) q="$(sed 's/^/`/; s/$/`/' <<<"$five")";; block) q="$(sed 's/^/> /' <<<"$five")";; indent) q="$(sed 's/^/    /' <<<"$five")";; esac
 v2_base; v2_comments comments-239.json; v2_comments reviews-246.json; v2_comments comments-246.json "$q"
 v2_run "$v2_yes"; has "$missing"; absent 'stages in one text'; absent 'near-miss'
 v2_run; absent 'role-played:'
 # Quoted newest Review cannot supply basis or mask live Review.
 v2_base; v2_times reviews-246.json "$early" '<!-- model-record: stage=Review model="m" -->' "$late" "$q"; v2_run
 count 'has no floor-basis' 1
 done
# Regression controls: separate stages, same stage repeated, distinct stages.
v2_base; v2_run "$v2_yes"; clean
v2_comments comments-246.json "$(mr Planning)"$'\n'"$(mr Planning)" "$(mr Test)" "$(mr Implementation)"; v2_run "$v2_yes"; clean
v2_comments comments-246.json "$(mr Planning)"$'\n'"$(mr Test)" "$(mr Implementation)"; v2_run "$v2_yes"; count 'stages in one text: Planning, Test' 1
v2_base; v2_comments comments-246.json $'```\nunclosed' "$(mr Planning)" "$(mr Test)" "$(mr Implementation)"; v2_run "$v2_yes"; clean
v2_comments comments-246.json $'`example`\n'"$(mr Planning)" "$(mr Test)" "$(mr Implementation)"; v2_run "$v2_yes"; clean

test_done
