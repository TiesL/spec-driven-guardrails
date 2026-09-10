#!/usr/bin/env bash
# S86 — SessionStart/SessionEnd hooks work regardless of the incidental cwd.
# Dekt: F6, F18

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

haal_commando() {
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

fetch_opdracht="$(haal_commando SessionStart 0)"
pending_opdracht="$(haal_commando SessionStart 1)"
push_opdracht="$(haal_commando SessionEnd 0)"
[ -n "$fetch_opdracht" ] || fail "S86 — no first SessionStart command found"
[ -n "$pending_opdracht" ] || fail "S86 — no second SessionStart command found"
[ -n "$push_opdracht" ] || fail "S86 — no SessionEnd command found"

# Given: an adopted project with a real bare remote (so fetch/push have
# something real to hit), a pre-migration answer table (so the
# pending-changes.sh call has something to report), and an unrelated
# "elsewhere" directory to run the hooks from.
project="$(vers_project doelproject)"
mkdir -p "$project/.claude"
ln -s "$TEST_REPO_ROOT/settings/session-hooks.json" "$project/.claude/settings.json"
cat > "$project/WORKFLOW-ADOPTIE.md" <<'EOF'
# Adoptie van gedeelde workflow-wijzigingen

| Wijziging | Antwoord | Datum | Toelichting |
|---|---|---|---|
| ci-conventie | ja | 2026-01-01 | verouderd antwoord |
EOF

remote="$SANDBOX/remote.git"
git init -q --bare "$remote"
git -C "$project" remote add origin "$remote"
git -C "$project" commit -q --allow-empty -m start
git -C "$project" push -q origin main

elders="$SANDBOX/elders"
mkdir -p "$elders"

# --- git fetch origin ------------------------------------------------------
# A second clone pushes a new commit to the same remote, so this project's
# fetch has something real to bring in.
tweede="$(vers_project tweede)"
git -C "$tweede" remote add origin "$remote"
git -C "$tweede" pull -q origin main
git -C "$tweede" commit -q --allow-empty -m "nieuwe commit op de remote"
git -C "$tweede" push -q origin main

(cd "$elders" && CLAUDE_PROJECT_DIR="$project" bash -c "$fetch_opdracht") >/dev/null 2>&1
if ! git -C "$project" rev-parse -q --verify refs/remotes/origin/main >/dev/null 2>&1 \
  || [ "$(git -C "$project" rev-parse refs/remotes/origin/main)" != "$(git -C "$tweede" rev-parse HEAD)" ]; then
  fail "S86 — 'git fetch origin' from elsewhere did not fetch into the project's own repo"
fi

# The pre-fix, cwd-dependent form must demonstrably fail the same case —
# confirming this is a real regression, not a coincidence.
fout_fetch='git fetch origin 2>&1 || true'
uitvoer_oud_fetch="$(cd "$elders" && CLAUDE_PROJECT_DIR="$project" bash -c "$fout_fetch" 2>&1)"
case "$uitvoer_oud_fetch" in
  *"not a git repository"*) ;;
  *) fail "S86 — the old cwd-dependent fetch form no longer fails as expected from elsewhere; the regression proof is stale: $uitvoer_oud_fetch" ;;
esac

# --- SessionStart's pending-changes.sh call --------------------------------
uitvoer_pending="$(cd "$elders" && CLAUDE_PROJECT_DIR="$project" bash -c "$pending_opdracht" 2>&1)"
assert_contains "S86 — pending-changes.sh ran and reported something, from elsewhere" \
  "ci-conventie" "$uitvoer_pending"

fout_pending='doel=$(readlink .claude/settings.json 2>/dev/null); if [ -z "$doel" ]; then exit 0; fi; wf=$(dirname "$(dirname "$doel")"); if [ -x "$wf/pending-changes.sh" ]; then "$wf/pending-changes.sh" . 2>/dev/null; fi; exit 0'
uitvoer_oud_pending="$(cd "$elders" && CLAUDE_PROJECT_DIR="$project" bash -c "$fout_pending" 2>&1)"
[ -z "$uitvoer_oud_pending" ] \
  || fail "S86 — the old cwd-dependent pending-changes form no longer silently does nothing from elsewhere; the regression proof is stale: $uitvoer_oud_pending"

# --- SessionEnd's git push --------------------------------------------------
git -C "$project" checkout -q -b feature/werk
git -C "$project" commit -q --allow-empty -m "werk op een branch"

(cd "$elders" && CLAUDE_PROJECT_DIR="$project" bash -c "$push_opdracht") >/dev/null 2>&1
if [ "$(git -C "$remote" rev-parse -q --verify refs/heads/feature/werk 2>/dev/null)" \
  != "$(git -C "$project" rev-parse HEAD)" ]; then
  fail "S86 — 'git push origin HEAD' from elsewhere did not push the project's own branch to its own remote"
fi

fout_push='[ "$(git rev-parse --abbrev-ref HEAD)" != "main" ] && git push origin HEAD 2>&1 || true'
git -C "$project" commit -q --allow-empty -m "nog een commit"
uitvoer_oud_push="$(cd "$elders" && CLAUDE_PROJECT_DIR="$project" bash -c "$fout_push" 2>&1)"
if [ "$(git -C "$remote" rev-parse -q --verify refs/heads/feature/werk 2>/dev/null)" \
  = "$(git -C "$project" rev-parse HEAD)" ]; then
  fail "S86 — the old cwd-dependent push form no longer fails to push from elsewhere; the regression proof is stale"
fi

test_klaar
