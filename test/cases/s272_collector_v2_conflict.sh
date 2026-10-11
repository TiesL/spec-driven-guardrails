#!/usr/bin/env bash
# S272 — normalized inter-issue conflicts.
# Covers: F27, F34, F39, F40
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
. "$TEST_REPO_ROOT/test/fixtures/collector-v2-helpers.sh"

for title in 'Closes #265, closes #266' 'Closes #266, closes #265'; do
 cv_base; cv_pr "$(cv_mark Implementation)" "$title"; cv_rows comments "$cv_late" "$(cv_mark Review)"; cv_rows issue265 "$cv_early" "$(cv_mark Review)"; cv_rows issue266 "$cv_late" "$(cv_mark Review claude-opus-5)"; cv_run; cv_status 2 indeterminate
 for want in conflicting 'issue #265' 'issue #266' claude-sonnet-5 claude-opus-5; do cv_has 2 "$want"; done
 cv_base; cv_pr "$(cv_mark Implementation)" "$title"; cv_rows comments; cv_rows issue265 "$cv_early" '<!-- model-record: stage=Review model="Claude Sonnet 5" effort="low" -->'; cv_rows issue266 "$cv_late" '<!-- model-record: stage=Review model="claude-sonnet-5-20260101" effort="high" -->'; cv_run; cv_status 2 evidenced; cv_has 2 'model alone'; cv_absent 2 conflicting
 cv_base; cv_pr "$(cv_mark Implementation)" "$title"; cv_rows comments; cv_rows issue265 "$cv_early" "$(cv_mark Review sonnet)"; cv_rows issue266 "$cv_late" "$(cv_mark Review)"; cv_run; cv_status 2 indeterminate; cv_has 2 conflicting
done
mkdir -p "$SANDBOX/missing"; cp "$TEST_REPO_ROOT/compliance-evidence.sh" "$SANDBOX/missing/"
PATH="$SANDBOX/bin:$PATH" /bin/bash "$SANDBOX/missing/compliance-evidence.sh" 279 > "$SANDBOX/stdout" 2> "$SANDBOX/stderr"; rc=$?
[ "$rc" = 3 ] && [ ! -s "$SANDBOX/stdout" ] || fail 'missing-lib contract'
test_source_match -F lib/model-record.sh "$SANDBOX/stderr" >/dev/null || fail 'missing-lib diagnostic'
test_done
