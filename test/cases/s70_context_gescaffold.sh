#!/usr/bin/env bash
# S70 — `CONTEXT.md` is scaffolded as soon as the row is set to `yes`.
# Covers: F10

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# Given: an already-adopted project whose process-context-document row is
# set to "yes" (a fresh adoption does not seed it that way — Standaard is
# "vraag" — so this simulates re-adoption after someone later set the row
# to "yes").
project="$(vers_project met-context)"
adopteer "$project"
cat >> "$project/WORKFLOW-ADOPTION.md" <<'EOF'
| process-context-document | yes | 2026-01-01 | dit project groeit met genoeg eigen jargon om vast te leggen |
EOF

rm -f "$project/CONTEXT.md"
adopteer "$project"

if [ ! -f "$project/CONTEXT.md" ]; then
  fail "S70 — CONTEXT.md was not scaffolded while the row is set to 'yes'"
  test_klaar
fi

# And: an already-existing copy is never overwritten.
printf 'eigen inhoud, niet aankomen\n' > "$project/CONTEXT.md"
adopteer "$project"
if ! grep -qx 'eigen inhoud, niet aankomen' "$project/CONTEXT.md"; then
  fail "S70 — an existing CONTEXT.md was overwritten"
fi

# And: a project without that row (or set to "no") gets nothing.
project2="$(vers_project zonder-context)"
adopteer "$project2"
if [ -f "$project2/CONTEXT.md" ]; then
  fail "S70 — CONTEXT.md was scaffolded without the row being set to 'yes'"
fi

# And: the same holds for the pre-migration format (W42/#114) — a project
# still on the old filename/ID/value also gets CONTEXT.md scaffolded,
# since that scaffold shouldn't wait on an unrelated migration.
project3="$(vers_project met-context-oud)"
cat > "$project3/WORKFLOW-ADOPTIE.md" <<'EOF'
# Adoption of shared workflow changes

| Change | Answer | Date | Notes |
|---|---|---|---|
| proces-context-document | ja | 2026-01-01 | dit project groeit met genoeg eigen jargon om vast te leggen |
EOF
SPEC_DRIVEN_GUARDRAILS_DIR="$TEST_REPO_ROOT" "$TEST_REPO_ROOT/adopt.sh" "$project3" >/dev/null 2>&1
if [ ! -f "$project3/CONTEXT.md" ]; then
  fail "S70 — pre-migration format: CONTEXT.md was not scaffolded while the row is set to 'ja'"
fi

# AC2 — write-spec refers to CONTEXT.md and when you update it.
writespec="$TEST_REPO_ROOT/skills/write-spec/SKILL.md"
assert_contains "S70/AC2 — write-spec mentions CONTEXT.md" "CONTEXT.md" "$(cat "$writespec")"
assert_contains "S70/AC2 — write-spec states when you update it" "Update it" "$(cat "$writespec")"

test_klaar
