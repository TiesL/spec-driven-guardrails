#!/usr/bin/env bash
# S13 — Push naar een feature-branch blijft werken.
# Dekt: F7

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

guard="$TEST_REPO_ROOT/hooks/git-guardrails"
[ -x "$guard" ] || { fail "S13 — hooks/git-guardrails ontbreekt"; test_klaar; }

project="$(vers_project werk)"
git -C "$project" commit -q --allow-empty -m start
git -C "$project" checkout -q -b feature/werk

# De SessionEnd-hook draait precies dit commando bij het afsluiten van elke
# sessie. Blokkeert de guard dat, dan breekt hij de bestaande voorziening.
sessie_einde="$(grep -o 'git push origin HEAD' "$TEST_REPO_ROOT/settings/session-hooks.json" | head -1)"
[ -n "$sessie_einde" ] || fail "S13 — de SessionEnd-hook pusht niet meer met 'git push origin HEAD'; test bijwerken"

printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"%s","tool_input":{"command":"git push origin HEAD"}}' \
  "$project" | "$guard" >/dev/null 2>&1
status=$?
[ "$status" -ne 2 ] || fail "S13 — de guard blokkeert de push van de SessionEnd-hook"

# Andere tools dan Bash gaan sowieso niet langs deze guard, maar mochten ze dat
# wel doen, dan hoort hij ze door te laten in plaats van te raden.
printf '{"hook_event_name":"PreToolUse","tool_name":"Edit","cwd":"%s","tool_input":{"file_path":"/x","old_string":"git push origin main","new_string":"y"}}' \
  "$project" | "$guard" >/dev/null 2>&1
[ $? -ne 2 ] || fail "S13 — de guard blokkeert een niet-Bash tool"

test_klaar
