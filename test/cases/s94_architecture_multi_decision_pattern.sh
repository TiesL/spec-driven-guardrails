#!/usr/bin/env bash
# S94 — templates/ARCHITECTURE.md documents the multiple-decisions pattern.
# Covers: F1

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sjabloon="$TEST_REPO_ROOT/templates/ARCHITECTURE.md"
[ -f "$sjabloon" ] || { fail "S94 — templates/ARCHITECTURE.md is missing"; test_klaar; }

inhoud="$(cat "$sjabloon")"

# Given/When: the template, as it stands.
# Then: the pattern is documented explicitly, with tennis-invoicing named
# as the concrete, real-world reference (#135) — not left to be
# reinvented by the next project that needs it.
assert_contains "S94 — the multi-decision section exists" "Multiple decisions in one document" "$inhoud"
assert_contains "S94 — tennis-invoicing is named as the concrete example" "tennis-invoicing" "$inhoud"

# And: the single-decision skeleton is unchanged — this is an addition,
# not a restructuring of the existing case (AC2).
for kop in \
  "## The decision" \
  "## Evaluation criteria" \
  "## Options weighed" \
  "## Comparison and choice" \
  "## Architecture requirements that follow from this" \
  "## System boundaries and ownership" \
  "## Dependencies" \
  "## When we would revisit this choice" \
  "## Still open after this document"
do
  if ! printf '%s\n' "$inhoud" | grep -qxF "$kop"; then
    fail "S94 — the single-decision skeleton lost its '$kop' heading"
  fi
done

test_klaar
