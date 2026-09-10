#!/usr/bin/env bash
# S2 — `check` fails on invalid JSON in the hook configuration.
# Covers: F1

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

repo="$(sandbox_copy_repo)"

# Given: session-hooks.json with a missing comma.
cat > "$repo/settings/session-hooks.json" <<'JSON'
{
  "hooks": {
    "SessionStart": []
  }
  "attribution": {
    "commit": ""
  }
}
JSON

# When: ./check runs.
uitvoer="$("$TEST_REPO_ROOT/check" --no-tests "$repo" 2>&1)"
status=$?

# Then: exit != 0, with a message that names the file.
if [ "$status" -eq 0 ]; then
  fail "S2 — check succeeded on invalid JSON"
fi
assert_contains "S2" "session-hooks.json" "$uitvoer"

# And: this also happens when shellcheck is not installed. A minimal PATH
# keeps jq and python3 (both in /usr/bin on macOS) but drops shellcheck,
# which lives in /opt/homebrew/bin or /usr/local/bin.
uitvoer_zonder_sc="$(PATH=/usr/bin:/bin "$TEST_REPO_ROOT/check" --no-tests "$repo" 2>&1)"
status_zonder_sc=$?

if [ "$status_zonder_sc" -eq 0 ]; then
  fail "S2 — check succeeded on invalid JSON when shellcheck was missing"
fi
assert_contains "S2 (without shellcheck)" "session-hooks.json" "$uitvoer_zonder_sc"

# And: if both jq and python3 are missing, check cannot verify the file. It
# must not report "fine" in that case - a green result without a check is
# exactly the silent degradation this repo pays for most dearly.
minbin="$(minimale_path_zonder_validators)"
uitvoer_zonder_validator="$(PATH="$minbin" "$TEST_REPO_ROOT/check" --no-tests "$repo" 2>&1)"
status_zonder_validator=$?

if [ "$status_zonder_validator" -eq 0 ]; then
  fail "S2 — check reported 'fine' while it could not validate the JSON"
fi
assert_contains "S2 (no validator)" "session-hooks.json" "$uitvoer_zonder_validator"

test_klaar
