#!/usr/bin/env bash
# S5 — Generator and checked-in template do not drift apart.
# Covers: F4

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

repo="$(sandbox_copy_repo)"

# Beforehand: on the checked-in state, check should not complain here.
if ! "$repo/check" --no-tests "$repo" >/dev/null 2>&1; then
  fail "S5 — check already complains on the unchanged state"
fi

# Given: an nfr/*.md whose Guidance has been changed without regenerating.
target="$repo/nfr/spec-security.md"
if [ ! -f "$target" ]; then
  fail "S5 — nfr/spec-security.md is missing"
  test_done
fi

python3 - "$target" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
kop = "## Guidance"
i = s.index(kop) + len(kop)
open(p, "w").write(s[:i] + "\nEen bewust afwijkende invulhulp voor deze test.\n")
PY

# When: ./check runs.
output="$("$repo/check" --no-tests "$repo" 2>&1)"
status=$?

# Then: exit != 0, with the relevant NFR in the message.
if [ "$status" -eq 0 ]; then
  fail "S5 — check succeeded while register and template drift apart"
fi
assert_contains "S5" "spec-security" "$output"

test_done
