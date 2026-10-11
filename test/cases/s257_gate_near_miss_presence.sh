#!/usr/bin/env bash
# S257 — gate_near_miss_presence; #427, independent CLI assertions (A31a/A34a/A37).
# Covers: F27, F38, F39, F40
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
. "$TEST_REPO_ROOT/test/fixtures/gate-v2-helpers.sh"

v2_base
v2_comments comments-246.json '<!-- model-record: stage="Planning" model="m" -->' "$(mr Test)" "$(mr Implementation)"
v2_run
has 'no record found for stage Planning'; count 'near-miss' 1; has 'stage="Planning"'
for stage in Discovery Planning Test Implementation Review; do
 for shape in bare empty missing effort inline suffix indent1 indent2 indent3 odd unclosed nested split lt gt; do
  good="$(mr "$stage")"
  case "$shape" in
   bare) bad="<!-- model-record: stage=$stage model=m -->";;
   empty) bad="<!-- model-record: stage=$stage model=\"\" -->";;
   missing) bad="<!-- model-record: stage=$stage -->";;
   effort) bad="<!-- model-record: stage=$stage model=\"m\" effort=low -->";;
   inline) bad="Done. $good";; suffix) bad="$good Done.";;
   indent1) bad=" $good";; indent2) bad="  $good";; indent3) bad="   $good";;
   odd) bad="<!-- model-record: stage=$stage model=\"m\" note=\"a\"b\" -->";;
   unclosed) bad="<!-- model-record: stage=$stage model=\"m\"";;
   nested) bad="<!-- model-record: stage=$stage model=\"m\" $good";;
   split) bad="<!-- model-record: stage=$stage"$'\n'' model="m" -->';;
   lt) bad="<!-- model-record: stage=$stage model=\"m\" note=\"a < b\" -->";;
   gt) bad="<!-- model-record: stage=$stage model=\"m\" note=\"a > b\" -->";;
  esac
  v2_base; v2_comments comments-239.json; v2_comments reviews-246.json
  v2_comments comments-246.json "$bad"; v2_run
  has "no record found for stage $stage"; count 'near-miss' 1
  v2_comments comments-246.json "$bad" "$good"; v2_run
  absent "no record found for stage $stage"; count 'near-miss' 1
 done
done
v2_base; v2_comments comments-246.json '<!-- model-record: stage=Unknown model="m" -->' 'Planning <!-- model-record no colon' "$(mr Planning)" "$(mr Test)" "$(mr Implementation)"; v2_run
count 'near-miss' 1; has 'stage=?'

test_done
