#!/usr/bin/env bash
# S41 — A broken register file does not silently disappear.
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

# Each case is a fully usable file with a single defect. Without a check,
# such a file disappears from all consumers at once, and then the
# drift check sees nothing: both sides are missing it after all.
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
    fail "S41 — check succeeded on a broken register file ($geval)"
  fi
  case "$uitvoer" in
    *nfr/spec-*) ;;
    *) fail "S41 — the message does not name the file in question ($geval)" ;;
  esac
done

# CRLF line endings must not make a file invisible. That is a separate
# requirement: such a file is fine content-wise, so it should just be
# included — not silently skipped because the frontmatter is not recognized.
repo="$SANDBOX/repo-crlf"
mkdir -p "$repo"
(cd "$TEST_REPO_ROOT" && tar --exclude='./.git' -cf - .) | (cd "$repo" && tar -xf -)
{ printf -- '---\nid: spec-proef\nkop: Proef\nvolgorde: 16\nstandaard: ja\nvan-toepassing-als: altijd\nproductie-poort: nee\nstatus: actief\n---\n\n'
  geldig_blok; } | sed 's/$/\r/' > "$repo/nfr/spec-proef.md"

# shellcheck source=../../lib/nfr.sh
. "$repo/lib/nfr.sh"

[ "$(nfr_veld "$repo/nfr/spec-proef.md" id)" = "spec-proef" ] \
  || fail "S41 — CRLF file: the id is not being read"
[ "$(nfr_veld "$repo/nfr/spec-proef.md" volgorde)" = "16" ] \
  || fail "S41 — CRLF file: the order is not being read"

blok="$SANDBOX/blok-crlf.txt"
nfr_blok "$repo/nfr" > "$blok"
grep -q 'spec-proef' "$blok" || fail "S41 — CRLF file disappeared from the generated block"

test_klaar
