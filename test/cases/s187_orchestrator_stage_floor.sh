#!/usr/bin/env bash
# S187 — ORCHESTRATOR.md tells the orchestrator to assess each stage's floor
# per model-choice and to set model and effort per stage.
# Covers: F38
#
# Issue #392, R5/AC8 and Architect A24 (the #371 dry-run finding: one model
# and one effort everywhere). What the orchestrating session then actually
# CHOOSES is model behaviour and cannot be asserted here (human dry run on
# the scratch repo); this is the mechanical proxy: the instruction exists as
# one coherent paragraph (so unrelated text cannot satisfy it), names no
# model or tier, carries no different-model rule, and says what to do when
# the dispatch tool exposes no effort setting.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"
# shellcheck source=../fixtures/review-floor-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/review-floor-helpers.sh"

orch="$TEST_REPO_ROOT/skills/role-contracts/ORCHESTRATOR.md"
if [ ! -f "$orch" ]; then
  fail "S187 — skills/role-contracts/ORCHESTRATOR.md does not exist"
  test_done
fi

# 1. One paragraph carries the per-stage floor assessment: it points at
#    model-choice, talks about the stage's floor, effort next to model,
#    "each/per/separately" per stage, and the Review-vs-Implementation rule.
para_has_all "$orch" 'model-choice' 'floor' 'effort' \
  '(each|per|every) stage|stage by stage|separately' \
  'at least as capable' 'Implementation' 'Review' \
  || fail "S187/AC8 — no single paragraph of ORCHESTRATOR.md assesses each stage's floor per model-choice, with model AND effort, and Review at least as capable as Implementation"

# 2. Per stage, not one pair for the whole run (the dry-run finding).
para_has_all "$orch" 'model-choice' \
  '(never|not|instead of|rather than)[^.]*(one|a single|the same) (model|pair|combination|setting|choice)' \
  || fail "S187/AC8 — ORCHESTRATOR.md does not rule out choosing one model/effort pair for every stage"

# 3. Effort the dispatch tool cannot set: said, and with a way out that
#    stays within the floor (a more capable model), in the same paragraph.
para_has_all "$orch" 'effort' \
  "(can.t|cannot|can not|unable|does not (let|allow|expose)|doesn.t (let|allow|expose)|no way to set|not able to set|not settable|isn.t (settable|exposed))" \
  'more capable' 'floor' \
  || fail "S187/AC8 — ORCHESTRATOR.md has no paragraph for an effort the dispatch cannot set (what to do: a more capable model, against the stage's floor)"

# 4. The chosen model and effort reach the role's model-record marker via
#    the dispatch prompt (so the choice is recorded, R5).
para_has_all "$orch" 'model-choice' '(dispatch )?prompt' 'model-record' 'effort' \
  || fail "S187/AC8 — ORCHESTRATOR.md does not tell the orchestrator to state the chosen model and effort in the dispatch prompt for the role's model-record marker"

# 5. No model or tier name hardcoded (floors stay qualitative).
if grep -qiE '\b(opus|sonnet|haiku|fable|gpt-?[0-9]|gemini|llama)\b|claude-[a-z]+-[0-9]' "$orch"; then
  fail "S187/R1 — ORCHESTRATOR.md names a model: $(grep -iE '\b(opus|sonnet|haiku|fable|gpt-?[0-9]|gemini|llama)\b|claude-[a-z]+-[0-9]' "$orch" | head -3)"
fi
if grep -qiE '\b(top|highest|strongest|cheapest|lightest|smallest)[- ]tier\b|\b(tier|tier-)[ -]?[0-9]\b' "$orch"; then
  fail "S187/R1 — ORCHESTRATOR.md names a tier"
fi

# 6. No different-model rule. A sentence may mention "different model"
#    only to say it is NOT required.
sentences="$(tr '\n' ' ' < "$orch" | sed -E 's/\. +/.\
/g')"
bad=""
while IFS= read -r sentence; do
  grep -qiE '(different|another|second|separate|distinct|other|independent) (model|llm)|genuinely different|swap the model|switch (the )?model' <<<"$sentence" || continue
  grep -qiE "(not|n.t|never|no) (be )?(required|needed|necessary|mandatory)|need not|does not have to|doesn.t have to|without" <<<"$sentence" && continue
  bad="$bad$sentence"$'\n'
done <<<"$sentences"
[ -z "$bad" ] || fail "S187/AC2/AC8 — ORCHESTRATOR.md carries a different-model rule: $bad"

test_done
