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


# #419: exercise the public CLI with real directory aliases and file modes.
script_names="check-pr-issue-link.sh check-main-via-pr.sh"
file_state() {
  python3 - "$1" <<'PY_STATE'
import os, stat, sys
p = sys.argv[1]
s = os.lstat(p)
print(oct(stat.S_IMODE(s.st_mode)))
print(os.readlink(p) if stat.S_ISLNK(s.st_mode) else open(p).read())
PY_STATE
}
prepare_self() {
  fixture="$(sandbox_copy_repo "$1")"
  rm -rf "$fixture/.agents" "$fixture/.guardrails"
  git -C "$fixture" init -q -b main
  # sandbox_copy_repo may inherit machine-local adoption artifacts.
  rm -f "$fixture/AGENTS.md" "$fixture/check-pr-issue-link.sh" \
    "$fixture/check-main-via-pr.sh" "$fixture/wait-for-ci.sh" \
    "$fixture/.guardrails/installation.json"
}
run_adoption() {
  result="$(SPEC_DRIVEN_GUARDRAILS_DIR="$source_path" "$TEST_REPO_ROOT/adopt.sh" \
    --runtime "$route" "$target_path" 2>&1)"
  result_status=$?
}
for route in claude codex; do
  for spelling in direct target source both; do
    prepare_self "$route $spelling missing"
    ln -s "$fixture" "$fixture alias"
    source_path="$fixture"; target_path="$fixture"
    case "$spelling" in source|both) source_path="$fixture alias" ;; esac
    case "$spelling" in target|both) target_path="$fixture alias" ;; esac
    for invocation in 1 2; do
      run_adoption
      [ "$result_status" -eq 0 ] || fail "S81 $route $spelling call $invocation: $result"
      for name in $script_names; do
        [ ! -e "$fixture/$name" ] || fail "S81 $route $spelling created $name"
      done
      [ -x "$fixture/wait-for-ci.sh" ] || fail "S81 $route $spelling skipped wait-for-ci.sh"
    done
  done
  for pair in existing mixed; do
    prepare_self "$route $pair"
    source_path="$fixture"; target_path="$fixture"
    printf 'issue marker\n' > "$fixture/check-pr-issue-link.sh"
    chmod 640 "$fixture/check-pr-issue-link.sh"
    before_issue="$(file_state "$fixture/check-pr-issue-link.sh")"
    if [ "$pair" = existing ]; then
      printf 'main marker\n' > "$fixture/check-main-via-pr.sh"
      chmod 600 "$fixture/check-main-via-pr.sh"
      before_main="$(file_state "$fixture/check-main-via-pr.sh")"
    fi
    for invocation in 1 2; do
      run_adoption
      [ "$result_status" -eq 0 ] || fail "S81 $route $pair adoption: $result"
      [ "$(file_state "$fixture/check-pr-issue-link.sh")" = "$before_issue" ] || fail "S81 $route $pair changed issue copy contents/mode"
      if [ "$pair" = existing ]; then
        [ "$(file_state "$fixture/check-main-via-pr.sh")" = "$before_main" ] || fail "S81 $route $pair changed main copy contents/mode"
      else
        [ ! -e "$fixture/check-main-via-pr.sh" ] || fail "S81 $route mixed created missing copy"
      fi
    done
  done

  # A separate checkout with the same remote must still receive scaffolds.
  other="$(fresh_project "$route other project")"
  git -C "$fixture" remote add origin https://example.invalid/shared.git
  git -C "$other" remote add origin https://example.invalid/shared.git
  printf '#!/bin/sh\nexit 0\n' > "$other/check"
  chmod +x "$other/check"
  ln -s "$other" "$other alias"
  source_path="$fixture"; target_path="$other alias"
  run_adoption
  [ "$result_status" -eq 0 ] || fail "S81 $route distinct project: $result"
  for name in $script_names; do
    cmp -s "$fixture/templates/$name" "$other/$name" || fail "S81 $route distinct missing $name"
    [ -x "$other/$name" ] || fail "S81 $route distinct non-executable $name"
    printf '%s custom\n' "$name" > "$other/$name"
    chmod 600 "$other/$name"
  done
  for invocation in 1 2; do
    run_adoption
    [ "$result_status" -eq 0 ] || fail "S81 $route distinct re-adoption: $result"
    for name in $script_names; do
      [ "$(cat "$other/$name")" = "$name custom" ] || fail "S81 $route overwrote custom $name"
      [ -x "$other/$name" ] || fail "S81 $route did not repair executable $name"
      chmod 600 "$other/$name"
    done
  done
done

# Codex must exclude each skipped destination, but retain other preflight guards.
route=codex
for name in $script_names wait-for-ci.sh; do
  prepare_self "codex symlink $name"
  sentinel="$SANDBOX/sentinel $name"
  printf 'outside sentinel\n' > "$sentinel"
  chmod 600 "$sentinel"
  ln -s "$sentinel" "$fixture/$name"
  before_link="$(file_state "$fixture/$name")"
  before_sentinel="$(file_state "$sentinel")"
  source_path="$fixture"; target_path="$fixture"
  run_adoption
  if [ "$name" = wait-for-ci.sh ]; then
    [ "$result_status" -ne 0 ] || fail "S81 Codex accepted selected symlink $name"
    [ ! -e "$fixture/.guardrails/installation.json" ] || fail "S81 Codex wrote ownership before refusal"
    [ ! -e "$fixture/AGENTS.md" ] || fail "S81 Codex wrote AGENTS before refusal"
  else
    [ "$result_status" -eq 0 ] || fail "S81 Codex refused skipped symlink $name: $result"
  fi
  [ "$(file_state "$fixture/$name")" = "$before_link" ] || fail "S81 Codex changed symlink $name"
  [ "$(file_state "$sentinel")" = "$before_sentinel" ] || fail "S81 Codex changed sentinel $name"
done

test_done
