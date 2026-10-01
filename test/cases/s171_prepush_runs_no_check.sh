#!/usr/bin/env bash
# S171 — hooks/pre-push does not run check or the suite, and still refuses a push to main (#378, AC7, R3).
# Covers: F17

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

project="$(fresh_project pushable)"
remote="$SANDBOX/remote.git"
git init -q --bare "$remote"
git -C "$project" remote add origin "$remote"
adopt "$project"
git -C "$project" commit -q --allow-empty -m "first commit"
git -C "$project" checkout -q -b feature/1-something
# A project whose full check and declared commit check are both red, each
# leaving a marker if it runs.
for f in check check-commit; do
  printf '#!/usr/bin/env bash\ntouch "%s/%s-ran"\nexit 1\n' "$SANDBOX" "$f" > "$project/$f"
  chmod +x "$project/$f"
done
# Commits made with the guard off: this scenario is about push, not commit.
CLAUDE_WORKFLOW_GUARDRAILS_OFF=1 git -C "$project" commit -q --allow-empty -m "tip with a red test"

out="$(cd "$project" && git push origin feature/1-something 2>&1)"; st=$?
[ "$st" -eq 0 ] || fail "S171 — a push of a branch with a red test was refused: $out"
[ ! -e "$SANDBOX/check-ran" ] || fail "S171 — pre-push ran the full ./check"
[ ! -e "$SANDBOX/check-commit-ran" ] || fail "S171 — pre-push ran check-commit"

out="$(cd "$project" && git push origin HEAD:main 2>&1)"; st=$?
[ "$st" -ne 0 ] || fail "S171 — a push to main was not refused"

test_done
