#!/usr/bin/env bash
# S41 — Een kapot registerbestand valt niet stil weg.
# Dekt: F4

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

geldig_blok() {
  cat <<'MD'
## Vraag

Is dit kenmerk relevant?

## Ja betekent

`PRD.md` beantwoordt de subsectie "Proef".

## Invulhulp

Waar gaat dit over?
MD
}

# Elk geval is een volledig bruikbaar bestand op één gebrek na. Zonder controle
# verdwijnt zo'n bestand uit álle consumenten tegelijk, en dan ziet de
# driftcontrole niets: beide kanten missen hem immers.
for geval in geen-volgorde naam-wijkt-af; do
  repo="$SANDBOX/repo-$geval"
  mkdir -p "$repo"
  (cd "$TEST_REPO_ROOT" && tar --exclude='./.git' -cf - .) | (cd "$repo" && tar -xf -)

  case "$geval" in
    geen-volgorde)
      doel="$repo/nfr/spec-proef.md"
      { printf -- '---\nid: spec-proef\nkop: Proef\nstandaard: ja\nvan-toepassing-als: altijd\nproductie-poort: nee\nstatus: actief\n---\n\n'
        geldig_blok; } > "$doel" ;;
    naam-wijkt-af)
      doel="$repo/nfr/spec-verkeerd-genoemd.md"
      { printf -- '---\nid: spec-proef\nkop: Proef\nvolgorde: 16\nstandaard: ja\nvan-toepassing-als: altijd\nproductie-poort: nee\nstatus: actief\n---\n\n'
        geldig_blok; } > "$doel" ;;
  esac

  uitvoer="$("$repo/check" --no-tests "$repo" 2>&1)"
  status=$?

  if [ "$status" -eq 0 ]; then
    fail "S41 — check slaagde bij een kapot registerbestand ($geval)"
  fi
  case "$uitvoer" in
    *nfr/spec-*) ;;
    *) fail "S41 — de melding noemt het betreffende bestand niet ($geval)" ;;
  esac
done

# CRLF-regeleinden mogen een bestand niet onzichtbaar maken. Dat is een aparte
# eis: zo'n bestand is inhoudelijk in orde, dus het hoort gewoon meegenomen te
# worden — niet stil overgeslagen omdat de frontmatter niet herkend wordt.
repo="$SANDBOX/repo-crlf"
mkdir -p "$repo"
(cd "$TEST_REPO_ROOT" && tar --exclude='./.git' -cf - .) | (cd "$repo" && tar -xf -)
{ printf -- '---\nid: spec-proef\nkop: Proef\nvolgorde: 16\nstandaard: ja\nvan-toepassing-als: altijd\nproductie-poort: nee\nstatus: actief\n---\n\n'
  geldig_blok; } | sed 's/$/\r/' > "$repo/nfr/spec-proef.md"

# shellcheck source=../../lib/nfr.sh
. "$repo/lib/nfr.sh"

[ "$(nfr_veld "$repo/nfr/spec-proef.md" id)" = "spec-proef" ] \
  || fail "S41 — CRLF-bestand: het id wordt niet gelezen"
[ "$(nfr_veld "$repo/nfr/spec-proef.md" volgorde)" = "16" ] \
  || fail "S41 — CRLF-bestand: de volgorde wordt niet gelezen"

blok="$SANDBOX/blok-crlf.txt"
nfr_blok "$repo/nfr" > "$blok"
grep -q 'spec-proef' "$blok" || fail "S41 — CRLF-bestand verdween uit het gegenereerde blok"

test_klaar
