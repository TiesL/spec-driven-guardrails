#!/usr/bin/env bash
# S167 — hooks/pre-commit warns and skips ./check when lib/git-env.sh is missing.
# Covers: F17
#
# Issue #377, human decision on the Architect report: running ./check
# without git-environment isolation *is* the hazard, so "could not
# isolate" means "do not run ./check". Fail-open for the commit itself,
# the same as a missing rules.sh (S58).

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

# Hermetic outer process (see S165): git's own list, read at runtime.
for _v in $(git rev-parse --local-env-vars 2>/dev/null); do unset "$_v"; done

sandbox_create
trap sandbox_destroy EXIT

# Given: a copy of this repo without lib/git-env.sh, its hook installed as a
# symlink, and a ./check that leaves a marker when it runs.
repo="$(sandbox_copy_repo)"
rm -f "$repo/lib/git-env.sh"

project="$SANDBOX/project"
git init -q -b main "$project"
mkdir -p "$project/.git/hooks"
ln -s "$repo/hooks/pre-commit" "$project/.git/hooks/pre-commit"
cat > "$project/check" <<EOF
#!/usr/bin/env bash
touch "$SANDBOX/check-ran"
exit 0
EOF
chmod +x "$project/check"
git -C "$project" add check
CLAUDE_WORKFLOW_GUARDRAILS_OFF=1 git -C "$project" commit -q -m "base"
git -C "$project" checkout -q -b feature/1-something

# When: a commit on a feature branch.
output="$(cd "$project" && git commit -q --allow-empty -m "second commit" 2>&1)"
status=$?

# Then: the commit proceeds, with a warning, and ./check never ran.
[ "$status" -eq 0 ] || fail "S167 — the commit was blocked while lib/git-env.sh is missing (must fail open), got: $output"
assert_contains "S167 — a warning appears" "warning" "$output"
assert_contains "S167 — the warning names the missing library" "git-env.sh" "$output"
[ ! -e "$SANDBOX/check-ran" ] || fail "S167 — ./check ran without git-environment isolation"

# And: the branch guard still works without the library (unchanged S58/S96 behavior).
git -C "$project" checkout -q main
if (cd "$project" && git commit -q --allow-empty -m "on main" >/dev/null 2>&1); then
  fail "S167 — a commit on main was let through while lib/git-env.sh is missing"
fi

test_done
