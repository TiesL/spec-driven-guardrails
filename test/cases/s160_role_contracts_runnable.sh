#!/usr/bin/env bash
# S160 — The installed role-contracts skill says how to run the pipeline without the WIP docs.
# Covers: F37
#
# Issue #369, AC6, and Architect decision A14(b)/(c). Seam: the SKILL.md as
# an adopted project sees it. The stage order and the stage-to-label
# mapping are read from role-label-staleness.sh, the script an adopter
# runs against those labels, rather than retyped here: the skill has to
# agree with what that script will actually check.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

clone="$(sandbox_copy_repo clone)"
project="$(fresh_project adopter)"
SPEC_DRIVEN_GUARDRAILS_DIR="$clone" "$clone/adopt.sh" "$project" >/dev/null 2>&1

skill="$project/.claude/skills/role-contracts/SKILL.md"
if [ ! -r "$skill" ]; then
  fail "S160 — no installed role-contracts skill in the adopted project (see S155)"
  test_done
fi

# The pipeline's stage order and labels, as role-label-staleness.sh defines them.
stages="$(sed -n 's/^STAGES=(\(.*\))$/\1/p' "$clone/role-label-staleness.sh")"
labels="$(sed -n 's/^ROLE_LABELS=(\(.*\))$/\1/p' "$clone/role-label-staleness.sh")"
read -r -a stage_list <<<"$stages"
read -r -a label_list <<<"$labels"
if [ "${#stage_list[@]}" -ne 5 ] || [ "${#label_list[@]}" -ne 5 ]; then
  fail "S160 — could not read five stages and five labels from role-label-staleness.sh"
  test_done
fi

# Then: the OR5 item of the installed ORCHESTRATOR.md (part 1, tier
# judgment; amended by #499 AC14, A41: no longer a `^|` table) lists the five
# Stage/Role/Label/stage= tuples, each stage with its label, in the order
# role-label-staleness.sh defines. Since #371 (A16) the run rules live in
# that file, which SKILL.md points to. Stage-order behaviour: OB5, OB36.
orch="$project/.claude/skills/role-contracts/ORCHESTRATOR.md"
grep -q 'ORCHESTRATOR.md' "$skill" || fail "S160 — SKILL.md does not point to ORCHESTRATOR.md for the run rules"
# shellcheck source=../fixtures/orchestrator-core-helpers.sh disable=SC1091
OC_ORCH="$orch"
OC_TSV="$project/.claude/skills/role-contracts/orchestrator-rules.tsv"
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/orchestrator-core-helpers.sh"
oc_rule "S160" OR5 judgment 1
or5="$(oc_item OR5)"
[ -n "$or5" ] || fail "S160 — no OR5 stage item in the installed skill's ORCHESTRATOR.md"
prev=0
i=0
while [ "$i" -lt 5 ]; do
  stage="${stage_list[$i]}"
  label="${label_list[$i]}"
  # Tuples are `Stage/Role/`label`/stage-value`, separated by `;`.
  pos="$(tr ';' '\n' <<<"${or5#*: }" | awk -v s="$stage" -v l="$label" '
    { t = $0; gsub(/[ `.]/, "", t); n = split(t, f, "/")
      if (n == 4 && f[1] == s && f[3] == l && f[4] == s) { print NR; exit } }')"
  if [ -z "$pos" ]; then
    fail "S160 — OR5 has no tuple naming stage '$stage' together with label '$label'"
  elif [ "$pos" -le "$prev" ]; then
    fail "S160 — stage '$stage' (tuple $pos) is listed before an earlier stage; order must be: $stages"
  else
    prev="$pos"
  fi
  i=$((i + 1))
done

# And: the model-record marker is named, with model-choice as the single
# place its format is defined (A14(b): no second literal copy here).
test_source_match -q 'model-record' "$skill" || fail "S160 — the skill never mentions the model-record marker"
grep -q 'model-choice' "$skill" || fail "S160 — the skill does not point to model-choice for the marker format"
if test_source_match -n '<!-- model-record' "$skill" "$orch" > "$SANDBOX/marker.txt" 2>/dev/null; then
  fail "S160 — the skill restates the model-record marker literally instead of pointing to model-choice:"
  cat "$SANDBOX/marker.txt" >&2
fi

# And: the adopting project is told to create the five labels in its own
# repo (the command), and why (role-label-staleness.sh reads them).
grep -q 'gh label create' "$skill" \
  || fail "S160 — the skill does not give the command to create the role labels in the project's own repo"
grep -q 'role-label-staleness.sh' "$skill" \
  || fail "S160 — the skill does not say the labels are what role-label-staleness.sh reads"

# And: every role takes part in every change (no phase skipping in v1).
awk -v RS= 'tolower($0) ~ /every role/ && tolower($0) ~ /every change/ { found = 1 } END { exit !found }' "$skill" \
  || fail "S160 — the skill does not state that every role takes part in every change"

test_done
