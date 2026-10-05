#!/usr/bin/env bash
# S218 — the self-check lines, the stated limit and the override pointer to #415.
# Covers: F42
#
# Issue #410, AC5 and AC6 (Architect A28; maintainer defaults 3 and 4, #408;
# the override record and risk note are #415's, A29). Seam: ORCHESTRATOR.md's
# text. The self-check lines must sit in the "Before asking for a merge"
# block (its paragraph plus the list right after it), where #414 put the
# first line. The override text points at #415 and must not define a format
# of its own.
#
# Mutations that turn this red (tag in the message):
#  self-check-design  delete the "no design-class finding was fixed without an Architect step" line, or move it out of the block
#  self-check-trigger delete the "trigger did not fire, or its step is on the PR" line
#  self-check-script  drop review-rounds.sh from the block
#  limit              delete the limit sentence, or say a script CAN verify the class
#  override           reverse "pushback" and "risk note" away, or drop "numbered human decision" or the rule it names
#  cwd        say 'run in the guardrails clone' or drop the working-directory sentence for review-rounds.sh
#  override-dir  "Architect pushes back once" -> "Architect never pushes back"; "before the fix commit" -> "after the fix commit"
#  pointer            drop "#415" and "A29" from the override text
#  no-own-format      add a risk-note "fields:" list or a loop-back marker to ORCHESTRATOR.md

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/loopback-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/loopback-helpers.sh"

lb_files
[ -f "$LB_ORCH" ] || { fail "S218 — ORCHESTRATOR.md does not exist"; test_done; }
blk='before asking for a merge'

# Where the script runs (round 1 finding orch-review-rounds-wrong-repo-cwd): it
# reads the repository of its working directory, so the text must say the
# working directory is the PROJECT's checkout, not the guardrails clone.
lb_sentence_has_all "$LB_ORCH" 'review-rounds\.sh' 'working directory' "(project.s|the project|your project)[^.]*checkout" \
  || fail "S218/cwd — ORCHESTRATOR.md does not say review-rounds.sh runs with the project's checkout as the working directory"
if lb_sentence_has_all "$LB_ORCH" 'review-rounds\.sh' 'guardrails clone' && ! lb_sentence_has_all "$LB_ORCH" 'review-rounds\.sh' 'working directory'; then
  fail "S218/cwd — ORCHESTRATOR.md names the guardrails clone for review-rounds.sh without saying the working directory is the project's checkout"
fi

lb_block_has_all "$LB_ORCH" "$blk" 'no design[- ]class finding' '(fixed|fix)[^.]*without an? Architect step before' \
  || fail "S218/self-check-design — the 'Before asking for a merge' block has no line saying no design-class finding was fixed without an Architect step"
lb_block_has_all "$LB_ORCH" "$blk" '(two-round|two consecutive)' 'did not fire' '(Architect|redesign)[^.]*(on the PR|recorded)' \
  || fail "S218/self-check-trigger — the 'Before asking for a merge' block has no line saying the two-round trigger did not fire or its Architect step is on the PR"
lb_block_has_all "$LB_ORCH" "$blk" 'review-rounds\.sh' \
  || fail "S218/self-check-script — the 'Before asking for a merge' block does not name review-rounds.sh"

# The stated limit: class and severity are judgments; a script can only check
# that the route left evidence.
lb_sentence_has_all "$LB_ORCH" '(class|severity)[^.]*(judg(e)?ment)' \
  || fail "S218/limit — ORCHESTRATOR.md does not say class and severity are judgments"
lb_sentence_has_all "$LB_ORCH" '(script|check)[^.]*(only|can only)[^.]*(route|evidence)|(no|not)[^.]*script[^.]*(verify|check)[^.]*(class|classification)' \
  || fail "S218/limit — ORCHESTRATOR.md does not say a script can only check that the route left evidence, never the classification"

# The override (AC6): the maintainer tells the orchestrator to patch a design
# defect in code; that is a recorded human decision, with the pushback and risk
# note of #415, not a format of its own.
ov='(maintainer|human)[^.]*(override|waive|patch|instead of)|(override|waive)[^.]*(loop-back|route|rule)'
lb_any_has_all "$LB_ORCH" "$ov" 'Architect (pushes|push) back (once|first)' 'Architect writes (the|a) risk note' \
  || fail "S218/override — no unit of ORCHESTRATOR.md says an override of the loop-back route follows the pushback and the risk note"
lb_any_has_all "$LB_ORCH" "$ov" 'numbered' 'human decision' '(names?|naming)[^.]*(rule|route)' \
  || fail "S218/override — ORCHESTRATOR.md does not say an override is a numbered human decision that names the rule overridden"
lb_any_has_all "$LB_ORCH" "$ov" '(#415|A29)' '(defined|owned|described|set|see|follows?)[^.]*(#415|A29)|(#415|A29)[^.]*(defines?|owns?)' \
  || fail "S218/pointer — the override text does not point at #415 (A29) for the pushback and risk note"

# No format of its own: no field list for the risk note, no new marker.
if lb_unit_has_all "$LB_ORCH" 'risk note' '(fields?|sections?|template|headings?)[^.]*:' ; then
  fail "S218/no-own-format — ORCHESTRATOR.md defines a risk-note field list; the format is #415's"
fi
if grep -qiE 'loop-?back[^<]*<!--|<!--[^>]*(loop-?back|design-override)' "$LB_ORCH"; then
  fail "S218/no-own-format — ORCHESTRATOR.md introduces a marker for a loop-back override; this item adds no new marker"
fi

test_done
