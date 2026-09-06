#!/usr/bin/env bash
# T3, T5 — schakel 2 (scenario -> issue) als poort in pre-merge-review (W20).
# Dekt: F13
#
# "Wordt dit scenario door een issue genoemd" is een strikte veldmatch: alleen
# het **Dekt:**-veld van een issue telt, een ID dat toevallig in een zin
# voorkomt niet (T5). T3: een ongedekt scenario wordt expliciet genoemd.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

script="$TEST_REPO_ROOT/skills/pre-merge-review/scenario-poort.sh"
[ -x "$script" ] || { fail "T3/T5 — skills/pre-merge-review/scenario-poort.sh ontbreekt of is niet uitvoerbaar"; test_klaar; }

sandbox_create
trap sandbox_destroy EXIT

project="$SANDBOX/project"
mkdir -p "$project"
cat > "$project/TEST-SCENARIOS.md" <<'EOF'
### S1 — wordt alleen in lopende tekst genoemd, niet in een Dekt-veld

### S2b — staat wél in een Dekt-veld, met staart-letter

### S3 — wordt door geen enkel issue genoemd
EOF

# Eén issue: noemt S1 losjes in de body (geen verwijzing), dekt S2b wel via
# het daarvoor bestemde veld. S3 komt in geen enkele body voor.
fakebin="$(fake_gh_bin '
case "$*" in
  "issue list --state all --limit 500 --json body --jq .[].body")
    printf "%s\n" "we hebben inmiddels s1 varianten getest"
    printf "%s\n" "**Dekt:** S2b"
    exit 0 ;;
esac
exit 1
')"

uitvoer="$(PATH="$fakebin:$PATH" "$script" "$project" 2>&1)"; status=$?
[ "$status" -eq 0 ] || fail "T3/T5 — de poort faalde onverwacht (exit $status): $uitvoer"

# T3 — S3 is ongedekt en wordt expliciet genoemd.
assert_contains "T3 — S3 wordt genoemd als ongedekt" "S3" "$uitvoer"

# T5 — de losse tekstvermelding van s1 telt niet als dekking: S1 blijft dus
# ook ongedekt.
assert_contains "T5 — S1 blijft ongedekt (lopende tekst telt niet)" "S1" "$uitvoer"

# T5 — S2b telt wél, via het veld: geen "S2b ... ongedekt"-regel.
case "$uitvoer" in
  *"S2b wordt door geen enkel issue gedekt"*)
    fail "T5 — S2b (gedekt via het Dekt-veld) werd toch als ongedekt gemeld" ;;
esac

# AC4 — de poort faalt niet blokkerend zonder gh.
padzondergh="$(pad_zonder_gh)"
uitvoer_geengh="$(PATH="$padzondergh" "$script" "$project" 2>&1)"; status_geengh=$?
[ "$status_geengh" -eq 0 ] || fail "AC4 — zonder gh gaf de poort exit $status_geengh in plaats van 0"
assert_contains "AC4 — er verschijnt een waarschuwing zonder gh" "waarschuwing" "$uitvoer_geengh"

test_klaar
