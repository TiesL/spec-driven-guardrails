#!/usr/bin/env bash
# S8 — Het signaal verandert de openstaand-set niet.
# Dekt: F6

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

project="$(vers_project doelproject)"
adopteer "$project"

# Given: hetzelfde project, één keer met onderbouwingsgaten en één keer zonder.
met_gaten="$SANDBOX/met-gaten.txt"
openstaande_ids "$project" > "$met_gaten"

sed -i.bak 's/bij adoptie — vereist onderbouwing tijdens PRD\/architectuur/onderbouwd voor dit project/g' \
  "$project/WORKFLOW-ADOPTIE.md"
rm -f "$project/WORKFLOW-ADOPTIE.md.bak"

zonder_gaten="$SANDBOX/zonder-gaten.txt"
openstaande_ids "$project" > "$zonder_gaten"

# Then: de lijst openstaande ID's is identiek. Het signaal staat ernaast, niet
# erin — beantwoord() is bewust niet aangepast, want dat zou R9 breken.
assert_ids_gelijk "S8" "$met_gaten" "$zonder_gaten"

# En de melding zelf verschilt wél tussen die twee toestanden, anders toetst
# deze vergelijking niets.
voor="$SANDBOX/voor.txt"; na="$SANDBOX/na.txt"
adopteer "$(vers_project tweede)" >/dev/null 2>&1 || true
tweede="$SANDBOX/tweede"
"$TEST_REPO_ROOT/pending-changes.sh" "$tweede" > "$voor" 2>/dev/null
"$TEST_REPO_ROOT/pending-changes.sh" "$project" > "$na" 2>/dev/null
if diff -q "$voor" "$na" >/dev/null 2>&1; then
  fail "S8 — de uitvoer is identiek met en zonder onderbouwingsgaten; het signaal doet niets"
fi

test_klaar
