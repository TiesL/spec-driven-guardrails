#!/usr/bin/env bash
# S34 — The README describes the current structure.
# Covers: F16

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

readme="$TEST_REPO_ROOT/README.md"

for map in 'skills/' 'hooks/' 'lib/' 'nfr/' 'test/' 'CHANGES-ARCHIEF.md'; do
  if ! grep -qF "\`$map\`" "$readme"; then
    fail "S34 — README.md does not mention \`$map\` in the contents table"
  fi
done

# "check" also appears loose in running text; the table row itself is what counts.
if ! grep -qE '^\| `check` \|' "$readme"; then
  fail "S34 — README.md has no table row for \`check\`"
fi

if ! grep -q 'fifteen non-functional questions' "$readme"; then
  fail "S34 — README.md does not mention 'fifteen non-functional questions'"
fi
if grep -q 'five non-functional questions' "$readme"; then
  fail "S34 — README.md still mentions 'five non-functional questions' (outdated since 4821bac)"
fi

test_done
