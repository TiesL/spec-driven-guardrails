#!/usr/bin/env bash
# S2 — `check` faalt op ongeldige JSON in de hookconfiguratie.
# Dekt: F1

set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

repo="$(sandbox_copy_repo)"

# Given: session-hooks.json met een ontbrekende komma.
cat > "$repo/settings/session-hooks.json" <<'JSON'
{
  "hooks": {
    "SessionStart": []
  }
  "attribution": {
    "commit": ""
  }
}
JSON

# When: ./check draait.
uitvoer="$("$TEST_REPO_ROOT/check" --no-tests "$repo" 2>&1)"
status=$?

# Then: exit != 0, met een melding die het bestand noemt.
if [ "$status" -eq 0 ]; then
  fail "S2 — check slaagde op ongeldige JSON"
fi
assert_contains "S2" "session-hooks.json" "$uitvoer"

# And: dit gebeurt ook wanneer shellcheck niet geinstalleerd is. Een minimale
# PATH houdt jq en python3 (beide in /usr/bin op macOS) maar laat shellcheck
# vallen, dat in /opt/homebrew/bin of /usr/local/bin staat.
uitvoer_zonder_sc="$(PATH=/usr/bin:/bin "$TEST_REPO_ROOT/check" --no-tests "$repo" 2>&1)"
status_zonder_sc=$?

if [ "$status_zonder_sc" -eq 0 ]; then
  fail "S2 — check slaagde op ongeldige JSON toen shellcheck ontbrak"
fi
assert_contains "S2 (zonder shellcheck)" "session-hooks.json" "$uitvoer_zonder_sc"

test_klaar
