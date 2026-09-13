#!/usr/bin/env bash
# test/run.sh — Runs all test cases in test/cases/.
#
# Each test case is a standalone script that sources test/lib.sh and exits
# with status 0 on success. They each run in their own process, so a test
# that redirects its HOME never does so for a following test.
#
# Usage: ./test/run.sh [name fragment]

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
filter="${1:-}"

# Defense in depth. sandbox_guard is opt-in per test case; a test that
# forgets sandbox_create would, without this, write into the real home. By
# already pointing HOME at a sentinel directory here, such a forgotten call
# can land at most there — and that's visible afterward.
# Capturing the real home first: reading it in the same command prefix
# where HOME gets overwritten reads confusingly (SC2097/SC2098).
real_home="$HOME"
sentinel="$(mktemp -d)"
trap 'rm -rf "$sentinel"' EXIT

passed=0
failed=0
failed_names=""

for case_file in "$here"/cases/*.sh; do
  [ -e "$case_file" ] || continue
  name="$(basename "$case_file" .sh)"
  if [ -n "$filter" ]; then
    case "$name" in
      *"$filter"*) ;;
      *) continue ;;
    esac
  fi

  echo "  $name"
  rm -rf "${sentinel:?}"/*
  if TEST_REAL_HOME="$real_home" HOME="$sentinel" bash "$case_file"; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
    failed_names="$failed_names $name"
  fi
  if [ -n "$(ls -A "$sentinel" 2>/dev/null)" ]; then
    echo "    warning: $name wrote into HOME without sandbox_create" >&2
  fi
done

echo
if [ "$failed" -gt 0 ]; then
  echo "Tests: $passed passed, $failed failed —$failed_names" >&2
  exit 1
fi

if [ "$passed" -eq 0 ]; then
  echo "Tests: not a single test case ran — that's not green." >&2
  exit 1
fi

echo "Tests: $passed passed."
