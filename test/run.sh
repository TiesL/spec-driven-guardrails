#!/usr/bin/env bash
# test/run.sh — Runs all test cases in test/cases/.
#
# Each test case is a standalone script that sources test/lib.sh and exits
# with status 0 on success. They each run in their own process, so a test
# that redirects its HOME never does so for a following test.
#
# Usage: ./test/run.sh [name fragment]

set -uo pipefail

hier="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
filter="${1:-}"

# Defense in depth. sandbox_guard is opt-in per test case; a test that
# forgets sandbox_create would, without this, write into the real home. By
# already pointing HOME at a sentinel directory here, such a forgotten call
# can land at most there — and that's visible afterward.
# Capturing the real home first: reading it in the same command prefix
# where HOME gets overwritten reads confusingly (SC2097/SC2098).
echte_home="$HOME"
schildwacht="$(mktemp -d)"
trap 'rm -rf "$schildwacht"' EXIT

geslaagd=0
gefaald=0
mislukt=""

for geval in "$hier"/cases/*.sh; do
  [ -e "$geval" ] || continue
  naam="$(basename "$geval" .sh)"
  if [ -n "$filter" ]; then
    case "$naam" in
      *"$filter"*) ;;
      *) continue ;;
    esac
  fi

  echo "  $naam"
  rm -rf "${schildwacht:?}"/*
  if TEST_REAL_HOME="$echte_home" HOME="$schildwacht" bash "$geval"; then
    geslaagd=$((geslaagd + 1))
  else
    gefaald=$((gefaald + 1))
    mislukt="$mislukt $naam"
  fi
  if [ -n "$(ls -A "$schildwacht" 2>/dev/null)" ]; then
    echo "    warning: $naam wrote into HOME without sandbox_create" >&2
  fi
done

echo
if [ "$gefaald" -gt 0 ]; then
  echo "Tests: $geslaagd passed, $gefaald failed —$mislukt" >&2
  exit 1
fi

if [ "$geslaagd" -eq 0 ]; then
  echo "Tests: not a single test case ran — that's not green." >&2
  exit 1
fi

echo "Tests: $geslaagd passed."
