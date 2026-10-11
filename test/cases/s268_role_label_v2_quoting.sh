#!/usr/bin/env bash
# S268 — quoted records versus whole-line near-misses.
# Covers: F35
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
. "$TEST_REPO_ROOT/test/fixtures/role-label-v2-helpers.sh"
test_rec='<!-- model-record: stage=Test model="claude-sonnet-5" -->'
for source in issue review; do
 for quote in live backtick tilde inline block four tab; do
  case "$quote" in live) body="$test_rec";; backtick) body=$'```\n'"$test_rec"$'\n```';; tilde) body=$'~~~\n'"$test_rec"$'\n~~~';; inline) body="\`$test_rec\`";; block) body="> $test_rec";; four) body="    $test_rec";; tab) body=$'\t'"$test_rec";; esac
  r_base; r_issue role:product
  if [ "$source" = issue ]; then r_rows issue-comments "$r_early" "$body"; else r_link; r_rows reviews "$r_early" "$body"; fi
  r_run
  if [ "$quote" = live ]; then r_status stale; r_has 'expected role:qa'; else r_status in-sync; r_has 'no model-record marker evidenced yet'; r_absent stage=Test; r_absent near-miss; fi
  [ "$source" != review ] || grep -F 'pulls/501/reviews ' "$ROLE_V2_LOG" >/dev/null || fail 'review endpoint not reached'
 done
done
for body in "prose $test_rec" "$test_rec prose" "| $test_rec |" " $test_rec" "  $test_rec" "   $test_rec"; do
 r_base; r_issue role:product; r_rows issue-comments "$r_early" "$body"; r_run; r_status indeterminate; r_has 'not on a line of its own'
done
r_base; r_issue role:product; r_rows issue-comments "$r_early" $'```\n'"$test_rec" "$r_late" "$test_rec"; r_run; r_status stale; r_has 'expected role:qa'
test_done
