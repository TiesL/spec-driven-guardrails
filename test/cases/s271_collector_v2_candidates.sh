#!/usr/bin/env bash
# S271 — presence and latest candidates.
# Covers: F27, F34, F39, F40
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
. "$TEST_REPO_ROOT/test/fixtures/collector-v2-helpers.sh"

cv_base; cv_run; cv_status 1 evidenced; cv_status 2 evidenced; cv_has 2 'model alone'
for q in '`<!-- model-record: stage=Planning model="m" -->`' $'```\n<!-- model-record: stage=Planning model="m" -->\n```' $'~~~\n<!-- model-record: stage=Planning model="m" -->\n~~~' '> <!-- model-record: stage=Planning model="m" -->' '    <!-- model-record: stage=Planning model="m" -->' $'\t<!-- model-record: stage=Planning model="m" -->'; do
 cv_base; cv_pr "$(cv_mark Discovery)
$(cv_mark Test)
$(cv_mark Implementation)
$q"; cv_run; cv_status 1 not-evidenced; cv_has 1 'but only inside a code span, fenced block or blockquote, so it was read as quoted illustration and not counted as live evidence'
done
for bad in 'Done. <!-- model-record: stage=Planning model="m" -->' ' <!-- model-record: stage=Planning model="m" -->' '| <!-- model-record: stage=Planning model="m" --> |' '<!-- model-record: stage=Planning model="m" --> trailing' '<!-- model-record: stage=Planning model=m -->'; do
 cv_base; cv_pr "$(cv_mark Discovery)
$(cv_mark Test)
$(cv_mark Implementation)
$bad"; cv_run; cv_status 1 indeterminate; cv_has 1 stage=Planning; cv_has 1 near-miss; cv_absent 1 'only inside'
 case "$bad" in *trailing) cv_has 1 'text after the closing --> or no closing -->';; *model=m*) cv_has 1 'no quoted, non-blank model';; *) cv_has 1 'not on a line of its own';; esac
done
cv_base; cv_pr "$(cv_mark Discovery)
$(cv_mark Test)
$(cv_mark Implementation)
model-record: stage=Planning model=m"; cv_run; cv_status 1 not-evidenced; cv_absent 1 'only inside'
bad='<!-- model-record: stage=Review -->'
for order in forward reverse; do
 cv_base
 if [ "$order" = forward ]; then cv_rows comments "$cv_early" "$(cv_mark Review)" "$cv_late" "$bad"; else cv_rows comments "$cv_late" "$bad" "$cv_early" "$(cv_mark Review)"; fi
 cv_run; cv_status 2 indeterminate; cv_has 2 stage=Review; cv_has 2 'no quoted, non-blank model'
 cv_base; cv_rows comments "$cv_late" "$(cv_mark Review)" "$cv_early" "$bad"; cv_run; cv_status 2 evidenced
 cv_base; cv_rows comments "$cv_late" "$(cv_mark Review claude-opus-5)" "$cv_early" "$(cv_mark Review)"; cv_run; cv_status 2 unverifiable-from-artifacts; cv_has 2 claude-opus-5; cv_has 2 claude-sonnet-5; cv_has 2 "their capability ordering isn't machine-checked"
done
cv_base; cv_rows comments "$cv_early" "$(cv_mark Review)" "$cv_late" "\`$(cv_mark Review claude-opus-5)\`"; cv_run; cv_status 2 evidenced
# New comment must beat an older review despite endpoint append order.
cv_base; cv_rows comments "$cv_late" "$bad"; cv_rows reviews "$cv_early" "$(cv_mark Review)"; cv_run; cv_status 2 indeterminate
# Equal source timestamps: reviews beat comments, later lines beat earlier.
for payload in "$(cv_mark Review)
$bad" "$bad
$(cv_mark Review)"; do
 cv_base; cv_rows comments "$cv_early" "$bad"; cv_rows reviews "$cv_early" "$payload"; cv_run
 case "$payload" in *'model="claude-sonnet-5" -->') cv_status 2 evidenced;; *) cv_status 2 indeterminate;; esac
done
# Description creation date wins over its edited date; issue precedes description in ties.
cv_base; cv_pr "$(cv_mark Discovery)
$(cv_mark Planning)
$(cv_mark Test)
$(cv_mark Implementation)
$bad" 'Closes #265'; cv_rows issue265 "$cv_early" "$(cv_mark Review)"; cv_rows comments "$cv_late" "$(cv_mark Review)"; cv_run; cv_status 2 evidenced
cv_base; cv_pr "$(cv_mark Discovery)
$(cv_mark Planning)
$(cv_mark Test)
$(cv_mark Implementation)
$bad" 'Closes #265'; cv_rows issue265 "$cv_early" "$(cv_mark Review)"; cv_rows comments; cv_run; cv_status 2 indeterminate
# The next invocation cannot inherit cache from a previous PR.
cv_base; cv_run; cv_status 2 evidenced; cv_base; cv_rows comments "$cv_late" "$bad"; cv_run 280; cv_status 2 indeterminate
# Witness self-control: unmatched endpoint is recorded (without accepting CLI failure).
PATH="$SANDBOX/bin:$PATH" gh api unexpected --jq . >/dev/null 2>&1
[ -s "$CV_UNEXPECTED" ] || fail 'unmatched-call witness did not fire'
test_done
