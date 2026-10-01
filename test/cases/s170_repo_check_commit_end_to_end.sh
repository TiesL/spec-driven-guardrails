#!/usr/bin/env bash
# S170 — this repo's own check-commit lets a red test commit through and still blocks on a static failure (#378, AC1, AC2).
# Covers: F17
#
# A throwaway copy of this repo becomes a git project with the real
# hooks/pre-commit installed as a symlink. Its test/run.sh is replaced by a
# stub that writes a marker and exits 1, so "the suite ran" is observable and
# a hook that runs the full ./check at commit time is caught twice (marker,
# and a block). The suite inside the hook inside the suite cannot recurse:
# the stub is the only thing the copy's ./check could call.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

repo="$(sandbox_copy_repo)"
[ -x "$repo/check-commit" ] || fail "S170 — this repo has no executable check-commit at its root"
marker="$SANDBOX/suite-ran"
printf '#!/usr/bin/env bash\ntouch "%s"\nexit 1\n' "$marker" > "$repo/test/run.sh"
chmod +x "$repo/test/run.sh"

git init -q -b main "$repo"
mkdir -p "$repo/.git/hooks"
ln -s "$repo/hooks/pre-commit" "$repo/.git/hooks/pre-commit"
git -C "$repo" add -A
CLAUDE_WORKFLOW_GUARDRAILS_OFF=1 git -C "$repo" commit -q -m "base"
git -C "$repo" checkout -q -b feature/378-x

# AC1: a red test case with its scenario heading commits; the suite does not run.
printf '#!/usr/bin/env bash\n# S9990 — a red test.\n# Covers: F17\nexit 1\n' > "$repo/test/cases/s9990_red.sh"
chmod +x "$repo/test/cases/s9990_red.sh"
printf '\n### S9990 — a red test\n**Covers:** F17\n- Given: x\n- When: y\n- Then: z\n' >> "$repo/TEST-SCENARIOS.md"
git -C "$repo" add -A
out="$(cd "$repo" && git commit -q -m "red-first" 2>&1)"; st=$?
[ "$st" -eq 0 ] || fail "S170 AC1 — a red-first commit was refused: $out"
[ ! -e "$marker" ] || fail "S170 AC1 — the test suite ran at commit time"

# AC2a: a script with a syntax error blocks, showing the failing check's output.
printf '#!/usr/bin/env bash\nif then\n' > "$repo/broken.sh"
chmod +x "$repo/broken.sh"
git -C "$repo" add -A
out="$(cd "$repo" && git commit -q -m "syntax error" 2>&1)"; st=$?
[ "$st" -ne 0 ] || fail "S170 AC2 — a syntax error did not block the commit"
assert_contains "S170 AC2 — the failing script is named" "broken.sh" "$out"
[ ! -e "$marker" ] || fail "S170 AC2 — the test suite ran at commit time"
git -C "$repo" rm -q -f --cached broken.sh; rm -f "$repo/broken.sh"

# AC2b: a scenario heading with no test file blocks, naming the heading.
printf '\n### S9991 — orphan heading\n**Covers:** F17\n- Given: x\n- When: y\n- Then: z\n' >> "$repo/TEST-SCENARIOS.md"
git -C "$repo" add -A
out="$(cd "$repo" && git commit -q -m "orphan heading" 2>&1)"; st=$?
[ "$st" -ne 0 ] || fail "S170 AC2 — a heading without a test file did not block the commit"
assert_contains "S170 AC2 — the orphan heading is named" "S9991" "$out"
[ ! -e "$marker" ] || fail "S170 AC2 — the test suite ran at commit time"

test_done
