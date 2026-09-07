#!/usr/bin/env bash
# S79 — Een .claude/settings.json die naar een niet-bestaande map wijst (bijv.
# na een hernoeming zoals W32/#56, vóór her-adoptie) meldt zich luid bij
# sessiestart, in plaats van stil geen hooks te draaien.
# Dekt: W32 AC3

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

opdracht="$(
  if command -v jq >/dev/null 2>&1; then
    jq -r '.hooks.SessionStart[0].hooks[1].command' "$TEST_REPO_ROOT/settings/session-hooks.json"
  else
    python3 -c '
import json, sys
h = json.load(open(sys.argv[1]))["hooks"]["SessionStart"][0]["hooks"][1]
print(h["command"])
' "$TEST_REPO_ROOT/settings/session-hooks.json"
  fi
)"
[ -n "$opdracht" ] || fail "S79 — geen tweede SessionStart-opdracht gevonden in session-hooks.json"

# Given: een project waarvan .claude/settings.json naar een verdwenen checkout
# wijst — de precieze toestand na een repo-hernoeming vóór her-adoptie.
project="$(vers_project verweesd)"
mkdir -p "$project/.claude"
verdwenen="$SANDBOX/checkout-die-niet-meer-bestaat"
mkdir -p "$verdwenen/settings"
ln -s "$verdwenen/settings/session-hooks.json" "$project/.claude/settings.json"
rm -rf "$verdwenen"

# When: sessiestart draait de opdracht.
uitvoer="$(cd "$project" && bash -c "$opdracht" 2>&1)"
status=$?

# Then: dit meldt zich, en de sessie start niet stilzwijgend zonder hooks.
[ "$status" -eq 0 ] || fail "S79 — de opdracht faalde (exit $status) in plaats van netjes te melden en door te gaan"
printf '%s' "$uitvoer" | grep -qi 'niet bestaat' \
  || fail "S79 — geen melding over de ontbrekende map. Uitvoer: $uitvoer"
printf '%s' "$uitvoer" | grep -qi 'adopt.sh opnieuw' \
  || fail "S79 — de melding zegt niet wat je eraan doet. Uitvoer: $uitvoer"

# --- Regressie: een gezonde symlink blijft stil (geen valse meldingen) en
# laat pending-changes.sh gewoon draaien.
project_gezond="$(vers_project gezond)"
mkdir -p "$project_gezond/.claude"
ln -s "$TEST_REPO_ROOT/settings/session-hooks.json" "$project_gezond/.claude/settings.json"
uitvoer_gezond="$(cd "$project_gezond" && bash -c "$opdracht" 2>&1)"
printf '%s' "$uitvoer_gezond" | grep -qi 'niet bestaat' \
  && fail "S79 — valse melding bij een gezonde symlink. Uitvoer: $uitvoer_gezond"

# --- Regressie: geen .claude/settings.json (niet-geadopteerd project) blijft
# stil — geen melding, geen foutstatus.
project_kaal="$(vers_project kaal)"
uitvoer_kaal="$(cd "$project_kaal" && bash -c "$opdracht" 2>&1)"
status_kaal=$?
[ "$status_kaal" -eq 0 ] || fail "S79 — een niet-geadopteerd project gaf een foutstatus"
[ -z "$uitvoer_kaal" ] || fail "S79 — een niet-geadopteerd project gaf onverwachte uitvoer: $uitvoer_kaal"

test_klaar
