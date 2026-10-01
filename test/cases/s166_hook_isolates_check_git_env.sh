#!/usr/bin/env bash
# S166 — hooks/pre-commit runs check-commit without git's repo-local variables, from any worktree and commit form.
# Covers: F17
#
# Issue #377 (AC1, AC2, AC5). git exports repo-local variables to the
# pre-commit hook: GIT_DIR and an absolute GIT_INDEX_FILE in a linked
# worktree, GIT_INDEX_FILE and GIT_PREFIX in the main worktree, and a
# temporary GIT_INDEX_FILE for `git commit -- <path>` / `-a` (verified by
# QA's probe on #377). A ./check that makes fixture git repos then wrote
# into the committing repo. Here a fixture project gets the real hook as a
# symlink (the installed form) and a check-commit that records its environment
# and does fixture git work; every commit form must leave the project
# unchanged apart from the commit itself.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

# Hermetic outer process (see S165): git's own list, read at runtime.
for _v in $(git rev-parse --local-env-vars 2>/dev/null); do unset "$_v"; done

sandbox_create
trap sandbox_destroy EXIT

local_vars="$(git rev-parse --local-env-vars)"
# Non-repo-local settings the hook must pass through to ./check unchanged.
export GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0

# Given: a project with the real hook installed as a symlink, and a ./check
# that records what it sees and then does fixture git work of the same
# shapes as S57/S84/S144 (init, commit, tag, init --bare).
project="$SANDBOX/project"
git init -q -b main "$project"
mkdir -p "$project/.git/hooks"
ln -s "$TEST_REPO_ROOT/hooks/pre-commit" "$project/.git/hooks/pre-commit"

cat > "$project/check-commit" <<EOF
#!/usr/bin/env bash
{
  echo "check_dir=\$(cd "\$(dirname "\$0")" && pwd -P)"
  echo "pwd=\$(pwd -P)"
  env
} > "$SANDBOX/check-env.out"
fx="\$(mktemp -d "$SANDBOX/fx.XXXXXX")"
git init -q -b main "\$fx/repo"
echo fixture > "\$fx/repo/fixture-file.txt"
git -C "\$fx/repo" add fixture-file.txt
git -C "\$fx/repo" commit -q -m "fixture commit"
git -C "\$fx/repo" tag fixture-tag
git init -q --bare "\$fx/remote.git"
exit 0
EOF
chmod +x "$project/check-commit"
echo base > "$project/tracked.txt"
git -C "$project" add check-commit tracked.txt
CLAUDE_WORKFLOW_GUARDRAILS_OFF=1 git -C "$project" commit -q -m "base"
git -C "$project" checkout -q -b feature/1-main
linked="$SANDBOX/linked"
git -C "$project" worktree add -q "$linked" -b feature/1-linked
project="$(cd "$project" && pwd -P)"
linked="$(cd "$linked" && pwd -P)"

# Everything shared by all worktrees, plus the *other* worktree's HEAD and
# index; $1 is the committing worktree, whose own branch and index may change.
snap_except() {
  local committing="$1" branch w
  branch="$(git -C "$committing" symbolic-ref -q HEAD)"
  echo "## refs"; git -C "$project" for-each-ref --format='%(refname) %(objectname)' | grep -v "^$branch "
  echo "## worktrees"; git -C "$project" worktree list --porcelain | grep -v '^HEAD '
  echo "## config"; cat "$project/.git/config"
  echo "## stash"; git -C "$project" stash list
  for w in "$project" "$linked"; do
    [ "$w" = "$committing" ] && continue
    echo "## other worktree $w"; git -C "$w" rev-parse HEAD; git -C "$w" ls-files -s
  done
}

# $1 label, $2 worktree, $3 form (normal|partial|all).
commit_and_check() {
  local label="$1" wt="$2" form="$3" before after out status name
  echo "$label" >> "$wt/tracked.txt"
  echo "$label" > "$wt/$label-a.txt"
  echo "$label" > "$wt/$label-b.txt"
  git -C "$wt" add "$label-a.txt" "$label-b.txt"
  rm -f "$SANDBOX/check-env.out"
  before="$(snap_except "$wt")"
  case "$form" in
    normal)  out="$(cd "$wt" && git commit -q -m "S166 $label" 2>&1)" ;;
    partial) out="$(cd "$wt" && git commit -q -m "S166 $label" -- "$label-a.txt" 2>&1)" ;;
    all)     out="$(cd "$wt" && git commit -q -a -m "S166 $label" 2>&1)" ;;
  esac
  status=$?
  after="$(snap_except "$wt")"

  [ "$status" -eq 0 ] || fail "S166 [$label] — the commit failed: $out"
  [ -f "$SANDBOX/check-env.out" ] || { fail "S166 [$label] — check-commit did not run"; return; }
  env_seen="$(cat "$SANDBOX/check-env.out")"

  for name in $local_vars; do
    if grep -q "^$name=" "$SANDBOX/check-env.out"; then
      fail "S166 [$label] — ./check saw $(grep "^$name=" "$SANDBOX/check-env.out")"
    fi
  done
  assert_contains "S166 [$label] — the committing worktree's own ./check ran" "check_dir=$wt" "$env_seen"
  assert_contains "S166 [$label] — ./check ran at the committing worktree's root" "pwd=$wt" "$env_seen"
  assert_contains "S166 [$label] — the git identity reached ./check" "GIT_AUTHOR_NAME=claude-workflow test" "$env_seen"
  assert_contains "S166 [$label] — GIT_CONFIG_NOSYSTEM reached ./check" "GIT_CONFIG_NOSYSTEM=1" "$env_seen"
  assert_contains "S166 [$label] — GIT_TERMINAL_PROMPT reached ./check" "GIT_TERMINAL_PROMPT=0" "$env_seen"

  if [ "$before" != "$after" ]; then
    fail "S166 [$label] — the commit changed the repo beyond its own commit:"
    diff <(echo "$before") <(echo "$after") >&2
  fi

  [ "$(git -C "$wt" log -1 --format=%s 2>/dev/null)" = "S166 $label" ] \
    || fail "S166 [$label] — HEAD is not the commit just made: $(git -C "$wt" log -1 --format=%s 2>&1)"
  local files expected
  files="$(git -C "$wt" show --name-only --format= HEAD 2>/dev/null | sort | tr '\n' ' ')"
  case "$form" in
    normal)  expected="$label-a.txt $label-b.txt " ;;
    partial) expected="$label-a.txt " ;;
    all)     expected="$label-a.txt $label-b.txt tracked.txt " ;;
  esac
  [ "$files" = "$expected" ] || fail "S166 [$label] — the commit holds '$files', expected '$expected'"
  if [ "$form" = partial ]; then
    staged="$(git -C "$wt" diff --cached --name-only 2>/dev/null | tr '\n' ' ')"
    [ "$staged" = "$label-b.txt " ] \
      || fail "S166 [$label] — after a partial commit the index holds staged '$staged', expected '$label-b.txt '"
    git -C "$wt" reset -q -- "$label-b.txt" 2>/dev/null
    rm -f "$wt/$label-b.txt"
  fi
  git -C "$wt" checkout -q -- tracked.txt 2>/dev/null
}

# When/Then: AC1 (linked worktree), AC2 (main worktree, partial, -a).
commit_and_check linked-normal  "$linked"  normal
commit_and_check linked-partial "$linked"  partial
commit_and_check linked-all     "$linked"  all
commit_and_check main-normal    "$project" normal
commit_and_check main-partial   "$project" partial
commit_and_check main-all       "$project" all

test_done
