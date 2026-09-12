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
project="$(vers_project doelproject)"
adopteer "$project"

uitvoer="$SANDBOX/uitvoer.txt"
"$TEST_REPO_ROOT/pending-changes.sh" "$project" > "$uitvoer" 2>/dev/null

gezien=0
while IFS= read -r regel; do
  case "$regel" in
    '  - '*) ;;
    *) continue ;;
  esac
  id="${regel#  - }"; id="${id%% —*}"
  getoond="${regel#*— }"

  # The expected text comes from the source where this ID is defined.
  verwacht="$(awk -v zoek="## $id" '
    $0 == zoek { in_entry = 1; next }
    in_entry && /\*\*Question:\*\*/ { sub(/.*\*\*Question:\*\* */, ""); print; exit }
    in_entry && /^## / { exit }
  ' "$TEST_REPO_ROOT/CHANGES.md")"
  bron="CHANGES.md"
  if [ -z "$verwacht" ]; then
    # Deliberately not via nfr_vraag(): that is the function being tested here.
    # If this oracle used that same function, expectation and reality would
    # move together and the test would measure nothing.
    verwacht="$(awk '
      /^## Question$/ { in_sec = 1; next }
      in_sec && /^## / { exit }
      in_sec { print }
    ' "$TEST_REPO_ROOT/nfr/$id.md" 2>/dev/null | sed '/^$/d' | tr '\n' ' ' | sed 's/ *$//')"
    bron="nfr/$id.md"
  fi

  if [ -z "$verwacht" ]; then
    fail "S42 — no source found for $id"
    continue
  fi
  if [ "$getoond" != "$verwacht" ]; then
    fail "S42 — $id does not show the question from $bron"
    echo "    getoond:  $getoond" >&2
    echo "    verwacht: $verwacht" >&2
  fi
  gezien=$((gezien + 1))
done < "$uitvoer"

[ "$gezien" -ge 7 ] || fail "S42 — only $gezien lines checked; the setup is flawed"

test_klaar
