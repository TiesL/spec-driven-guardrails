#!/usr/bin/env bash
# S42 — Every reported change shows the question from its own source.
# Covers: F4

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
sandbox_create
trap sandbox_destroy EXIT

# Given: the pending changes of a project, from both sources.
project="$(fresh_project target-project)"
adopt "$project"

output="$SANDBOX/output.txt"
"$TEST_REPO_ROOT/pending-changes.sh" "$project" > "$output" 2>/dev/null

seen=0
while IFS= read -r line; do
  case "$line" in
    '  - '*) ;;
    *) continue ;;
  esac
  id="${line#  - }"; id="${id%% —*}"
  shown="${line#*— }"

  # The expected text comes from the source where this ID is defined.
  expected="$(awk -v search="## $id" '
    $0 == search { in_entry = 1; next }
    in_entry && /\*\*Question:\*\*/ { sub(/.*\*\*Question:\*\* */, ""); print; exit }
    in_entry && /^## / { exit }
  ' "$TEST_REPO_ROOT/CHANGES.md")"
  source="CHANGES.md"
  if [ -z "$expected" ]; then
    # Deliberately not via nfr_question(): that is the function being tested here.
    # If this oracle used that same function, expectation and reality would
    # move together and the test would measure nothing.
    expected="$(awk '
      /^## Question$/ { in_sec = 1; next }
      in_sec && /^## / { exit }
      in_sec { print }
    ' "$TEST_REPO_ROOT/nfr/$id.md" 2>/dev/null | sed '/^$/d' | tr '\n' ' ' | sed 's/ *$//')"
    source="nfr/$id.md"
  fi

  if [ -z "$expected" ]; then
    fail "S42 — no source found for $id"
    continue
  fi
  if [ "$shown" != "$expected" ]; then
    fail "S42 — $id does not show the question from $source"
    echo "    shown:  $shown" >&2
    echo "    expected: $expected" >&2
  fi
  seen=$((seen + 1))
done < "$output"

[ "$seen" -ge 7 ] || fail "S42 — only $seen lines checked; the setup is flawed"

test_done
