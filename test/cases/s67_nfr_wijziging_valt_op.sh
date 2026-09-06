#!/usr/bin/env bash
# S67 — Een wijziging in het nfr-register die de vraagset raakt, valt op.
# Dekt: F2
#
# Aangetoond met een mutatie, zelfde stijl als R6/S41: een nieuw nfr-bestand
# met `van-toepassing-als: altijd` moet R9 voor élke fixture laten afwijken,
# en dat verschil moet het nieuwe ID benoemen — niet stilzwijgend oplosbaar
# door alleen de gouden set aan te passen.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

repo="$(sandbox_copy_repo)"
nulmeting="$repo/test/fixtures/nulmeting"

cat > "$repo/nfr/spec-mutatietest.md" <<'EOF'
---
id: spec-mutatietest
kop: Mutatietest
volgorde: 16
standaard: ja
van-toepassing-als: altijd
productie-poort: nee
status: actief
---

## Vraag

Is dit een test-mutatie?

## Ja betekent

Dit bestand bestaat alleen om S67 aan te tonen.

## Invulhulp

Niet van toepassing.
EOF

# TEST_REPO_ROOT overschrijven zou andere tests raken; deze test roept
# pending-changes.sh rechtstreeks in de gemuteerde kopie aan, in plaats van
# via de openstaande_ids()-helper die op TEST_REPO_ROOT leunt.
minst_een_verschil=0
for project in a2t-emails tennis-admin tennis-registration tennis-invoicing; do
  gouden="$nulmeting/$project/verwacht-openstaand.txt"
  [ -f "$gouden" ] || continue

  huidig="$SANDBOX/$project-gemuteerd.txt"
  "$repo/pending-changes.sh" "$nulmeting/$project" 2>/dev/null \
    | grep '^  - ' | sed 's/^  - //; s/ —.*//' | sort > "$huidig"

  if ! diff -q "$gouden" "$huidig" >/dev/null 2>&1; then
    minst_een_verschil=1
    if ! grep -qx 'spec-mutatietest' "$huidig"; then
      fail "S67 — $project week af, maar noemde spec-mutatietest niet als nieuw ID"
    fi
  fi
done

[ "$minst_een_verschil" -eq 1 ] || fail "S67 — een nieuw altijd-van-toepassing nfr-bestand veranderde geen enkele fixture-uitkomst; de mutatie viel nergens op"

test_klaar
