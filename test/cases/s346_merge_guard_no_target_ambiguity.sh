#!/usr/bin/env bash
# S346 — with no merge target, two open PRs for the current branch fail open with the existing warning (A44 amendment 3, decision 5a)
# Covers: F8
#
# Seam: gh on PATH (a list-driven fake, as in S337/S339), the guard run through
# PreToolUse JSON. The sandbox's current branch is feature/work.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

guard="$TEST_REPO_ROOT/hooks/git-guardrails"
[ -x "$guard" ] || { fail "S346 — hooks/git-guardrails is missing"; test_done; }

sandbox_create
trap sandbox_destroy EXIT

D="$SANDBOX/ghdata"
mkdir -p "$D" "$SANDBOX/fakegh"
calls="$D/calls.log"
cat > "$SANDBOX/fakegh/gh" <<GHEOF
#!/usr/bin/env bash
D="$D"
printf '%s\n' "\$*" >> "\$D/calls.log"
case "\$*" in
  "pr view --json comments,headRefOid")
    sha=1111111111111111111111111111111111111111
    printf '%s' "{\"headRefOid\":\"\$sha\",\"comments\":[{\"body\":\"findings\\\\n<!-- pre-merge-review:done sha=\$sha -->\"}]}"
    exit 0 ;;
  "pr checks --json bucket,name")
    printf '%s' '[{"name":"check","bucket":"pass"}]'
    exit 0 ;;
  "api repos/{owner}/{repo}/pulls --paginate --jq "*)
    cat "\$D/list"; exit 0 ;;
  "api repos/{owner}/{repo}/pulls/"*" --jq .base.ref"*)
    n="\${2##*/pulls/}"; n="\${n%% *}"
    printf 'main\t%040d\n' "\$n"; exit 0 ;;
  "api repos/{owner}/{repo}/compare/"*)
    cat "\$D/behind" 2>/dev/null || echo 0; exit 0 ;;
esac
exit 1
GHEOF
chmod +x "$SANDBOX/fakegh/gh"

project="$(fresh_project noTarget)"
git -C "$project" commit -q --allow-empty -m start
git -C "$project" checkout -q -b feature/work

run_guard() {
  local input='{"tool_name":"Bash","cwd":"'"$project"'","tool_input":{"command":"gh pr merge"}}'
  rm -f "$calls"
  out="$(printf '%s' "$input" | PATH="$SANDBOX/fakegh:$PATH" "$guard" 2>"$SANDBOX/err.txt")"; st=$?
  err="$(cat "$SANDBOX/err.txt")"
}

echo 3 > "$D/behind"

# (a) two PRs for the current branch: fail open, existing warning, no guessing.
printf '41\tfeature/work\n52\tfeature/work\n' > "$D/list"
run_guard
[ "$st" -eq 0 ] || fail "S346/a — ambiguity did not fail open (status $st): $out$err"
assert_contains "S346/a — existing warning" "couldn't determine the PR number" "$err"
assert_contains "S346/a — names the skipped check" "skips the up-to-date check" "$err"
grep -q '^api repos/{owner}/{repo}/pulls/[0-9]* ' "$calls" && fail "S346/a — a candidate PR was read (first-match-wins): $(cat "$calls")"

# (b) exactly one match still blocks; (c) so does one match beside a PR on another branch.
printf '41\tfeature/work\n' > "$D/list"
run_guard
[ "$st" -eq 2 ] || fail "S346/b — a single match behind was not blocked (status $st): $out$err"
assert_contains "S346/b — names the remedy" "gh pr update-branch 41" "$err"
printf '41\tfeature/work\n52\tfeature/other\n' > "$D/list"
run_guard
[ "$st" -eq 2 ] || fail "S346/c — a single match beside another branch's PR was not blocked (status $st): $out$err"
assert_contains "S346/c — names the remedy" "gh pr update-branch 41" "$err"

test_done
