#!/usr/bin/env bash
# S203 — the orchestrator hands each role the emit command (never a typed
# marker), and the grammar has one owner.
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

# --- AC1 (A26 amended): the orchestrator hands the role a COMMAND, not a line ---
# one paragraph: the wrapper `model-record-emit.sh`, found through
# $SPEC_DRIVEN_GUARDRAILS_DIR or the project's installed skill, with --stage and
# --effort filled in (unknown when it cannot find the effort out); the role adds
# --model with its own exact id (the Reviewer also --floor-basis) and pastes
# the output unchanged as the first line of its report; the requested model is
# named; nobody types a marker by hand
para_has_all "$orch" 'model-record-emit\.sh' '--stage' '--effort' '(dispatch )?prompt' \
  || fail "S203/AC1 — no paragraph of ORCHESTRATOR.md gives the role the model-record-emit.sh command with --stage and --effort in the dispatch prompt"
para_has_all "$orch" 'model-record-emit\.sh' 'SPEC_DRIVEN_GUARDRAILS_DIR|\.claude/skills/pre-merge-review' \
  || fail "S203/AC1 — ORCHESTRATOR.md must say how to find the wrapper (SPEC_DRIVEN_GUARDRAILS_DIR, or the project's installed skill)"
para_has_all "$orch" 'model-record-emit\.sh' 'effort' 'unknown' \
  || fail "S203/AC1 — ORCHESTRATOR.md must say to fill --effort with unknown when the effort cannot be set or found out"
para_has_all "$orch" 'model-record-emit\.sh' '--model' '(role|it)[^.]*(adds|add|fills|supplies|passes)|(adds|add|fills|supplies|passes)[^.]*--model|own (exact )?(model )?id' \
  || fail "S203/AC1 — ORCHESTRATOR.md must say the ROLE adds --model with its own exact model id"
para_has_all "$orch" 'model-record-emit\.sh' '--floor-basis' 'Review' \
  || fail "S203/AC1 — ORCHESTRATOR.md must say the Reviewer also adds --floor-basis"
para_has_all "$orch" 'model-record-emit\.sh' 'first line' '(unchanged|verbatim|as is|nothing else)' \
  || fail "S203/AC1 — ORCHESTRATOR.md must tell the role to paste the output, unchanged, as the first line of its report"
para_has_all "$orch" 'model-record-emit\.sh' '(requested|chose|chosen|asked for)' 'model' \
  || fail "S203/AC1 — ORCHESTRATOR.md must say to name the requested model in the prompt"
para_has_all "$orch" 'model-record-emit\.sh' '(never|not|nobody|no one)[^.]*(typ|hand|write)' \
  || fail "S203/AC1 — ORCHESTRATOR.md must say a marker is never typed by hand"
# the bare "state the model and effort" sentence alone is not enough
if grep -qE 'so the role records them in its .model-record. marker' "$orch" && ! grep -q 'model-record-emit' "$orch"; then
  fail "S203/AC1 — only the old 'state model and effort' sentence is there, no wrapper command"
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

# --- the other texts ---------------------------------------------------------------
para_has_all "$mc" 'model-record-emit\.sh' '(never|not)[^.]*(typ|hand)' \
  || fail "S203/A26 — model-choice's 'Machine-readable form' must open with: produce the line with model-record-emit.sh, never type it"
para_has_all "$pmr" 'model-record-emit\.sh' \
  || fail "S203/A26 — pre-merge-review's marker grammar text must say the Reviewer produces its marker with model-record-emit.sh"
para_has_all "$rc" 'model-record-emit\.sh' 'first line' '(never|not)[^.]*(typ|hand)' \
  || fail "S203/A26 — role-contracts' shared section must say the report's first line is the output of the model-record-emit.sh command in the prompt, never typed by hand"
para_has_all "$rc" 'model-record-emit\.sh' '(no command|has no command|without a command|lacks? (the|a) command|missing)' '(run|use)' '(say|says|state|states|report)' \
  || fail "S203/A26 — role-contracts must say a role whose prompt has no command runs the wrapper itself and says so in its report"
# the grammar's one home: no other document carries a marker template
for f in "$TEST_REPO_ROOT"/WORKFLOW.md "$TEST_REPO_ROOT"/README.md "$TEST_REPO_ROOT"/skills/*/SKILL.md "$TEST_REPO_ROOT"/skills/role-contracts/*.md; do
  [ -f "$f" ] || continue
  case "$f" in "$mc" | "$pmr") continue ;; esac
  if grep -qE 'model="<model>"|model-record: stage=<' "$f"; then
    fail "S203/AC2 — ${f#"$TEST_REPO_ROOT"/} carries a second copy of the marker template; the owner is model-choice"
  fi
done

test_done
