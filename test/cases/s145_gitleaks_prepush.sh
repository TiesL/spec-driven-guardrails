#!/usr/bin/env bash
# S145 — hooks/pre-push runs gitleaks on what's being pushed, blocking on
# a real finding, unconditional on repo visibility, failing open if
# gitleaks itself can't run, and respecting the existing escape hatch
# (#264).
# Covers: F17
#
# A fake `gitleaks` (test/lib.sh's fake_gitleaks_bin), not the real one:
# these cases exercise the hook's own logic (block/allow/fail-open), not
# whether any particular fixture commit happens to contain a real secret.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

setup_pushable_project() {
  local name="$1"
  local project="$SANDBOX/$name"
  local remote="$SANDBOX/$name-remote.git"
  git init -q --bare "$remote" >/dev/null
  project="$(fresh_project "$name")"
  git -C "$project" remote add origin "$remote"
  git -C "$project" commit -q --allow-empty -m "first commit"
  git -C "$project" checkout -q -b feature/1-something
  git -C "$project" commit -q --allow-empty -m "on a branch"
  echo "$project"
}

# Case 1 (AC1): gitleaks installed, finds nothing -> push proceeds.
project_clean="$(setup_pushable_project gitleaks-clean)"
adopt "$project_clean"
fakebin_clean="$(fake_gitleaks_bin 'exit 0')"
output_clean="$(cd "$project_clean" && PATH="$fakebin_clean:$PATH" git push origin feature/1-something 2>&1)"
status_clean=$?
[ "$status_clean" -eq 0 ] || fail "S145 — a push was blocked despite a clean gitleaks scan, got: $output_clean"

# Case 2 (AC2): gitleaks finds something -> push blocked, output shown.
project_leak="$(setup_pushable_project gitleaks-leak)"
adopt "$project_leak"
fakebin_leak="$(fake_gitleaks_bin 'echo "FAKE LEAK FOUND"; exit 1')"
output_leak="$(cd "$project_leak" && PATH="$fakebin_leak:$PATH" git push origin feature/1-something 2>&1)"
status_leak=$?
[ "$status_leak" -ne 0 ] || fail "S145 — a push was not blocked despite a gitleaks finding"
assert_contains "S145 — the block message names gitleaks" "gitleaks found a possible secret" "$output_leak"
assert_contains "S145 — gitleaks' own output is shown" "FAKE LEAK FOUND" "$output_leak"

# Case 3 (AC3): gitleaks not on PATH at all -> fails open, with a warning.
# PATH deliberately narrowed to exclude a real gitleaks install (unlike
# fakebin above, which prepends): git/bash/coreutils live under /usr/bin
# and /bin on every platform this repo runs tests on.
project_missing="$(setup_pushable_project gitleaks-missing)"
adopt "$project_missing"
output_missing="$(cd "$project_missing" && PATH="/usr/bin:/bin" git push origin feature/1-something 2>&1)"
status_missing=$?
[ "$status_missing" -eq 0 ] || fail "S145 — a push was blocked with no gitleaks on PATH, got: $output_missing"
assert_contains "S145 — a warning names the missing gitleaks" "gitleaks not found on PATH" "$output_missing"

# Case 4 (AC4): the existing escape hatch also covers this guard.
project_off="$(setup_pushable_project gitleaks-guard-off)"
adopt "$project_off"
fakebin_off="$(fake_gitleaks_bin 'exit 1')"
output_off="$(cd "$project_off" && PATH="$fakebin_off:$PATH" CLAUDE_WORKFLOW_GUARDRAILS_OFF=1 git push origin feature/1-something 2>&1)"
status_off=$?
[ "$status_off" -eq 0 ] || fail "S145 — the escape hatch did not let a push through despite a gitleaks finding, got: $output_off"
assert_contains "S145 — a warning names the disabled guard" "disabled via CLAUDE_WORKFLOW_GUARDRAILS_OFF" "$output_off"

test_done
