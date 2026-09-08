#!/usr/bin/env bash
# S81 — spec-driven-guardrails kan zichzelf adopteren.
# Dekt: F7, F8

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# Given: een sandboxkopie van dit repo, gebruikt als zowel
# SPEC_DRIVEN_GUARDRAILS_DIR als adoptiedoel. sandbox_copy_repo kopieert de
# huidige staat van dit repo (inclusief de eventuele weigering hierboven, als
# die nog niet verwijderd is — precies wat "eerst rood" hier toetst).
repo="$(sandbox_copy_repo)"
git -C "$repo" init -q -b main
git -C "$repo" -c user.name=test -c user.email=test@example.invalid \
  commit -q --allow-empty -m "eerste commit"

# Vingerafdruk van bestaande, gecommitte bestanden vóór adoptie — om aan te
# tonen dat zelf-adoptie niets van dit repo zelf overschrijft.
before_prd="$(cat "$repo/PRD.md")"
before_scenarios="$(cat "$repo/TEST-SCENARIOS.md")"
before_check="$(cat "$repo/check")"

# When: adopt.sh draait met zichzelf als bron én doel.
uitvoer="$(SPEC_DRIVEN_GUARDRAILS_DIR="$repo" "$repo/adopt.sh" "$repo" 2>&1)"
status=$?

# Then: hij adopteert daadwerkelijk, in plaats van de weigering te tonen.
case "$uitvoer" in
  *"geen adoptie nodig"*)
    fail "S81 — adopt.sh weigert nog steeds zichzelf te adopteren: $uitvoer"
    test_klaar
    ;;
esac
[ "$status" -eq 0 ] || fail "S81 — adopt.sh tegen zichzelf gaf exitstatus $status: $uitvoer"

[ -L "$repo/CLAUDE.md" ] || fail "S81 — CLAUDE.md is geen symlink na zelf-adoptie"
doel_claude="$(readlink "$repo/CLAUDE.md" 2>/dev/null)"
case "$doel_claude" in
  */WORKFLOW.md) ;;
  *) fail "S81 — CLAUDE.md wijst niet naar WORKFLOW.md: $doel_claude" ;;
esac

[ -L "$repo/.claude/settings.json" ] || fail "S81 — .claude/settings.json is geen symlink na zelf-adoptie"
doel_settings="$(readlink "$repo/.claude/settings.json" 2>/dev/null)"
case "$doel_settings" in
  */settings/session-hooks.json) ;;
  *) fail "S81 — .claude/settings.json wijst niet naar settings/session-hooks.json: $doel_settings" ;;
esac

# And: geen enkel bestaand, gecommit bestand verandert.
[ "$(cat "$repo/PRD.md")" = "$before_prd" ] \
  || fail "S81 — PRD.md is gewijzigd door zelf-adoptie"
[ "$(cat "$repo/TEST-SCENARIOS.md")" = "$before_scenarios" ] \
  || fail "S81 — TEST-SCENARIOS.md is gewijzigd door zelf-adoptie"
[ "$(cat "$repo/check")" = "$before_check" ] \
  || fail "S81 — check is gewijzigd door zelf-adoptie"

# And: de git-guardrails-hook is daarna functioneel — een gefabriceerde
# PreToolUse-aanroep die een directe push naar main voorstelt, wordt
# geweigerd, net als in elk geadopteerd project.
invoer='{"tool_name":"Bash","cwd":"'"$repo"'","tool_input":{"command":"git push origin main"}}'
hook_uitvoer="$(printf '%s' "$invoer" | "$repo/hooks/git-guardrails" 2>&1)"
hook_status=$?
[ "$hook_status" -ne 0 ] \
  || fail "S81 — de PreToolUse-guard weigerde een directe push naar main niet: $hook_uitvoer"
assert_contains "S81 — de melding komt overeen met de PreToolUse-guard" "main krijgt zijn wijzigingen via een PR" "$hook_uitvoer"

# And: de native git-hooks zijn ook geïnstalleerd en weigeren hetzelfde
# buiten Claude Code om (zelfde patroon als S50).
[ -L "$repo/.git/hooks/pre-commit" ] || fail "S81 — pre-commit is geen symlink na zelf-adoptie"
[ -L "$repo/.git/hooks/pre-push" ] || fail "S81 — pre-push is geen symlink na zelf-adoptie"
native_uitvoer="$(cd "$repo" && git commit -q --allow-empty -m "rechtstreeks op main" 2>&1)"
native_status=$?
[ "$native_status" -ne 0 ] \
  || fail "S81 — de native pre-commit-hook weigerde een directe commit op main niet"
assert_contains "S81 — de native-hookmelding komt overeen met de PreToolUse-guard" "main krijgt zijn wijzigingen via een PR" "$native_uitvoer"

# And: een tweede aanroep is idempotent.
uitvoer2="$(SPEC_DRIVEN_GUARDRAILS_DIR="$repo" "$repo/adopt.sh" "$repo" 2>&1)"
status2=$?
[ "$status2" -eq 0 ] || fail "S81 — een tweede zelf-adoptie faalt: $uitvoer2"
gitignore_regels="$(grep -c '^CLAUDE\.md$' "$repo/.gitignore" 2>/dev/null || echo 0)"
[ "$gitignore_regels" -le 1 ] \
  || fail "S81 — een tweede zelf-adoptie voegt CLAUDE.md dubbel toe aan .gitignore"

test_klaar
