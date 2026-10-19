#!/usr/bin/env bash
# S211 — the limit on proving a fresh agent is stated; pipeline log and self-check are the fallback.
# Covers: F41
#
# Issue #414, AC5 case (b) (Architect A27); amended by #499 AC14 (A41): the
# Pipeline log and the pre-merge self-check rules are located by ID. OR22
# (Pipeline log) and OR23 (self-check before asking for a merge) each start
# exactly one item in part 2 with tier judgment; OR22's item carries no live
# `<!-- model-record` text (absence check); OR24-OR27 are sub-items of OR23
# (S218). The behaviour (one log line per dispatch, the self-check before
# the merge question, the stated limit that GitHub cannot prove distinct
# agent instances) moved to OB26 and OB27; the limit's wording is no longer
# asserted.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/orchestrator-core-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/orchestrator-core-helpers.sh"

oc_rule "S211/OR22 Pipeline log" OR22 judgment 2 0
oc_rule "S211/OR23 self-check before asking for a merge" OR23 judgment 2 0
if test_source_match -qF '<!-- model-record' <<<"$(oc_item OR22)"; then
  fail "S211/OR22 — the Pipeline log item carries live <!-- model-record text"
fi
for id in OR24 OR25 OR26 OR27; do
  oc_rule "S211/$id sub-item of OR23" "$id" core 2 1
done
# Sub-items follow OR23 directly, in order.
order="$(python3 -I "$OC_PY" items --orch "$OC_ORCH" | cut -f1 | tr '\n' ' ')"
case "$order" in
  *"OR23 OR24 OR25 OR26 OR27 "*) ;;
  *) fail "S211 — OR24-OR27 do not directly follow OR23 as its sub-items" ;;
esac

test_done
