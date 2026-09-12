#!/usr/bin/env bash
# R5 — NFR list stays 1-to-1 in sync.
# Covers: F4

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

nfr_map="$TEST_REPO_ROOT/nfr"
template="$TEST_REPO_ROOT/templates/PRD.md"

if [ ! -d "$nfr_map" ]; then
  fail "R5 — nfr/ is missing"
  test_done
fi

# Given: the NFR IDs from the register and the ###-subsections in the template.
from_register="$SANDBOX/register.txt"
from_template="$SANDBOX/template.txt"

# The register supplies the id/heading pair from the same file — no normalization
# from "spec-compliance" to "Compliance en auditeerbaarheid" needed.
for file in "$nfr_map"/*.md; do
  [ -e "$file" ] || continue
  id="$(awk -F': *' '/^id:/{print $2; exit}' "$file")"
  kop="$(awk -F': *' '/^heading:/{print $2; exit}' "$file")"
  status="$(awk -F': *' '/^status:/{print $2; exit}' "$file")"
  [ "$status" = "retired" ] && continue
  if [ -z "$id" ] || [ -z "$kop" ]; then
    fail "R5 — $(basename "$file") is missing an id or heading"
    continue
  fi
  printf '%s\t%s\n' "$id" "$kop" >> "$from_register"
done
sort -o "$from_register" "$from_register" 2>/dev/null || : > "$from_register"

# The template supplies the headings from the generated block, with the ID from
# the HTML comment that the generator adds alongside it.
awk '
  /<!-- nfr-block:begin/ { in_blok = 1; next }
  /<!-- nfr-block:end/  { in_blok = 0 }
  in_blok && /^### /     { kop = substr($0, 5) }
  in_blok && /<!-- nfr:/ { id = $0; sub(/.*<!-- nfr: */, "", id); sub(/ *-->.*/, "", id); print id "\t" kop }
' "$template" | sort > "$from_template"

# Then: exact 1-to-1 match, no missing or excess side.
count="$(grep -c . "$from_register" 2>/dev/null || echo 0)"
[ "$count" -eq 15 ] || fail "R5 — $count active NFRs in the register, expected 15"

if ! diff -u "$from_register" "$from_template" >/dev/null 2>&1; then
  fail "R5 — register and template are out of sync:"
  diff -u "$from_register" "$from_template" >&2
fi

# And: no more spec-* entries in CHANGES.md — the register is the sole source.
if grep -q '^## spec-' "$TEST_REPO_ROOT/CHANGES.md"; then
  fail "R5 — CHANGES.md still contains spec-* entries"
  grep -n '^## spec-' "$TEST_REPO_ROOT/CHANGES.md" >&2
fi

test_done
