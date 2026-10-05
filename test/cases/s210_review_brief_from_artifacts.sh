#!/usr/bin/env bash
# S210 — a later round's brief is built from artifacts; carried-forward findings are inputs, not memory.
# Covers: F41
#
# Issue #414, AC3 and AC4 (Architect A27). Seam: ORCHESTRATOR.md's brief
# paragraph and pre-merge-review's "What happens with it" section.
#
# Mutations that turn this red: remove the head SHA, the issue or the
# previous findings from the brief's input list; delete the "never the
# earlier Reviewer's conversation" clause; delete the "inputs, not memory"
# sentence from pre-merge-review; reword it so that the Reviewer is told to
# rely on remembered findings. AC4's "gate script and its test unchanged"
# is not asserted here: the existing finding-carryforward tests stay in the
# suite and run unchanged (AC6).

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/review-floor-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/review-floor-helpers.sh"
# shellcheck source=../fixtures/fresh-reviewer-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/fresh-reviewer-helpers.sh"

fr_files

# AC3: one paragraph is the brief: Review round, head SHA, diff, issue, the
# previous round's findings (by link or slug), the carry-forward gate.
para_has_all "$FR_ORCH" 'review round' 'brief' 'head SHA' 'diff' '\bissue\b' \
  '(previous|earlier|prior|last) round' 'findings' '(link|slug)' \
  || fail "S210/AC3 — no ORCHESTRATOR.md paragraph briefs a Review round with head SHA, diff, issue and the previous round's findings (link or slug)"
para_has_all "$FR_ORCH" 'review round' 'brief' 'finding-carryforward-gate' \
  || fail "S210/AC3 — the Review round brief does not name finding-carryforward-gate.sh"

# AC3: the exclusion, in one sentence: the brief never carries the earlier
# Reviewer's conversation / recollection / a summary of it.
sentence_has_all "$FR_ORCH" 'brief' '(never|not|no)' 'reviewer' \
  '(conversation|recollection|memory|summary)' \
  || fail "S210/AC3 — ORCHESTRATOR.md does not say the brief never includes or relies on the earlier Reviewer's conversation or recollection"

# AC4: pre-merge-review says carried-forward findings are inputs re-checked
# against the new head, not memory; checked inside the carry-forward section.
sec="$(section_of "$FR_PMR" '^## What happens with it')"
[ -n "$sec" ] || fail "S210/AC4 — pre-merge-review has no '## What happens with it' section"
tmp="$(mktemp)"
printf '%s\n' "$sec" > "$tmp"
sentence_has_all "$tmp" 'finding' 'input' '(not|never|rather than|instead of)[^.]*memory' \
  || fail "S210/AC4 — the carry-forward text of pre-merge-review does not say the previous round's findings are inputs, not memory"
sentence_has_all "$tmp" 'finding|slug' '(re-?check|re-?verif|re-?examin|check again|verif)' \
  '(new|current|latest) head' \
  || fail "S210/AC4 — the carry-forward text does not say the new Reviewer re-checks each previous finding against the new head"
rm -f "$tmp"

test_done
