#!/usr/bin/env bash
# S70 — `CONTEXT.md` wordt gescaffold zodra de rij op `ja` staat.
# Dekt: F10

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# Given: een al geadopteerd project waarvan proces-context-document op "ja"
# staat (een verse adoptie seedt hem niet — Standaard is "vraag" — dus dit
# simuleert de her-adoptie nadat iemand de rij later op "ja" heeft gezet).
project="$(vers_project met-context)"
adopteer "$project"
cat >> "$project/WORKFLOW-ADOPTIE.md" <<'EOF'
| proces-context-document | ja | 2026-01-01 | dit project groeit met genoeg eigen jargon om vast te leggen |
EOF

rm -f "$project/CONTEXT.md"
adopteer "$project"

if [ ! -f "$project/CONTEXT.md" ]; then
  fail "S70 — CONTEXT.md werd niet gescaffold terwijl de rij op 'ja' staat"
  test_klaar
fi

# And: een al bestaand exemplaar wordt nooit overschreven.
printf 'eigen inhoud, niet aankomen\n' > "$project/CONTEXT.md"
adopteer "$project"
if ! grep -qx 'eigen inhoud, niet aankomen' "$project/CONTEXT.md"; then
  fail "S70 — een bestaand CONTEXT.md werd overschreven"
fi

# And: een project zonder die rij (of op "nee") krijgt niets.
project2="$(vers_project zonder-context)"
adopteer "$project2"
if [ -f "$project2/CONTEXT.md" ]; then
  fail "S70 — CONTEXT.md werd gescaffold zonder dat de rij op 'ja' staat"
fi

# AC2 — write-spec verwijst naar CONTEXT.md en wanneer je het bijwerkt.
writespec="$TEST_REPO_ROOT/skills/write-spec/SKILL.md"
assert_contains "S70/AC2 — write-spec noemt CONTEXT.md" "CONTEXT.md" "$(cat "$writespec")"
assert_contains "S70/AC2 — write-spec zegt wanneer je hem bijwerkt" "Update it" "$(cat "$writespec")"

test_klaar
