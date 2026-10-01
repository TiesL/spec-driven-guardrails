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

# Then: one table row per stage, in pipeline order, each naming the stage
# as a cell of its own and carrying that stage's role:<name> label.
grep -n '^|' "$skill" > "$SANDBOX/rows.txt"
prev=0
i=0
while [ "$i" -lt 5 ]; do
  stage="${stage_list[$i]}"
  label="${label_list[$i]}"
  row="$(awk -F'|' -v s="$stage" -v l="$label" '
    {
      hit = 0
      for (c = 2; c < NF; c++) {
        cell = $c; gsub(/[ `*]/, "", cell)
        if (cell == s) hit = 1
      }
      if (hit && index($0, l) > 0) { split($1, n, ":"); print n[1]; exit }
    }
  ' "$SANDBOX/rows.txt")"
  if [ -z "$row" ]; then
    fail "S160 — no table row names stage '$stage' together with label '$label'"
  elif [ "$row" -le "$prev" ]; then
    fail "S160 — stage '$stage' (line $row) is listed before an earlier stage; order must be: $stages"
  else
    prev="$row"
  fi
  i=$((i + 1))
done

# And: the model-record marker is named, with model-choice as the single
# place its format is defined (A14(b): no second literal copy here).
grep -q 'model-record' "$skill" || fail "S160 — the skill never mentions the model-record marker"
grep -q 'model-choice' "$skill" || fail "S160 — the skill does not point to model-choice for the marker format"
if grep -n '<!-- model-record' "$skill" > "$SANDBOX/marker.txt"; then
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
