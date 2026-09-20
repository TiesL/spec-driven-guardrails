#!/usr/bin/env bash
# S144 — hooks/pre-commit runs ./check and blocks a commit on a real
# failure, fails open when ./check itself can't run, and respects the
# existing escape hatch (#263).
# Covers: F17

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# Case 1 (AC1): a green ./check does not block the commit.
project_green="$(fresh_project check-green)"
adopt "$project_green"
cat > "$project_green/check" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$project_green/check"

git -C "$project_green" commit -q --allow-empty -m "first commit"
git -C "$project_green" checkout -q -b feature/1-something
output_green="$(cd "$project_green" && git commit -q --allow-empty -m "second commit" 2>&1)"
status_green=$?
[ "$status_green" -eq 0 ] || fail "S144 — a commit was blocked despite a green ./check, got: $output_green"

# Case 2 (AC2): a red ./check blocks the commit and shows its output.
project_red="$(fresh_project check-red)"
adopt "$project_red"
cat > "$project_red/check" <<'EOF'
#!/usr/bin/env bash
echo "FAKE CHECK FAILURE"
exit 1
EOF
chmod +x "$project_red/check"

git -C "$project_red" commit -q --allow-empty -m "first commit"
git -C "$project_red" checkout -q -b feature/1-something
output_red="$(cd "$project_red" && git commit -q --allow-empty -m "second commit" 2>&1)"
status_red=$?
[ "$status_red" -ne 0 ] || fail "S144 — a commit was not blocked despite a red ./check"
assert_contains "S144 — the block message names ./check" "./check failed" "$output_red"
assert_contains "S144 — ./check's own output is shown" "FAKE CHECK FAILURE" "$output_red"

# Case 3 (AC3): no executable ./check at all fails open, with a warning.
project_missing="$(fresh_project check-missing)"
adopt "$project_missing"

git -C "$project_missing" commit -q --allow-empty -m "first commit"
git -C "$project_missing" checkout -q -b feature/1-something
output_missing="$(cd "$project_missing" && git commit -q --allow-empty -m "second commit" 2>&1)"
status_missing=$?
[ "$status_missing" -eq 0 ] || fail "S144 — a commit was blocked with no ./check present, got: $output_missing"
assert_contains "S144 — a warning names the missing ./check" "no executable ./check" "$output_missing"

# Case 4 (AC4): the existing escape hatch also covers ./check, not just the
# branch guard — a red ./check with the guard disabled still proceeds.
project_off="$(fresh_project check-guard-off)"
adopt "$project_off"
cat > "$project_off/check" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$project_off/check"

git -C "$project_off" commit -q --allow-empty -m "first commit"
git -C "$project_off" checkout -q -b feature/1-something
output_off="$(cd "$project_off" && CLAUDE_WORKFLOW_GUARDRAILS_OFF=1 git commit -q --allow-empty -m "second commit" 2>&1)"
status_off=$?
[ "$status_off" -eq 0 ] || fail "S144 — the escape hatch did not let a commit through despite a red ./check, got: $output_off"
assert_contains "S144 — a warning names the disabled guard" "disabled via CLAUDE_WORKFLOW_GUARDRAILS_OFF" "$output_off"

test_done
