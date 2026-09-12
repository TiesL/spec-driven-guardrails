#!/usr/bin/env bash
# S81 — spec-driven-guardrails can adopt itself.
# Covers: F7, F8

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# Given: a sandbox copy of this repo, used as both
# SPEC_DRIVEN_GUARDRAILS_DIR and the adoption target. sandbox_copy_repo copies
# the current state of this repo (including the refusal above, if
# not yet removed — exactly what "red first" tests here).
repo="$(sandbox_copy_repo)"
git -C "$repo" init -q -b main
git -C "$repo" -c user.name=test -c user.email=test@example.invalid \
  commit -q --allow-empty -m "eerste commit"

# Fingerprint of existing, committed files before adoption — to show
# that self-adoption overwrites nothing of this repo itself.
before_prd="$(cat "$repo/PRD.md")"
before_scenarios="$(cat "$repo/TEST-SCENARIOS.md")"
before_check="$(cat "$repo/check")"

# When: adopt.sh runs with itself as both source and target.
output="$(SPEC_DRIVEN_GUARDRAILS_DIR="$repo" "$repo/adopt.sh" "$repo" 2>&1)"
status=$?

# Then: it actually adopts, instead of showing the refusal.
case "$output" in
  *"no adoption needed"*)
    fail "S81 — adopt.sh still refuses to adopt itself: $output"
    test_done
    ;;
esac
[ "$status" -eq 0 ] || fail "S81 — adopt.sh against itself gave exit status $status: $output"

# Exact comparison, not a */WORKFLOW.md pattern: the latter would also
# pass if the symlink accidentally pointed to WORKFLOW.md in the real repo
# outside the sandbox instead of the sandbox copy itself.
[ -L "$repo/CLAUDE.md" ] || fail "S81 — CLAUDE.md is not a symlink after self-adoption"
target_claude="$(readlink "$repo/CLAUDE.md" 2>/dev/null)"
[ "$target_claude" = "$repo/WORKFLOW.md" ] \
  || fail "S81 — CLAUDE.md does not point to the sandbox copy of WORKFLOW.md: $target_claude"

[ -L "$repo/.claude/settings.json" ] || fail "S81 — .claude/settings.json is not a symlink after self-adoption"
target_settings="$(readlink "$repo/.claude/settings.json" 2>/dev/null)"
[ "$target_settings" = "$repo/settings/session-hooks.json" ] \
  || fail "S81 — .claude/settings.json does not point to the sandbox copy of settings/session-hooks.json: $target_settings"

# And: not a single existing, committed file changes.
[ "$(cat "$repo/PRD.md")" = "$before_prd" ] \
  || fail "S81 — PRD.md was changed by self-adoption"
[ "$(cat "$repo/TEST-SCENARIOS.md")" = "$before_scenarios" ] \
  || fail "S81 — TEST-SCENARIOS.md was changed by self-adoption"
[ "$(cat "$repo/check")" = "$before_check" ] \
  || fail "S81 — check was changed by self-adoption"

# And: the git-guardrails hook is functional afterward — a fabricated
# PreToolUse call proposing a direct push to main is
# refused, just as in any adopted project.
input='{"tool_name":"Bash","cwd":"'"$repo"'","tool_input":{"command":"git push origin main"}}'
hook_output="$(printf '%s' "$input" | "$repo/hooks/git-guardrails" 2>&1)"
hook_status=$?
[ "$hook_status" -ne 0 ] \
  || fail "S81 — the PreToolUse guard did not refuse a direct push to main: $hook_output"
assert_contains "S81 — the message matches the PreToolUse guard" "main gets its changes via a PR" "$hook_output"

# And: the native git hooks are also installed and refuse the same
# outside Claude Code (same pattern as S50).
[ -L "$repo/.git/hooks/pre-commit" ] || fail "S81 — pre-commit is not a symlink after self-adoption"
[ -L "$repo/.git/hooks/pre-push" ] || fail "S81 — pre-push is not a symlink after self-adoption"
native_output="$(cd "$repo" && git commit -q --allow-empty -m "rechtstreeks op main" 2>&1)"
native_status=$?
[ "$native_status" -ne 0 ] \
  || fail "S81 — the native pre-commit hook did not refuse a direct commit to main"
assert_contains "S81 — the native hook message matches the PreToolUse guard" "main gets its changes via a PR" "$native_output"

# And: a second call is idempotent.
uitvoer2="$(SPEC_DRIVEN_GUARDRAILS_DIR="$repo" "$repo/adopt.sh" "$repo" 2>&1)"
status2=$?
[ "$status2" -eq 0 ] || fail "S81 — a second self-adoption fails: $uitvoer2"
gitignore_regels="$(grep -c '^CLAUDE\.md$' "$repo/.gitignore" 2>/dev/null || echo 0)"
[ "$gitignore_regels" -le 1 ] \
  || fail "S81 — a second self-adoption adds CLAUDE.md to .gitignore twice"

test_done
