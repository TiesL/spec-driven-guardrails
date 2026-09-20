#!/usr/bin/env bash
# S147 — check-scenario-file-sync.sh enforces the 1:1 correspondence
# between test/cases files and TEST-SCENARIOS.md headings (#260).
# Covers: F32

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

script="$TEST_REPO_ROOT/check-scenario-file-sync.sh"
[ -x "$script" ] || { fail "S147 — check-scenario-file-sync.sh is missing or not executable"; test_done; }

# Given: the real repo, as it stands today.
output="$("$script" "$TEST_REPO_ROOT" 2>&1)"; status=$?
[ "$status" -eq 0 ] || fail "S147 — the real repo is not in sync: $output"

sandbox_create
trap sandbox_destroy EXIT

# A file claiming an ID with no matching heading is caught.
repo1="$(sandbox_copy_repo missing-heading)"
cat > "$repo1/test/cases/s9001_scratch.sh" <<'EOF'
#!/usr/bin/env bash
# S9001 — Scratch scenario with no heading.
EOF
output1="$("$repo1/check-scenario-file-sync.sh" "$repo1" 2>&1)"; status1=$?
[ "$status1" -ne 0 ] || fail "S147 — a file claiming a headless ID was not caught"
assert_contains "S147 — names the offending file" "s9001_scratch.sh" "$output1"
assert_contains "S147 — names the missing ID" "S9001" "$output1"

# A heading with no claiming file is caught.
repo2="$(sandbox_copy_repo orphan-heading)"
printf '\n### S9002 — Scratch heading with no file\n**Covers:** F1\n' >> "$repo2/TEST-SCENARIOS.md"
output2="$("$repo2/check-scenario-file-sync.sh" "$repo2" 2>&1)"; status2=$?
[ "$status2" -ne 0 ] || fail "S147 — an orphan heading was not caught"
assert_contains "S147 — names the orphan heading" "S9002" "$output2"

# The same ID claimed by two different files is caught.
repo3="$(sandbox_copy_repo duplicate-claim)"
cat > "$repo3/test/cases/s1_scratch_duplicate.sh" <<'EOF'
#!/usr/bin/env bash
# S1 — Duplicate claim of an already-claimed ID.
EOF
output3="$("$repo3/check-scenario-file-sync.sh" "$repo3" 2>&1)"; status3=$?
[ "$status3" -ne 0 ] || fail "S147 — a duplicate ID claim across two files was not caught"
assert_contains "S147 — names the duplicated ID" "S1 is claimed by more than one file" "$output3"

# The same heading appearing twice is caught.
repo4="$(sandbox_copy_repo duplicate-heading)"
printf '\n### S1 — Duplicate of an existing heading\n**Covers:** F1\n' >> "$repo4/TEST-SCENARIOS.md"
output4="$("$repo4/check-scenario-file-sync.sh" "$repo4" 2>&1)"; status4=$?
[ "$status4" -ne 0 ] || fail "S147 — a duplicated heading was not caught"
assert_contains "S147 — names the duplicated heading" "S1 appears more than once" "$output4"

# A range header ("S<a>-S<b>") expands to every ID in between, not just
# the two endpoints — proven against this repo's own real S19-S23 file
# rather than a synthetic one, so the assertion tracks the real
# convention instead of a fixture that could drift from it.
repo5="$(sandbox_copy_repo range-gap)"
sed -i.bak '/^### S21 /,/^$/d' "$repo5/TEST-SCENARIOS.md"
rm -f "$repo5/TEST-SCENARIOS.md.bak"
output5="$("$repo5/check-scenario-file-sync.sh" "$repo5" 2>&1)"; status5=$?
[ "$status5" -ne 0 ] || fail "S147 — removing a heading from inside a claimed range was not caught"
assert_contains "S147 — names the gap inside the range" "S21" "$output5"

# The pending-exclusion list suppresses a known, tracked orphan heading —
# same mechanism as check-no-dutch.sh's pending_excluded, proven with a
# synthetic entry rather than a real one currently on the list (that list
# shrinks as #272 resolves each entry, which would make a hardcoded real
# ID here fragile against that progress).
repo6="$(sandbox_copy_repo pending-exclusion)"
printf '\n### S9003 — Scratch heading, tracked pending\n**Covers:** F1\n' >> "$repo6/TEST-SCENARIOS.md"
sed -i.bak "s/pending_excluded='\([^']*\)'/pending_excluded='\1 S9003'/" "$repo6/check-scenario-file-sync.sh"
rm -f "$repo6/check-scenario-file-sync.sh.bak"
output6="$("$repo6/check-scenario-file-sync.sh" "$repo6" 2>&1)"; status6=$?
[ "$status6" -eq 0 ] || fail "S147 — a tracked-pending orphan heading was still reported: $output6"

test_done
