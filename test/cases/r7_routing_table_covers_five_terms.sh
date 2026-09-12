#!/usr/bin/env bash
# R7 — An adopted project still sees the full operational instruction.
# Covers: F12
#
# The five terms (branching, quality review, substantiation requirement,
# deploy-guards, adoption registry) must still resolve in a single jump
# after WORKFLOW.md's trim: directly in the file, or via an explicit
# reference to a skill that actually exists.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

project="$(fresh_project r7)"
adopt "$project"

claude_md="$project/CLAUDE.md"
[ -f "$claude_md" ] || { fail "R7 — CLAUDE.md is missing after adoption"; test_done "R7"; }

controleer_term() {
  local term="$1"
  local rows count skill target
  rows="$(routing_table_rows "$claude_md" | grep -i "$term" || true)"
  count="$(printf '%s\n' "$rows" | grep -c . || true)"
  [ "$count" -ge 1 ] || { fail "R7 — '$term' yields no routing table row"; return; }
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    skill="$(skill_from_row "$row")"
    target="$project/.claude/skills/$skill/SKILL.md"
    [ -f "$target" ] \
      || fail "R7 — '$term' points to skill '$skill', but $target does not exist"
  done <<< "$rows"
}

controleer_term "quality review"
controleer_term "substantiation requirement"
controleer_term "deploy-guards"
controleer_term "adoption registry"

# Branching is not moved: the section stays directly in the file.
grep -qi '^## Branch strategy' "$claude_md" \
  || fail "R7 — 'Branch strategy' is no longer directly in CLAUDE.md"

test_done "R7"
