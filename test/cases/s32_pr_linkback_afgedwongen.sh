#!/usr/bin/env bash
# S32 — Elke actieve entry heeft een PR-linkback.
# Dekt: F15

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# AC2 — dit repo zelf, ongewijzigd: elke actieve entry heeft al een
# **PR:**-veld. check moet daar geen fout over geven.
repo_goed="$(sandbox_copy_repo goed)"
if ! "$repo_goed/check" --no-tests "$repo_goed" >/dev/null 2>&1; then
  uitvoer="$("$repo_goed/check" --no-tests "$repo_goed" 2>&1)"
  case "$uitvoer" in
    *"PR:"*) fail "S32/AC2 — dit repo's eigen CHANGES.md gaf ten onrechte een PR-linkback-fout: $uitvoer" ;;
    *) : ;; # andere, ongerelateerde fout — niet dit scenario's zorg
  esac
fi

# AC1/AC3 — een entry zonder **PR:**-veld faalt, met het ID in de melding.
repo_kapot="$(sandbox_copy_repo kapot)"
# proces-prd's PR-regel weghalen; de rest van het bestand blijft intact.
sed -i.bak '/^- \*\*PR:\*\* https:\/\/github\.com\/TiesL\/claude-workflow\/pull\/1$/d' "$repo_kapot/CHANGES.md"
rm -f "$repo_kapot/CHANGES.md.bak"

uitvoer="$("$repo_kapot/check" --no-tests "$repo_kapot" 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "S32/AC1,AC3 — CHANGES.md zonder PR-veld gaf exit 0"
assert_contains "S32 — het ID van de kapotte entry staat in de melding" "proces-prd" "$uitvoer"

# AC4 — een gearchiveerde entry behoudt zijn linkback; check moet daar niet
# over klagen zolang die intact is (dit repo's CHANGES-ARCHIEF.md, ongewijzigd).
case "$uitvoer" in
  *"prd-testscenarios-issue-templates"*)
    fail "S32/AC4 — de gearchiveerde entry werd ten onrechte gemeld: $uitvoer" ;;
esac

test_klaar
