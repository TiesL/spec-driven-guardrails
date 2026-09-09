#!/usr/bin/env bash
# S70 — `CONTEXT.md` is scaffolded as soon as the row is set to `ja`.
# Dekt: F10

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# Given: an already-adopted project whose proces-context-document row is
# set to "ja" (a fresh adoption does not seed it that way — Standaard is
# "vraag" — so this simulates re-adoption after someone later set the row
# to "ja").
project="$(vers_project met-context)"
adopteer "$project"
cat >> "$project/WORKFLOW-ADOPTIE.md" <<'EOF'
| proces-context-document | ja | 2026-01-01 | dit project groeit met genoeg eigen jargon om vast te leggen |
EOF

rm -f "$project/CONTEXT.md"
adopteer "$project"

if [ ! -f "$project/CONTEXT.md" ]; then
  fail "S70 — CONTEXT.md was not scaffolded while the row is set to 'ja'"
  test_klaar
fi

# And: an already-existing copy is never overwritten.
printf 'eigen inhoud, niet aankomen\n' > "$project/CONTEXT.md"
adopteer "$project"
if ! grep -qx 'eigen inhoud, niet aankomen' "$project/CONTEXT.md"; then
  fail "S70 — an existing CONTEXT.md was overwritten"
fi

# And: a project without that row (or set to "nee") gets nothing.
project2="$(vers_project zonder-context)"
adopteer "$project2"
if [ -f "$project2/CONTEXT.md" ]; then
  fail "S70 — CONTEXT.md was scaffolded without the row being set to 'ja'"
fi

# AC2 — write-spec refers to CONTEXT.md and when you update it.
writespec="$TEST_REPO_ROOT/skills/write-spec/SKILL.md"
assert_contains "S70/AC2 — write-spec mentions CONTEXT.md" "CONTEXT.md" "$(cat "$writespec")"
assert_contains "S70/AC2 — write-spec states when you update it" "Update it" "$(cat "$writespec")"

test_klaar
