#!/usr/bin/env bash
# T1, T2, S30 — link 1 of the traceability chain, offline.
# Covers: F13
#
# The design from W17: do not hardcode F/S. Collect ID tokens from the headings
# of PRD.md and TEST-SCENARIOS.md and check that every Covers: token resolves in
# the other set. A check that fails on day one in one of the four projects gets
# switched off on day two — hence a PRD without IDs warns instead of failing.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

script="$TEST_REPO_ROOT/templates/check-traceability.sh"
[ -x "$script" ] || { fail "T1 — templates/check-traceability.sh is missing or not executable"; test_done; }

sandbox_create
trap sandbox_destroy EXIT

# Builds a project with the given PRD and scenario content.
build() {
  local name="$1" prd="$2" scen="$3"
  local path="$SANDBOX/$name"
  mkdir -p "$path"
  printf '%s\n' "$prd" > "$path/PRD.md"
  printf '%s\n' "$scen" > "$path/TEST-SCENARIOS.md"
  echo "$path"
}

# T1 — full chain, everything covered.
p="$(build t1 \
'## Functionality

### F1 — something' \
'### S1 — expected behavior
**Covers:** F1

### S2 — what goes wrong
**Covers:** F1')"
output="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -eq 0 ] || fail "T1 — full coverage gave exit $status: $output"

# T2 — a feature without a scenario fails, by name.
p="$(build t2 \
'### F1 — covered

### F2 — uncovered' \
'### S1 — something
**Covers:** F1')"
output="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "T2 — uncovered F2 gave exit 0"
assert_contains "T2 — the message names F2" "F2" "$output"

# S30 — duplicate IDs and an unknown token, reported separately.
p="$(build s30 \
'### F1 — something' \
'### S1 — first
**Covers:** F1

### S1 — second, same ID
**Covers:** F1

### S2 — refers nowhere
**Covers:** F9')"
output="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "S30 — duplicate ID and unknown token gave exit 0"
assert_contains "S30 — the duplicate ID is reported" "S1" "$output"
assert_contains "S30 — the unresolved token is reported" "F9" "$output"

# AC5 — a PRD without any ID warns and does not fail. tennis-invoicing is this
# case; if the script failed there, it would get switched off immediately.
p="$(build ac5 \
'## Functionality

This project describes its functionality in prose, without ID headings.' \
'### S1 — something
**Covers:**')"
output="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -eq 0 ] || fail "AC5 — prefix-less PRD gave exit $status instead of a warning"
assert_contains "AC5 — a warning appears" "warning" "$output"

# S62 — a project not yet using the convention warns and does not fail.
# All four existing projects are this case on the day it is introduced.
p="$(build s62 \
'### F1 — something

### F2 — something else' \
'### S1 — something, without a coverage field
- Given: ...')"
output="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -eq 0 ] || fail "S62 — project without Covers: fields gave exit $status instead of a warning"
assert_contains "S62 — a warning appears" "warning" "$output"
case "$output" in
  *F1*|*F2*) fail "S62 — it still reported uncovered items: $output" ;;
esac

# And once the first reference is there, it does enforce — otherwise a
# project with a single Covers: field could leave the rest unpunished.
p="$(build s62b \
'### F1 — covered

### F2 — uncovered' \
'### S1 — something
**Covers:** F1')"
output="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "S62 — with one Covers: field, F2 was not enforced"
assert_contains "S62 — F2 is reported once the convention is in use" "F2" "$output"

# T5 — only the field counts. An ID in running prose is not a reference, and
# neither is a line that does not start with the field. Without this check
# any sentence that accidentally mentions an ID would produce coverage that
# is not really there.
p="$(build t5 \
'### F1 — covered

### F2 — not covered, only mentioned in prose' \
'### S1 — something
**Covers:** F1
- Given: this scenario mentions Covers: F2 in running text, which is not a reference
- When: the script runs
- Then: F2 does not count as covered')"
output="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "T5 — 'Covers: F2' in running prose counted as coverage"
assert_contains "T5 — F2 stays uncovered" "F2" "$output"

# Prefix-agnostic. This is the core of decision c from W17: tennis-admin numbers
# its scenarios R/A/B/P and uses OP for open items. A script keyed to F/S would
# be unusable there from day one — and that cannot be demonstrated with F/S
# test data alone.
p="$(build prefix-free \
'### R1 — a requirement with its own prefix

### OP4 — an open point, two leading letters' \
'### B7 — scenario with yet another prefix
**Covers:** R1

### P2b — and one with a trailing letter
**Covers:** OP4')"
output="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -eq 0 ] || fail "prefix-agnostic — R/OP/B/P was not recognized: $output"

# And a reference to a non-existent ID with its own prefix is reported,
# so "approve everything" does not pass as prefix-agnostic.
p="$(build prefix-free-broken \
'### R1 — exists' \
'### B7 — refers nowhere
**Covers:** R9')"
output="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "prefix-agnostic — unknown R9 was not reported"
assert_contains "prefix-agnostic — R9 is in the message" "R9" "$output"

# A placeholder from the template is not a reference. A freshly scaffolded
# project carries `**Covers:** <F1>`; if the check fails on that, it would be
# switched off on first use.
p="$(build placeholder \
'### F1 — something' \
'### S1 — fresh from the template
**Covers:** <F1>')"
output="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -eq 0 ] || fail "placeholder — <F1> was treated as a reference: $output"

# A Covers: token with a trailing letter. a2t-emails has an S2b, and a
# grammar that rejects that is immediately unusable there. Without this case
# it cannot be shown that the script accepts the trailing letter — a test
# with only S1/S2 leaves a stricter grammar untouched.
p="$(build trailing-letter \
'### F1 — something' \
'### S2b — a scenario with a trailing letter
**Covers:** F1')"
output="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -eq 0 ] || fail "trailing-letter — S2b was not recognized as a valid ID: $output"

p="$(build trailing-letter-broken \
'### F1 — something

### F2 — uncovered' \
'### S1 — refers to a non-existent ID with a trailing letter
**Covers:** F1, F2b')"
output="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "trailing-letter — unknown F2b was not reported"
assert_contains "trailing-letter — F2b is in the message" "F2b" "$output"

# The other direction: a Covers: field in PRD.md refers to a scenario. Both
# directions are checked; without this case, the check on the PRD side
# could be silently removed.
p="$(build other-way \
'### F1 — refers to a scenario that does not exist
**Covers:** S9' \
'### S1 — something
**Covers:** F1')"
output="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "other direction — unknown S9 in PRD.md was not reported"
assert_contains "other direction — S9 is in the message" "S9" "$output"

# Exact match, not a substring. Without `grep -qx`, a dangling reference
# to F1 would silently resolve against an existing F123 — and then the
# check would report "fine" while no F1 exists anywhere.
p="$(build substring \
'### F123 — the only item' \
'### S1 — covers F123
**Covers:** F123

### S2 — dangling reference that is a substring of F123
**Covers:** F1')"
output="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "substring — F1 resolved against F123"
assert_contains "substring — F1 is in the message" "F1" "$output"

# A duplicate that is not next to its twin. Without sorting before
# looking for duplicates, `uniq -d` only sees adjacent lines, and then
# exactly the realistic case slips through: a copy-paste error further down
# in a large file.
p="$(build duplicate-apart \
'### F1 — something' \
'### S1 — first
**Covers:** F1

### S2 — in between
**Covers:** F1

### S1 — the same ID, far from the first
**Covers:** F1')"
output="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "duplicate-apart — non-adjacent duplicate S1 was missed"
assert_contains "duplicate-apart — S1 is in the message" "S1" "$output"

# A broken token is reported, not silently filtered out. Otherwise the
# check would promise that every token resolves while it precisely fails
# to see the typos.
p="$(build broken-token \
'### F1 — something

### F2 — something' \
'### S1 — with a typo in between
**Covers:** F1, F-2, F2')"
output="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "broken token — 'F-2' was silently filtered out"
assert_contains "broken token — F-2 is in the message" "F-2" "$output"

# Spaces instead of commas produce one unusable token. That too must be
# reported, since otherwise the field looks filled in while covering nothing.
p="$(build space-separated \
'### F1 — something

### F2 — something' \
'### S1 — spaces instead of a comma
**Covers:** F1 F2')"
output="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "space-separated — 'F1 F2' was silently filtered out"

# S87 — a leftover **Dekt:** field (pre-Covers:-cutover, W42/#114) is
# reported by name, neither parsed as a valid Covers: reference nor
# silently treated as "this project doesn't use the convention yet".
p="$(build leftover-dekt \
'### F1 — something' \
'### S1 — still on the old field
**Dekt:** F1')"
output="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "S87 — a leftover Dekt: field gave exit 0"
assert_contains "S87 — the leftover field is named" "Dekt:" "$output"
assert_contains "S87 — it points at #114" "#114" "$output"
case "$output" in
  *"doesn't carry any Covers: fields yet"*)
    fail "S87 — a leftover Dekt: field was treated as 'convention not in use yet'" ;;
esac

test_done "T1/T2/T5/S30/S62/S87"
