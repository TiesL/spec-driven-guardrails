#!/usr/bin/env bash
# S262 — gate_strict_override; #427, independent CLI assertions (A31a/A34a/A37).
# Covers: F27, F38, F39, F40
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
. "$TEST_REPO_ROOT/test/fixtures/gate-v2-helpers.sh"

override='<!-- pipeline-override: decided-by="human" scope="single-session" reason="approved exception" -->'
for shape in gt lt empty missing scope control inline fence span block; do
 case "$shape" in
 gt) o="${override/approved exception/a > b}";; lt) o="${override/approved exception/a < b}";;
 empty) o="${override/decided-by=\"human\"/decided-by=\"\"}";; missing) o="${override/ reason=\"approved exception\"/}";;
 scope) o="${override/single-session/anything}";; control) o="${override/approved exception/$'a\tb'}";;
 inline) o="Done. $override";; fence) o=$'```\n'"$override"$'\n```';; span) o="\`$override\`";; block) o="> $override";; esac
 v2_base; v2_comments comments-246.json "$(mr Test)" "$(mr Implementation)" "$o"; v2_run "$v2_yes"
 has 'role-played: stages missing: Planning'
 case "$shape" in fence|span|block) absent 'near-miss';; *) count 'override near-miss' 1;; esac
done
for source in issue description comment review; do
 v2_base; v2_comments comments-246.json "$(mr Test)" "$(mr Implementation)"
 case "$source" in
 issue) v2_comments comments-239.json "$(mr Discovery)" "$override";; description) v2_pr 'Fix #239' "$override";;
 comment) v2_comments comments-246.json "$(mr Test)" "$(mr Implementation)" "$override";;
 review) v2_comments reviews-246.json "$(mr Review)" "$override";; esac
 v2_run "$v2_yes"; absent 'role-played:'; has 'override'; has 'no record found for stage Planning'
done
for stage in Discovery Planning Test Implementation Review; do
 v2_base; v2_comments comments-239.json; v2_comments reviews-246.json
 bodies=(); for s in Discovery Planning Test Implementation Review; do [ "$s" = "$stage" ] || bodies+=("$(mr "$s")"); done
 bodies+=("${override/single-session/skip=$stage}")
 v2_comments comments-246.json "${bodies[@]}"; v2_run "$v2_yes"; absent 'role-played:'; has "no record found for stage $stage"
done
v2_base; v2_comments comments-246.json "$(mr Implementation)" "${override/single-session/skip=Planning}"; v2_run "$v2_yes"; has 'role-played: stages missing: Test'
v2_comments comments-246.json "$(mr Implementation)"$'\n'"$(mr Test)" "${override/single-session/skip=Planning}"; v2_run "$v2_yes"; has 'role-played: stages in one text: Test, Implementation'

test_done
