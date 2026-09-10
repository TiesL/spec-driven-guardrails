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

project="$(vers_project r7)"
adopteer "$project"

claude_md="$project/CLAUDE.md"
[ -f "$claude_md" ] || { fail "R7 — CLAUDE.md is missing after adoption"; test_klaar "R7"; }

controleer_term() {
  local term="$1"
  local rijen aantal skill doel
  rijen="$(wegwijzer_rijen "$claude_md" | grep -i "$term" || true)"
  aantal="$(printf '%s\n' "$rijen" | grep -c . || true)"
  [ "$aantal" -ge 1 ] || { fail "R7 — '$term' yields no routing table row"; return; }
  while IFS= read -r rij; do
    [ -n "$rij" ] || continue
    skill="$(skill_van_rij "$rij")"
    doel="$project/.claude/skills/$skill/SKILL.md"
    [ -f "$doel" ] \
      || fail "R7 — '$term' points to skill '$skill', but $doel does not exist"
  done <<< "$rijen"
}

controleer_term "quality review"
controleer_term "substantiation requirement"
controleer_term "deploy-guards"
controleer_term "adoption registry"

# Branching is not moved: the section stays directly in the file.
grep -qi '^## Branch strategy' "$claude_md" \
  || fail "R7 — 'Branch strategy' is no longer directly in CLAUDE.md"

test_klaar "R7"
