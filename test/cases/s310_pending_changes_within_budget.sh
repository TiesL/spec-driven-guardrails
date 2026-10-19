#!/usr/bin/env bash
# S310 — worst-case pending-changes output is within the same budget
# (#499 AC5)
# Covers: F38
#
# Seam: `pending-changes.sh <project>` output, measured by `context_chars`
# of lib/context-budget.sh against CONTEXT_BUDGET_CHARS (the constant S309
# uses, sourced, never a literal here). Worst case: a git repo with an
# executable `check` and `deploy` and no WORKFLOW-ADOPTION.md, so every
# applicable entry and NFR is pending.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

if [ ! -r "$TEST_REPO_ROOT/lib/context-budget.sh" ]; then
  fail "S310 — lib/context-budget.sh is missing"
  test_done
fi
# shellcheck source=../../lib/context-budget.sh
. "$TEST_REPO_ROOT/lib/context-budget.sh"

proj="$SANDBOX/project"
mkdir -p "$proj"
git -C "$proj" init -q -b main
printf '#!/usr/bin/env bash\nexit 0\n' > "$proj/check"
printf '#!/usr/bin/env bash\nexit 0\n' > "$proj/deploy"
chmod +x "$proj/check" "$proj/deploy"

out="$("$TEST_REPO_ROOT/pending-changes.sh" "$proj" 2>/dev/null; printf x)"
out="${out%x}"
[ -n "$out" ] || fail "S310 — the worst-case fixture produced no pending output"

within() { # budget -> 0 when the output fits; prints the failure
  local size
  size="$(printf '%s' "$out" | context_chars)"
  if [ "$size" -gt "$1" ]; then
    echo "pending-changes.sh output is $size characters, over the budget of $1"
    return 1
  fi
}
msg="$(within "$CONTEXT_BUDGET_CHARS")" || fail "S310 — $msg"
# Negative control (red-before-green proof for a check green on main): the
# same check with the budget overridden to 5,000 fails and names both.
msg="$(within 5000)" && fail "S310/neg — the check passed a 5,000 budget"
case "$msg" in
  *"characters, over the budget of 5000") ;;
  *) fail "S310/neg — the failure must name size and budget: '$msg'" ;;
esac

test_done
