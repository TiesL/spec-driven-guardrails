#!/usr/bin/env bash
# T1, T2, S30 — link 1 of the traceability chain, offline.
# Dekt: F13
#
# The design from W17: do not hardcode F/S. Collect ID tokens from the headings
# of PRD.md and TEST-SCENARIOS.md and check that every Dekt: token resolves in
# the other set. A check that fails on day one in one of the four projects gets
# switched off on day two — hence a PRD without IDs warns instead of failing.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

script="$TEST_REPO_ROOT/templates/check-traceability.sh"
[ -x "$script" ] || { fail "T1 — templates/check-traceability.sh is missing or not executable"; test_klaar; }

sandbox_create
trap sandbox_destroy EXIT

# Builds a project with the given PRD and scenario content.
bouw() {
  local naam="$1" prd="$2" scen="$3"
  local pad="$SANDBOX/$naam"
  mkdir -p "$pad"
  printf '%s\n' "$prd" > "$pad/PRD.md"
  printf '%s\n' "$scen" > "$pad/TEST-SCENARIOS.md"
  echo "$pad"
}

# T1 — full chain, everything covered.
p="$(bouw t1 \
'## Functionaliteit

### F1 — iets' \
'### S1 — verwacht gedrag
**Dekt:** F1

### S2 — wat er misgaat
**Dekt:** F1')"
uitvoer="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -eq 0 ] || fail "T1 — full coverage gave exit $status: $uitvoer"

# T2 — a feature without a scenario fails, by name.
p="$(bouw t2 \
'### F1 — gedekt

### F2 — ongedekt' \
'### S1 — iets
**Dekt:** F1')"
uitvoer="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "T2 — uncovered F2 gave exit 0"
assert_contains "T2 — the message names F2" "F2" "$uitvoer"

# S30 — duplicate IDs and an unknown token, reported separately.
p="$(bouw s30 \
'### F1 — iets' \
'### S1 — eerste
**Dekt:** F1

### S1 — tweede, zelfde ID
**Dekt:** F1

### S2 — verwijst nergens heen
**Dekt:** F9')"
uitvoer="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "S30 — duplicate ID and unknown token gave exit 0"
assert_contains "S30 — the duplicate ID is reported" "S1" "$uitvoer"
assert_contains "S30 — the unresolved token is reported" "F9" "$uitvoer"

# AC5 — a PRD without any ID warns and does not fail. tennis-invoicing is this
# case; if the script failed there, it would get switched off immediately.
p="$(bouw ac5 \
'## Functionaliteit

Dit project beschrijft zijn functionaliteit in proza, zonder ID-koppen.' \
'### S1 — iets
**Dekt:**')"
uitvoer="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -eq 0 ] || fail "AC5 — prefix-less PRD gave exit $status instead of a warning"
assert_contains "AC5 — a warning appears" "warning" "$uitvoer"

# S62 — a project not yet using the convention warns and does not fail.
# All four existing projects are this case on the day it is introduced.
p="$(bouw s62 \
'### F1 — iets

### F2 — nog iets' \
'### S1 — iets, zonder dekkingsveld
- Given: ...')"
uitvoer="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -eq 0 ] || fail "S62 — project without Dekt: fields gave exit $status instead of a warning"
assert_contains "S62 — a warning appears" "warning" "$uitvoer"
case "$uitvoer" in
  *F1*|*F2*) fail "S62 — it still reported uncovered items: $uitvoer" ;;
esac

# And once the first reference is there, it does enforce — otherwise a
# project with a single Dekt: field could leave the rest unpunished.
p="$(bouw s62b \
'### F1 — gedekt

### F2 — ongedekt' \
'### S1 — iets
**Dekt:** F1')"
uitvoer="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "S62 — with one Dekt: field, F2 was not enforced"
assert_contains "S62 — F2 is reported once the convention is in use" "F2" "$uitvoer"

# T5 — only the field counts. An ID in running prose is not a reference, and
# neither is a line that does not start with the field. Without this check
# any sentence that accidentally mentions an ID would produce coverage that
# is not really there.
p="$(bouw t5 \
'### F1 — gedekt

### F2 — niet gedekt, wordt alleen in proza genoemd' \
'### S1 — iets
**Dekt:** F1
- Given: dit scenario noemt Dekt: F2 in lopende tekst, wat geen verwijzing is
- When: het script draait
- Then: F2 telt niet als gedekt')"
uitvoer="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "T5 — 'Dekt: F2' in running prose counted as coverage"
assert_contains "T5 — F2 stays uncovered" "F2" "$uitvoer"

# Prefix-agnostic. This is the core of decision c from W17: tennis-admin numbers
# its scenarios R/A/B/P and uses OP for open items. A script keyed to F/S would
# be unusable there from day one — and that cannot be demonstrated with F/S
# test data alone.
p="$(bouw prefixvrij \
'### R1 — een eis met een eigen prefix

### OP4 — een open punt, twee beginletters' \
'### B7 — scenario met weer een ander prefix
**Dekt:** R1

### P2b — en een met een staart-letter
**Dekt:** OP4')"
uitvoer="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -eq 0 ] || fail "prefix-agnostic — R/OP/B/P was not recognized: $uitvoer"

# And a reference to a non-existent ID with its own prefix is reported,
# so "approve everything" does not pass as prefix-agnostic.
p="$(bouw prefixvrij-fout \
'### R1 — bestaat' \
'### B7 — verwijst nergens heen
**Dekt:** R9')"
uitvoer="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "prefix-agnostic — unknown R9 was not reported"
assert_contains "prefix-agnostic — R9 is in the message" "R9" "$uitvoer"

# A placeholder from the template is not a reference. A freshly scaffolded
# project carries `**Dekt:** <F1>`; if the check fails on that, it would be
# switched off on first use.
p="$(bouw placeholder \
'### F1 — iets' \
'### S1 — vers uit het sjabloon
**Dekt:** <F1>')"
uitvoer="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -eq 0 ] || fail "placeholder — <F1> was treated as a reference: $uitvoer"

# A Dekt: token with a trailing letter. a2t-emails has an S2b, and a
# grammar that rejects that is immediately unusable there. Without this case
# it cannot be shown that the script accepts the trailing letter — a test
# with only S1/S2 leaves a stricter grammar untouched.
p="$(bouw staartletter \
'### F1 — iets' \
'### S2b — een scenario met staart-letter
**Dekt:** F1')"
uitvoer="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -eq 0 ] || fail "trailing-letter — S2b was not recognized as a valid ID: $uitvoer"

p="$(bouw staartletter-fout \
'### F1 — iets

### F2 — ongedekt' \
'### S1 — verwijst naar een niet-bestaand ID met staart-letter
**Dekt:** F1, F2b')"
uitvoer="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "trailing-letter — unknown F2b was not reported"
assert_contains "trailing-letter — F2b is in the message" "F2b" "$uitvoer"

# The other direction: a Dekt: field in PRD.md refers to a scenario. Both
# directions are checked; without this case, the check on the PRD side
# could be silently removed.
p="$(bouw andersom \
'### F1 — verwijst naar een scenario dat niet bestaat
**Dekt:** S9' \
'### S1 — iets
**Dekt:** F1')"
uitvoer="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "other direction — unknown S9 in PRD.md was not reported"
assert_contains "other direction — S9 is in the message" "S9" "$uitvoer"

# Exact match, not a substring. Without `grep -qx`, a dangling reference
# to F1 would silently resolve against an existing F123 — and then the
# check would report "fine" while no F1 exists anywhere.
p="$(bouw substring \
'### F123 — het enige item' \
'### S1 — dekt F123
**Dekt:** F123

### S2 — hangende verwijzing die substring is van F123
**Dekt:** F1')"
uitvoer="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "substring — F1 resolved against F123"
assert_contains "substring — F1 is in the message" "F1" "$uitvoer"

# A duplicate that is not next to its twin. Without sorting before
# looking for duplicates, `uniq -d` only sees adjacent lines, and then
# exactly the realistic case slips through: a copy-paste error further down
# in a large file.
p="$(bouw duplicaat-uiteen \
'### F1 — iets' \
'### S1 — eerste
**Dekt:** F1

### S2 — er tussenin
**Dekt:** F1

### S1 — dezelfde ID, ver van de eerste
**Dekt:** F1')"
uitvoer="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "duplicate-apart — non-adjacent duplicate S1 was missed"
assert_contains "duplicate-apart — S1 is in the message" "S1" "$uitvoer"

# A broken token is reported, not silently filtered out. Otherwise the
# check would promise that every token resolves while it precisely fails
# to see the typos.
p="$(bouw kapot-token \
'### F1 — iets

### F2 — iets' \
'### S1 — met een tikfout ertussen
**Dekt:** F1, F-2, F2')"
uitvoer="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "broken token — 'F-2' was silently filtered out"
assert_contains "broken token — F-2 is in the message" "F-2" "$uitvoer"

# Spaces instead of commas produce one unusable token. That too must be
# reported, since otherwise the field looks filled in while covering nothing.
p="$(bouw spatie-gescheiden \
'### F1 — iets

### F2 — iets' \
'### S1 — spaties in plaats van komma is
**Dekt:** F1 F2')"
uitvoer="$("$script" "$p" 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "space-separated — 'F1 F2' was silently filtered out"

test_klaar "T1/T2/T5/S30/S62"
