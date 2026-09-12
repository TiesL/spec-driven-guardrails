#!/usr/bin/env bash
# S86 — SessionStart/SessionEnd hooks work regardless of the incidental cwd.
# Covers: F6, F18

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

get_command() {
  local event="$1" index="$2"
  if command -v jq >/dev/null 2>&1; then
    jq -r ".hooks.$event[0].hooks[$index].command" "$TEST_REPO_ROOT/settings/session-hooks.json"
  else
    python3 -c '
import json, sys
h = json.load(open(sys.argv[1]))["hooks"][sys.argv[2]][0]["hooks"][int(sys.argv[3])]
print(h["command"])
' "$TEST_REPO_ROOT/settings/session-hooks.json" "$event" "$index"
  fi
}

fetch_command="$(get_command SessionStart 0)"
pending_command="$(get_command SessionStart 1)"
push_command="$(get_command SessionEnd 0)"
[ -n "$fetch_command" ] || fail "S86 — no first SessionStart command found"
[ -n "$pending_command" ] || fail "S86 — no second SessionStart command found"
[ -n "$push_command" ] || fail "S86 — no SessionEnd command found"

# Given: an adopted project with a real bare remote (so fetch/push have
# something real to hit), a pre-migration answer table (so the
# pending-changes.sh call has something to report), and an unrelated
# "elsewhere" directory to run the hooks from.
project="$(fresh_project target-project)"
mkdir -p "$project/.claude"
ln -s "$TEST_REPO_ROOT/settings/session-hooks.json" "$project/.claude/settings.json"
cat > "$project/WORKFLOW-ADOPTIE.md" <<'EOF'
# Adoption of shared workflow changes

| Change | Answer | Date | Notes |
|---|---|---|---|
| ci-convention | ja | 2026-01-01 | outdated answer |
EOF

remote="$SANDBOX/remote.git"
git init -q --bare "$remote"
git -C "$project" remote add origin "$remote"
git -C "$project" commit -q --allow-empty -m start
git -C "$project" push -q origin main

elsewhere="$SANDBOX/elsewhere"
mkdir -p "$elsewhere"

# --- git fetch origin ------------------------------------------------------
# A second clone pushes a new commit to the same remote, so this project's
# fetch has something real to bring in.
second="$(fresh_project second)"
git -C "$second" remote add origin "$remote"
git -C "$second" pull -q origin main
git -C "$second" commit -q --allow-empty -m "new commit on the remote"
git -C "$second" push -q origin main

(cd "$elsewhere" && CLAUDE_PROJECT_DIR="$project" bash -c "$fetch_command") >/dev/null 2>&1
if ! git -C "$project" rev-parse -q --verify refs/remotes/origin/main >/dev/null 2>&1 \
  || [ "$(git -C "$project" rev-parse refs/remotes/origin/main)" != "$(git -C "$second" rev-parse HEAD)" ]; then
  fail "S86 — 'git fetch origin' from elsewhere did not fetch into the project's own repo"
fi

# The pre-fix, cwd-dependent form must demonstrably fail the same case —
# confirming this is a real regression, not a coincidence.
error_fetch='git fetch origin 2>&1 || true'
output_old_fetch="$(cd "$elsewhere" && CLAUDE_PROJECT_DIR="$project" bash -c "$error_fetch" 2>&1)"
case "$output_old_fetch" in
  *"not a git repository"*) ;;
  *) fail "S86 — the old cwd-dependent fetch form no longer fails as expected from elsewhere; the regression proof is stale: $output_old_fetch" ;;
esac

# --- SessionStart's pending-changes.sh call --------------------------------
output_pending="$(cd "$elsewhere" && CLAUDE_PROJECT_DIR="$project" bash -c "$pending_command" 2>&1)"
assert_contains "S86 — pending-changes.sh ran and reported something, from elsewhere" \
  "ci-convention" "$output_pending"

error_pending='target=$(readlink .claude/settings.json 2>/dev/null); if [ -z "$target" ]; then exit 0; fi; wf=$(dirname "$(dirname "$target")"); if [ -x "$wf/pending-changes.sh" ]; then "$wf/pending-changes.sh" . 2>/dev/null; fi; exit 0'
output_old_pending="$(cd "$elsewhere" && CLAUDE_PROJECT_DIR="$project" bash -c "$error_pending" 2>&1)"
[ -z "$output_old_pending" ] \
  || fail "S86 — the old cwd-dependent pending-changes form no longer silently does nothing from elsewhere; the regression proof is stale: $output_old_pending"

# --- SessionEnd's git push --------------------------------------------------
git -C "$project" checkout -q -b feature/work
git -C "$project" commit -q --allow-empty -m "work on a branch"

(cd "$elsewhere" && CLAUDE_PROJECT_DIR="$project" bash -c "$push_command") >/dev/null 2>&1
if [ "$(git -C "$remote" rev-parse -q --verify refs/heads/feature/work 2>/dev/null)" \
  != "$(git -C "$project" rev-parse HEAD)" ]; then
  fail "S86 — 'git push origin HEAD' from elsewhere did not push the project's own branch to its own remote"
fi

error_push='[ "$(git rev-parse --abbrev-ref HEAD)" != "main" ] && git push origin HEAD 2>&1 || true'
git -C "$project" commit -q --allow-empty -m "another commit"
output_old_push="$(cd "$elsewhere" && CLAUDE_PROJECT_DIR="$project" bash -c "$error_push" 2>&1)"
if [ "$(git -C "$remote" rev-parse -q --verify refs/heads/feature/work 2>/dev/null)" \
  = "$(git -C "$project" rev-parse HEAD)" ]; then
  fail "S86 — the old cwd-dependent push form no longer fails to push from elsewhere; the regression proof is stale"
fi

test_done
