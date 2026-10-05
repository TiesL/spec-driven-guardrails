#!/usr/bin/env bash
# S211 — the limit on proving a fresh agent is stated; pipeline log and self-check are the fallback.
# Covers: F41
#
# Issue #414, AC5 case (b) (Architect A27): no GitHub artifact shows two
# rounds came from different agent instances, so no script. The rule text
# must say so, and the fallback must be written: a pipeline log with one
# line per dispatch (agent id), never a model-record marker, and a
# "Before asking for a merge" self-check line.
#
# Mutations that turn this red: soften the self-check to 'optionally note:';
# say 'record it' without naming the Pipeline log; delete the limit sentence, or turn it into
# a claim that the rounds are verified ("checked", "proves"); delete the
# self-check line or its "recorded self-check, not a pass" wording; drop the
# agent id from the log; let the log carry a model-record marker.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/review-floor-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/review-floor-helpers.sh"
# shellcheck source=../fixtures/fresh-reviewer-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/fresh-reviewer-helpers.sh"

fr_files

# Limit: GitHub artifacts cannot show different agent instances.
sentence_has_all "$FR_ORCH" '(cannot|can.t|can not|not possible|no way|unable)' \
  'GitHub' '(different|separate|distinct|same)[^.]*(agent )?instance' \
  || fail "S211/AC5b — ORCHESTRATOR.md does not state that GitHub artifacts cannot show whether two rounds came from different agent instances"
sentence_has_all "$FR_ORCH" '(self-check|check)' '(not a pass|is not proof|proves nothing|not evidence of)' \
  || fail "S211/AC5b — ORCHESTRATOR.md does not say the self-check is a recorded self-check, not a pass"

# Pipeline log: per-dispatch line with the agent id; never a marker.
para_has_all "$FR_ORCH" 'pipeline log' 'agent id' 'dispatch' 'review|round' \
  || fail "S211/AC5b — no ORCHESTRATOR.md paragraph defines a pipeline log with an agent id per dispatch"
para_has_all "$FR_ORCH" 'pipeline log' '(never|not|no)[^.]*model-record' \
  || fail "S211/AC5b — ORCHESTRATOR.md does not say the pipeline log never carries a model-record marker"

# Self-check list: the one line this item owns.
para_has_all "$FR_ORCH" 'before asking for a merge' 'review round' 'agent id' 'SendMessage|message' \
  || fail "S211/AC5b — no ORCHESTRATOR.md 'Before asking for a merge' paragraph with the line: every Review round has its own agent id and no message went to an earlier Reviewer"

# The self-check is mandatory (not 'optionally note') and its result goes in
# one named place: a line in the issue's Pipeline log (decided wording,
# Architect, #414 round 1, finding 6).
para_has_all "$FR_ORCH" 'before asking for a merge' '(run|must|always) (this )?(self-check|check)' \
  || fail "S211/AC5b — the 'Before asking for a merge' self-check is not mandatory in ORCHESTRATOR.md (expected 'run this self-check')"
sentence_has_all "$FR_ORCH" 'self-check' 'record[^.:]*pipeline log' \
  || fail "S211/AC5b — ORCHESTRATOR.md does not say to record the self-check result as a line in the issue's Pipeline log"

test_done
