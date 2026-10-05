#!/usr/bin/env bash
# S215 — two consecutive rounds with a medium-or-worse finding force an Architect step; the count resets.
# Covers: F42
#
# Issue #410, AC3 (Architect A28). Seam: ORCHESTRATOR.md's text. Each
# check is one directional sentence ("before", "after", "never" in the right
# place), so the inverted rule goes red.
#
# Mutations that turn this red (tag in the message):
#  trigger     change "before any Developer fix" to "after"; or drop "consecutive"; or drop "one PR"
#  counts      change "medium or high" to "low or medium"; drop "new or carried over"
#  architect   delete the sentence that the Architect posts a PR comment with a Planning marker
#  may-conclude delete "may conclude no design change is needed"
#  reset       change "starts again after that recorded step" to "never starts again", or "before"

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/loopback-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/loopback-helpers.sh"

lb_files
[ -f "$LB_ORCH" ] || { fail "S215 — ORCHESTRATOR.md does not exist"; test_done; }

# The trigger: two consecutive rounds on one PR -> Architect BEFORE any Developer fix.
lb_sentence_has_all "$LB_ORCH" 'two consecutive[^.]*round' '(one|a|the same|each) PR|per PR|on the PR' \
  '(dispatch|goes? (back )?to|send)[^.]*Architect[^.]*before[^.]*(Developer|fix)|before[^.]*(Developer|any fix)[^.]*(dispatch|Architect)' \
  || fail "S215/trigger — ORCHESTRATOR.md has no sentence saying two consecutive rounds on one PR send the orchestrator to the Architect before any Developer fix"

# What counts as a round: an open finding of medium or high, new or carried over.
lb_sentence_has_all "$LB_ORCH" 'round' 'count' 'at least one' 'open' 'medium or (high|worse|higher)' 'new or carried' \
  || fail "S215/counts — ORCHESTRATOR.md does not say a round counts when it reports at least one open finding of medium or high severity, new or carried over"

# The Architect step is recorded: a PR comment with a Planning marker; it may
# conclude that no design change is needed.
lb_sentence_has_all "$LB_ORCH" 'Architect' 'comment' 'Planning marker' '\bPR\b' \
  || fail "S215/architect — ORCHESTRATOR.md does not say the Architect posts a PR comment with a Planning marker"
lb_sentence_has_all "$LB_ORCH" 'Architect' '(may|can|is free to)[^.]*conclude' 'no design change' \
  || fail "S215/may-conclude — ORCHESTRATOR.md does not say the Architect may conclude that no design change is needed"

# The reset: the count starts again AFTER the recorded step (without it the
# next round would fire the trigger again).
lb_sentence_has_all "$LB_ORCH" 'count' '(starts? again|resets?|restarts?|begins again)[^.]*after[^.]*(recorded|Architect|redesign)' \
  || fail "S215/reset — ORCHESTRATOR.md does not say the count starts again after the recorded Architect step"

test_done
