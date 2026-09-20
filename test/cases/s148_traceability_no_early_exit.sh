#!/usr/bin/env bash
# S148 — check-traceability.sh's "PRD.md has no ID headings" warning
# doesn't silently drop the other checks that don't depend on it (#275).
# Covers: F13

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

script="$TEST_REPO_ROOT/check-traceability.sh"
[ -x "$script" ] || { fail "S148 — check-traceability.sh is missing or not executable"; test_done; }

# Case 1 (AC1): a prose-only PRD.md (no ID headings) must not mask a
# leftover Dekt: field in TEST-SCENARIOS.md — the exact reproduction from
# an adopted project's own pre-merge-review.
project1="$SANDBOX/dekt-leftover"
mkdir -p "$project1"
cat > "$project1/PRD.md" <<'EOF'
# PRD

Just prose here, no ID headings at all.
EOF
cat > "$project1/TEST-SCENARIOS.md" <<'EOF'
# Test scenarios

**Dekt:** F1
EOF
output1="$("$script" "$project1" 2>&1)"; status1=$?
[ "$status1" -ne 0 ] || fail "S148 — a Dekt: leftover was not reported when PRD.md has no ID headings, got: $output1"
assert_contains "S148 — the Dekt: leftover is reported" "pre-migration Dekt" "$output1"

# Case 2 (AC3): the "no ID headings" warning itself still appears,
# unchanged — this fix stops it from masking other checks, not removes it.
assert_contains "S148 — the no-ID-headings warning still appears" "PRD.md has no ID headings" "$output1"

# Case 3 (AC2): PRD.md's own Covers-token resolution against
# TEST-SCENARIOS.md's IDs still runs even without PRD ID headings — a
# bad token here is still reported.
project2="$SANDBOX/prd-bad-covers-token"
mkdir -p "$project2"
cat > "$project2/PRD.md" <<'EOF'
# PRD

Just prose here, no ID headings.

**Covers:** S999
EOF
cat > "$project2/TEST-SCENARIOS.md" <<'EOF'
# Test scenarios

### S1 — Something
**Covers:** F1
EOF
output2="$("$script" "$project2" 2>&1)"; status2=$?
[ "$status2" -ne 0 ] || fail "S148 — PRD.md's own bad Covers: token was not reported without PRD ID headings, got: $output2"
assert_contains "S148 — names the unresolved token" "S999" "$output2"

# And: a scenario's own Covers: token pointing at a PRD functionality is
# NOT reported as broken just because PRD.md has no ID headings — that
# direction is genuinely inapplicable without prd_ids and stays skipped
# (skipping it specifically, not via the removed early exit).
case "$output2" in
  *"S1"*"doesn't exist in PRD.md"*) fail "S148 — a scenario's PRD-facing Covers: token was wrongly checked against an empty PRD-ID set, got: $output2" ;;
  *) : ;;
esac

test_done
