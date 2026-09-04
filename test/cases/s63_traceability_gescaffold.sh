#!/usr/bin/env bash
# S63 — adopt.sh scaffoldt de traceability-controle, uitvoerbaar en zonder te
# overschrijven.
# Dekt: F13
#
# Een controle die alleen in dit repo bestaat, controleert nergens iets.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# Given: een vers project.
project="$(vers_project vers)"
adopteer "$project"

doel="$project/check-traceability.sh"
[ -f "$doel" ] || { fail "S63 — adopt.sh scaffoldde check-traceability.sh niet"; test_klaar; }
[ -x "$doel" ] || fail "S63 — check-traceability.sh is niet uitvoerbaar"

# And: hij draait in dat verse project zonder te falen. Een scaffold die meteen
# rood staat, wordt bij de eerste aanraking uitgezet.
uitvoer="$("$doel" "$project" 2>&1)"; status=$?
[ "$status" -eq 0 ] || fail "S63 — de gescaffolde controle faalde in een vers project: $uitvoer"

# And: een eigen versie wordt niet overschreven.
echo "#!/usr/bin/env bash" > "$doel"
echo "# eigen variant" >> "$doel"
adopteer "$project"
grep -q 'eigen variant' "$doel" \
  || fail "S63 — adopt.sh overschreef een eigen check-traceability.sh"

test_klaar "S63"
