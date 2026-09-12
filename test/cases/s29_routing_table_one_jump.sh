#!/usr/bin/env bash
# S29 — The routing table resolves every moved topic in a single jump.
# Covers: F12

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

workflow="$TEST_REPO_ROOT/WORKFLOW.md"
[ -f "$workflow" ] || { fail "S29 — WORKFLOW.md is missing"; test_done "S29"; }

alle_skills="$(cd "$TEST_REPO_ROOT/skills" 2>/dev/null && ls -d */ 2>/dev/null | sed 's#/$##')"

controleer_precies_een_rij() {
  local term="$1" verwachte_skill="$2"
  local rows count skill
  rows="$(routing_table_rows "$workflow" | grep -i "$term" || true)"
  count="$(printf '%s\n' "$rows" | grep -c . || true)"
  if [ "$count" -ne 1 ]; then
    fail "S29 — '$term' yields $count routing table rows, 1 expected"
    return
  fi
  skill="$(skill_from_row "$rows")"
  printf '%s\n' "$alle_skills" | grep -qxF "$skill" \
    || fail "S29 — '$term' points to '$skill', which is not an existing skill"
  [ "$skill" = "$verwachte_skill" ] \
    || fail "S29 — '$term' points to '$skill', expected '$verwachte_skill'"
}

controleer_precies_een_rij "quality review" "pre-merge-review"
controleer_precies_een_rij "substantiation requirement" "adoption-registry"
controleer_precies_een_rij "adoption registry" "adoption-registry"
controleer_precies_een_rij "deploy-guards" "deploy-guards"

# Substantiation requirement and adoption registry land in the same skill,
# but should be two separate rows, not silently merged into one.
row_substantiation="$(routing_table_rows "$workflow" | grep -i "substantiation requirement" || true)"
row_adoption="$(routing_table_rows "$workflow" | grep -i "adoption registry" || true)"
[ -z "$row_substantiation" ] || [ -z "$row_adoption" ] || [ "$row_substantiation" != "$row_adoption" ] \
  || fail "S29 — substantiation requirement and adoption registry share the same routing table row"

# Branching is not moved: no routing table row needed, the section stays
# directly in WORKFLOW.md.
grep -qi '^## Branch strategy' "$workflow" \
  || fail "S29 — 'Branch strategy' is no longer directly in WORKFLOW.md"

test_done "S29"
