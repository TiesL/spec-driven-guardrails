#!/usr/bin/env bash
# S78 — Eén 'adopt.sh'-run wijst een project met verhuisde symlinks (bijv. na
# de W32/#56-hernoeming) volledig om naar de nieuwe locatie.
# Dekt: W32 AC4

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# Given: een project geadopteerd vanuit een "oude" checkout-locatie.
oud="$(sandbox_copy_repo oude-checkout)"
project="$(vers_project doelproject)"
SPEC_DRIVEN_GUARDRAILS_DIR="$oud" "$oud/adopt.sh" "$project" >/dev/null 2>&1

[ "$(readlink "$project/CLAUDE.md")" = "$oud/WORKFLOW.md" ] \
  || fail "S78 — voorbereiding: CLAUDE.md wijst niet naar de oude locatie"
[ "$(readlink "$project/.claude/settings.json")" = "$oud/settings/session-hooks.json" ] \
  || fail "S78 — voorbereiding: settings.json wijst niet naar de oude locatie"

# When: de checkout "verhuist" (simuleert een repo-hernoeming: nieuwe map,
# oude is weg) en adopt.sh draait opnieuw, nu met de nieuwe locatie.
nieuw="$SANDBOX/nieuwe-checkout"
mv "$oud" "$nieuw"
SPEC_DRIVEN_GUARDRAILS_DIR="$nieuw" "$nieuw/adopt.sh" "$project" >/dev/null 2>&1

# Then: beide symlinks wijzen nu naar de nieuwe locatie, in één handeling.
[ "$(readlink "$project/CLAUDE.md")" = "$nieuw/WORKFLOW.md" ] \
  || fail "S78 — CLAUDE.md wijst na de migratie niet naar de nieuwe locatie"
[ "$(readlink "$project/.claude/settings.json")" = "$nieuw/settings/session-hooks.json" ] \
  || fail "S78 — settings.json wijst na de migratie niet naar de nieuwe locatie"

# And: een derde run is een no-op — geen foutmelding, geen wijziging.
na_eerste="$(readlink "$project/CLAUDE.md")"
SPEC_DRIVEN_GUARDRAILS_DIR="$nieuw" "$nieuw/adopt.sh" "$project" >/dev/null 2>&1 \
  || fail "S78 — een herhaalde run na migratie faalde"
[ "$(readlink "$project/CLAUDE.md")" = "$na_eerste" ] \
  || fail "S78 — een herhaalde run na migratie veranderde de symlink opnieuw"

test_klaar
