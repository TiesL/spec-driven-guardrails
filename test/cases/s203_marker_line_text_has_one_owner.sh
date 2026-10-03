#!/usr/bin/env bash
# S203 — the orchestrator hands each role its marker line from the one
# template, and the grammar has one owner.
# Covers: F40
#
# Issue #402, R1/R2, AC1/AC2, A26. What the orchestrating session then
# actually PASTES into its dispatch prompts, and whether a dispatched role
# posts the line unchanged, is model behaviour (shown only by the scratch-repo
# re-run, a human check). Mechanical proxy: the instruction exists as one
# coherent paragraph (so unrelated text cannot satisfy it), it points to the
# template instead of restating the grammar, the role-contracts text says what
# a role does when its prompt has no line, and the template is the single
# copy. Seam: the text of ORCHESTRATOR.md, role-contracts/SKILL.md,
# model-choice and pre-merge-review.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"
# shellcheck source=../fixtures/review-floor-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/review-floor-helpers.sh"

orch="$TEST_REPO_ROOT/skills/role-contracts/ORCHESTRATOR.md"
rc="$TEST_REPO_ROOT/skills/role-contracts/SKILL.md"
mc="$TEST_REPO_ROOT/skills/model-choice/SKILL.md"
pmr="$TEST_REPO_ROOT/skills/pre-merge-review/SKILL.md"
for f in "$orch" "$rc" "$mc" "$pmr"; do
  [ -f "$f" ] || { fail "S203 — ${f#"$TEST_REPO_ROOT"/} is missing"; test_done; }
done

# --- AC1: the dispatch instruction -----------------------------------------
# one paragraph: marker line, from the model-choice template ("Machine-readable
# form"), in the dispatch prompt, per stage; orchestrator fills stage and
# effort (unknown when it cannot tell); the role fills model with its own id;
# the role posts the line, completed, first and otherwise unchanged
para_has_all "$orch" 'marker line' 'model-choice' 'Machine-readable form' '(dispatch )?prompt' \
  || fail "S203/AC1 — no paragraph of ORCHESTRATOR.md tells the orchestrator to put the marker line, taken from model-choice's 'Machine-readable form', into the dispatch prompt"
para_has_all "$orch" 'marker line' '(each|every|per|its) stage|stage=' 'effort' 'unknown' \
  || fail "S203/AC1 — ORCHESTRATOR.md must say the orchestrator fills in the stage and the effort (unknown when it cannot find it out)"
para_has_all "$orch" 'marker line' '(role|it) (fills|writes|puts|records|completes)[^.]*model|model[^.]*(role.s own|its own|the role fills)' '(own|exact) (model )?id|exact model' \
  || fail "S203/AC1 — ORCHESTRATOR.md must say the ROLE fills in model with its own exact model id (the dispatch tool only takes an alias)"
para_has_all "$orch" 'marker line' 'first line' '(unchanged|nothing else|changing nothing|without changing)' \
  || fail "S203/AC1 — ORCHESTRATOR.md must tell the role to post the line, completed, as the first line of its report, changing nothing else"
para_has_all "$orch" 'marker line' '(requested|chose|chosen|asked for)' 'model' '(alias|differs|differ|own id)' \
  || fail "S203/AC1 — ORCHESTRATOR.md must say to name the requested model in the prompt so the role can say so if its own id differs"
# the instruction replaces the old bare "state the model and effort" sentence:
if grep -qE 'so the role records them in its .model-record. marker' "$orch" && ! para_has_all "$orch" 'marker line'; then
  fail "S203/AC1 — only the old 'state model and effort' sentence is there, no marker line"
fi

# --- AC2: no second copy of the grammar in ORCHESTRATOR.md -------------------
# (a bare `model="…"` hint, "leave this for the role to fill", is not grammar)
attr_ere='(effort|stage|floor-basis)="|model="[^"…]'
if grep -qE "$attr_ere" "$orch"; then
  fail "S203/AC2 — ORCHESTRATOR.md carries a quoted-attribute example of the marker (a second copy of the grammar): $(grep -nE "$attr_ere" "$orch" | head -2)"
fi
if grep -qE 'model-record:[[:space:]]*stage=' "$orch"; then
  fail "S203/AC2 — ORCHESTRATOR.md spells out a marker line ('model-record: stage='); it must point to the template, not copy it"
fi
if grep -qiE 'low ?(\||,|/) ?medium ?(\||,|/) ?high|bare token|quoted attributes? (are|must)|quoting rules?|must be quoted|allowed values' "$orch"; then
  fail "S203/AC2 — ORCHESTRATOR.md restates grammar (quoting rule or the effort values); the owner is model-choice / pre-merge-review"
fi

# --- the template is the one copy ------------------------------------------------
grep -qE 'model-record: stage=<[^>]*> model="<model>" effort=' "$mc" \
  || fail "S203/AC2 — model-choice must keep the marker template (the single owner of the line)"
grep -qE 'model-record: stage=Review model="<model>" effort="[^"]*" floor-basis=' "$mc" \
  || fail "S203/AC2 — model-choice must keep the Review template with floor-basis"
if grep -qE 'stage="' "$mc" "$pmr" "$orch" "$rc"; then
  fail "S203/AC2 — a skill shows a QUOTED stage (stage=\"...\"), which is malformed: the stage is a bare token"
fi
for f in "$orch" "$rc"; do
  if grep -qE 'model-record: stage=<[^>]*> model=' "$f"; then
    fail "S203/AC2 — ${f#"$TEST_REPO_ROOT"/} carries its own copy of the marker template"
  fi
done
# the pointer names the owning section, and it exists
grep -q 'Machine-readable form' "$mc" || fail "S203/AC2 — model-choice has no 'Machine-readable form' section to point to"

# --- a role with no line in its prompt (role-contracts, shared section) ----------
para_has_all "$rc" 'dispatch prompt' 'model-record' 'model-choice' 'first line' \
  || fail "S203/AC1 — role-contracts' shared section must say a report's first line is the model-record marker from the dispatch prompt, completed"
para_has_all "$rc" 'dispatch prompt' 'model-record' '(no line|none|lacks?|lacked|missing|without|has no)' '(template|model-choice)' '(say|says|state|states|note|notes|report)' \
  || fail "S203/AC1 — role-contracts must say that a role whose prompt has no marker line writes it from the model-choice template and says so in its report"
para_has_all "$rc" 'model-record' '(not|never|must not)[^.]*(refuse|stop|block)|still (post|write|do)|rather than (refus|stop)' \
  || fail "S203/AC1 — role-contracts must say the role does not refuse to work when the line is missing"

test_done
