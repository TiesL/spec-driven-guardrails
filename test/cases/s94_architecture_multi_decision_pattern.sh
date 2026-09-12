#!/usr/bin/env bash
# S94 — templates/ARCHITECTURE.md documents the multiple-decisions pattern.
# Covers: F1

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

template="$TEST_REPO_ROOT/templates/ARCHITECTURE.md"
[ -f "$template" ] || { fail "S94 — templates/ARCHITECTURE.md is missing"; test_done; }

content="$(cat "$template")"

# Given/When: the template, as it stands.
# Then: the pattern is documented explicitly, with tennis-invoicing named
# as the concrete, real-world reference (#135) — not left to be
# reinvented by the next project that needs it.
assert_contains "S94 — the multi-decision section exists" "Multiple decisions in one document" "$content"
assert_contains "S94 — tennis-invoicing is named as the concrete example" "tennis-invoicing" "$content"

# And: the single-decision skeleton is unchanged — this is an addition,
# not a restructuring of the existing case (AC2). Checked as an exact,
# ordered sequence, not just presence: a reorder is also a
# restructuring, and presence-only checks (found during review) would
# miss one heading silently swapping places with another.
expected="$(mktemp)"
actual="$(mktemp)"
trap 'rm -f "$expected" "$actual" "$actual.tmp"' EXIT
cat > "$expected" <<'EOF'
## The decision
## Evaluation criteria
## Options weighed
## Comparison and choice
## Architecture requirements that follow from this
## System boundaries and ownership
## Dependencies
## When we would revisit this choice
## Still open after this document
EOF
printf '%s\n' "$content" | grep -E '^## ' > "$actual"

# The new "Multiple decisions" section is expected, additive content —
# strip it out before comparing, since this check is about the
# single-decision skeleton's own headings only, not the whole file.
grep -vxF '## Multiple decisions in one document' "$actual" > "$actual.tmp"
mv "$actual.tmp" "$actual"

if ! diff -u "$expected" "$actual" >/dev/null 2>&1; then
  fail "S94 — the single-decision skeleton's headings changed (missing, renamed, or reordered):"
  diff -u "$expected" "$actual" >&2
fi

test_done
