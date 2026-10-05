#!/usr/bin/env bash
# S212 — in pre-merge-review a bare "fork" means only `context: fork`.
# Covers: F41
#
# Issue #414, Architect A27 and round 1 finding 7. After the rule, "fork" in
# this skill must not read as the dispatch tool's banned fork type. Seam: the
# skill text with the two legitimate uses (`context: fork`, "the dispatch
# tool's `fork` type") removed must contain no "fork"; and the single-Reviewer
# and lens-Adapter runs are named as runs.
#
# Mutation that turns this red: reintroduce "single-Reviewer fork",
# "fork Reviewer as usual" or "lens-Adapter forks".

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/review-floor-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/review-floor-helpers.sh"
# shellcheck source=../fixtures/fresh-reviewer-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/fresh-reviewer-helpers.sh"

fr_files
flat="$(tr '\n' ' ' < "$FR_PMR" | sed -E "s/context: *\`?fork\`?//g; s/tool.s \`?fork\`?//g")"
left="$(grep -oiE '.{25}\bfork[a-z]*.{15}' <<<"$flat" | head -5)"
[ -z "$left" ] || fail "S212/AC1 — pre-merge-review uses 'fork' for something other than context: fork or the dispatch tool's fork type: $left"
grep -qiE 'single isolated Reviewer run' <<<"$flat" \
  || fail "S212/AC1 — pre-merge-review does not call the single-Reviewer review a 'single isolated Reviewer run'"
grep -qiE 'run the Reviewer as usual' <<<"$flat" \
  || fail "S212/AC1 — pre-merge-review thorough mode does not say 'run the Reviewer as usual'"
grep -qiE 'lens-Adapter runs' <<<"$flat" \
  || fail "S212/AC1 — pre-merge-review thorough mode does not say 'lens-Adapter runs'"

test_done
