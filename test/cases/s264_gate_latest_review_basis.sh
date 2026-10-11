#!/usr/bin/env bash
# S264 — gate_latest_review_basis; #427, independent CLI assertions (A31a/A34a/A37).
# Covers: F27, F38, F39, F40
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
. "$TEST_REPO_ROOT/test/fixtures/gate-v2-helpers.sh"

for basis in '' ' floor-basis=""' ' floor-basis="   "' ' same-model-exception="legacy"'; do
 for impl in present absent; do
  v2_base
  [ "$impl" = present ] || v2_comments comments-246.json "$(mr Planning)" "$(mr Test)"
  v2_times reviews-246.json "$late" "<!-- model-record: stage=Review model=\"m\"$basis -->" "$early" "$(mr Review)"; v2_run
  count 'has no floor-basis' 1
 done
done
# Regression model-only floor, literal shell-looking data is harmless.
for effort in 'effort="low"' '' 'effort=""' 'effort="odd"'; do
 for model in sonnet opus; do
  v2_base; v2_comments reviews-246.json "<!-- model-record: stage=Review model=\"$model\" $effort floor-basis=\"same model -- \`code\` \$(touch /never-run) model=\" -->"; v2_run; clean
 done
done

test_done
