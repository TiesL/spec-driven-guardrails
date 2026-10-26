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

# #585: the releases section sits before the problem section and holds a table.
rel="$(grep -n -m1 '^## Releases and their themes$' "$readme" | cut -d: -f1)"
prob="$(grep -n -m1 '^## The problem, and the shape of the fix$' "$readme" | cut -d: -f1)"
[ -n "$rel" ] || fail "S34 — README.md has no '## Releases and their themes' section"
[ -n "$prob" ] || fail "S34 — README.md has no '## The problem, and the shape of the fix' section"
[ -z "$rel" ] || [ "$rel" -lt "$prob" ] || fail "S34 — '## Releases and their themes' (line $rel) is not before '## The problem, and the shape of the fix' (line $prob)"
section="$(sed -n "$((${rel:-0} + 1)),$((${prob:-1} - 1))p" "$readme")"
grep -qE '^\|[ -]*---' <<<"$section" \
  || fail "S34 — the releases section has no table"

test_done
