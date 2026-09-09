#!/usr/bin/env bash
# S63 — adopt.sh scaffolds the traceability check, executable and without
# overwriting.
# Dekt: F13
#
# A check that only exists in this repo does not check anything anywhere.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# Given: a fresh project.
project="$(vers_project vers)"
adopteer "$project"

doel="$project/check-traceability.sh"
[ -f "$doel" ] || { fail "S63 — adopt.sh did not scaffold check-traceability.sh"; test_klaar; }
[ -x "$doel" ] || fail "S63 — check-traceability.sh is not executable"

# And: it runs in that fresh project without failing. A scaffold that is red
# right away gets switched off at the first touch.
uitvoer="$("$doel" "$project" 2>&1)"; status=$?
[ "$status" -eq 0 ] || fail "S63 — the scaffolded check failed in a fresh project: $uitvoer"

# And: a customized version is not overwritten.
echo "#!/usr/bin/env bash" > "$doel"
echo "# eigen variant" >> "$doel"
adopteer "$project"
grep -q 'eigen variant' "$doel" \
  || fail "S63 — adopt.sh overwrote a customized check-traceability.sh"

test_klaar "S63"
