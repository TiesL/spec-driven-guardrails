#!/usr/bin/env bash
# S337-S340 — `gh pr merge <branch>` resolves the branch to its open PR through the existing list seam, for the up-to-date, role-play and stray-Closes checks alike (#541, A44 1)
# Covers: F8
#
# Seam: `gh` on PATH, the guard run through PreToolUse JSON as in S324. One
# data-driven fake gh (below) serves every call shape the three checks make;
# its list answer, per-PR behind counts, marker and CI answers come from
# files in $D, and every call is logged. The sandbox's current branch is
# `feature/current`, never the target, so a match must come from the target.
#
# S339 is a pairing scenario with S337: a stub that always fails open passes
# S339 and fails S337. S338 is a coverage (green-before-and-after) scenario
# for numeric/URL targets and the explicit-target-beats-current-branch rule;
# it closes review finding s324-numeric-target-untested.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"

guard="$TEST_REPO_ROOT/hooks/git-guardrails"
[ -x "$guard" ] || { fail "S337 — hooks/git-guardrails is missing"; test_done; }
command -v jq >/dev/null 2>&1 || { fail "S337 — jq is needed by the fake gh"; test_done; }

sandbox_create
trap sandbox_destroy EXIT

D="$SANDBOX/ghdata"
mkdir -p "$D"
export FAKE_GH_DATA="$D"
calls="$D/calls.log"

# fake_gh: files in $D —
#   list            raw output of the open-PR list (default: 41<TAB>feature/work)
#   list-fail       present: the list call exits 1
#   base            base.ref of every PR (default main)
#   behind-<N>      behind_by for PR N (default 0); head sha of N is %040d N
#   nomarker        present: the review marker is missing
#   commits.dat     raw bytes for pulls/N/commits (default empty)
# Any other `gh api` shape goes to fake_gh_rest (pr-N.json etc.); anything
# else exits 1. Every call is appended to calls.log.
rest="$(fake_gh_rest "$D")"
fakebin="$SANDBOX/fakegh-targets"
mkdir -p "$fakebin"
cat > "$fakebin/gh" <<GHEOF
#!/usr/bin/env bash
D="$D"
printf '%s\n' "\$*" >> "\$D/calls.log"
case "\$*" in
  "pr view "*"--json comments,headRefOid")
    sha=1111111111111111111111111111111111111111
    if [ -f "\$D/nomarker" ]; then body="no marker here"; else body="findings\\\\n<!-- pre-merge-review:done sha=\$sha -->"; fi
    printf '%s' "{\"headRefOid\":\"\$sha\",\"comments\":[{\"body\":\"\$body\"}]}"
    exit 0 ;;
  "pr checks "*"--json bucket,name")
    printf '%s' '[{"name":"check","bucket":"pass"}]'
    exit 0 ;;
  "api repos/{owner}/{repo}/pulls --paginate --jq "*)
    [ -f "\$D/list-fail" ] && { echo "HTTP 502" >&2; exit 1; }
    if [ -f "\$D/list" ]; then cat "\$D/list"; else printf '41\tfeature/work\n'; fi
    exit 0 ;;
  "api repos/{owner}/{repo}/pulls/"*" --jq .base.ref"*)
    n="\${2##*/pulls/}"; n="\${n%% *}"
    printf '%s\t%040d\n' "\$(cat "\$D/base" 2>/dev/null || echo main)" "\$n"
    exit 0 ;;
  "api repos/{owner}/{repo}/compare/"*)
    sha="\${2##*...}"
    n=\$((10#\$sha))
    cat "\$D/behind-\$n" 2>/dev/null || echo 0
    exit 0 ;;
  "api repos/{owner}/{repo}/pulls/"*"/commits "*)
    cat "\$D/commits.dat" 2>/dev/null
    exit 0 ;;
  "issue view "*)
    printf OPEN; exit 0 ;;
  "api "*)
    exec "$rest/gh" "\$@" ;;
esac
exit 1
GHEOF
chmod +x "$fakebin/gh"

project="$(fresh_project branch-target)"
git -C "$project" commit -q --allow-empty -m start
git -C "$project" checkout -q -b feature/current

reset_data() {
  rm -rf "${D:?}"/*
  mkdir -p "$D"
}

# run_guard <command> [project]: sets out (both streams), err (stderr), st.
run_guard() {
  local cmd="$1" proj="${2:-$project}" input errf="$SANDBOX/err.txt"
  input='{"tool_name":"Bash","cwd":"'"$proj"'","tool_input":{"command":"'"$cmd"'"}}'
  rm -f "$calls"
  out="$(printf '%s' "$input" | PATH="$fakebin:$PATH" "$guard" 2>"$errf")"; st=$?
  err="$(cat "$errf")"
  out="$out$err"
}

# only_known_api_shapes: no `api` call besides list, pulls/N base/head and compare (A44: no new call shape).
only_known_api_shapes() {
  ! grep '^api ' "$calls" | grep -v -e '^api repos/{owner}/{repo}/pulls --paginate --jq ' \
    -e '^api repos/{owner}/{repo}/pulls/[0-9]* --jq \.base\.ref' \
    -e '^api repos/{owner}/{repo}/compare/' >/dev/null
}

# --- S337: a branch target is resolved and checked for being behind ----------
for case_id in a c d e; do
  reset_data
  echo 3 > "$D/behind-41"
  target="feature/work"; flags=""; base=main
  case "$case_id" in
    c) target="o:feature/work" ;;
    d) flags=" --squash --delete-branch" ;;
    e) base="release/40-epic"; echo "$base" > "$D/base" ;;
  esac
  run_guard "gh pr merge $target$flags"
  [ "$st" -eq 2 ] || fail "S337/$case_id — a branch target behind its base was not blocked (status $st): $out"
  assert_contains "S337/$case_id — names the base" "$base" "$err"
  assert_contains "S337/$case_id — names the count" "3 commit" "$err"
  assert_contains "S337/$case_id — names the resolved PR number" "gh pr update-branch 41" "$err"
  grep -q '^api repos/{owner}/{repo}/pulls --paginate' "$calls" || fail "S337/$case_id — no list call: $(cat "$calls")"
  grep -q '^api repos/{owner}/{repo}/pulls/41 ' "$calls" || fail "S337/$case_id — pulls/41 was not read: $(cat "$calls")"
  only_known_api_shapes || fail "S337/$case_id — a new gh api call shape appeared: $(cat "$calls")"
done

reset_data   # (b) not behind: passes, paired with (a)
echo 0 > "$D/behind-41"
run_guard "gh pr merge feature/work"
[ "$st" -eq 0 ] || fail "S337/b — an up-to-date branch target was blocked (status $st): $out"
case "$err" in *"behind its base"*|*"couldn't determine the PR number"*) fail "S337/b — unexpected up-to-date message: $err" ;; esac
grep -q '^api repos/{owner}/{repo}/compare/' "$calls" || fail "S337/b — the compare call never ran, so the pass is vacuous: $(cat "$calls")"

# --- S338: numeric and URL targets unchanged; an explicit target wins --------
for target in 41 "https://github.com/o/r/pull/41" "https://github.com/o/r/pull/41/files" "https://github.com/o/r/pull/41?x=1"; do
  reset_data
  echo 3 > "$D/behind-41"
  run_guard "gh pr merge $target --squash --delete-branch"
  [ "$st" -eq 2 ] || fail "S338/$target — not blocked (status $st): $out"
  assert_contains "S338/$target — names update-branch 41" "gh pr update-branch 41" "$err"
  grep -q '^api repos/{owner}/{repo}/pulls --paginate' "$calls" && fail "S338/$target — a list call ran for a number/URL target: $(cat "$calls")"
done
reset_data
echo 0 > "$D/behind-41"
run_guard "gh pr merge 41 --squash --delete-branch"
[ "$st" -eq 0 ] || fail "S338/41-clean — behind_by 0 was blocked (status $st): $out"

# Explicit target beats the current branch: current branch's PR (41) is behind, the target (99) is not.
reset_data
git -C "$project" checkout -q -b feature/work
printf '41\tfeature/work\n' > "$D/list"
echo 3 > "$D/behind-41"; echo 0 > "$D/behind-99"
run_guard "gh pr merge 99 --squash --delete-branch"
[ "$st" -eq 0 ] || fail "S338/explicit — the current branch's PR was checked instead of the explicit target (status $st): $out"
grep -q '^api repos/{owner}/{repo}/pulls/99 ' "$calls" || fail "S338/explicit — pulls/99 was not read: $(cat "$calls")"
git -C "$project" checkout -q feature/current

# --- S339: ambiguous, unknown or unreadable: fail open with a warning --------
expect_open() { # expect_open <label>
  [ "$st" -eq 0 ] || fail "S339/$1 — did not fail open (status $st): $out"
  assert_contains "S339/$1 — warns" "warning:" "$err"
  assert_contains "S339/$1 — names the skipped check" "up-to-date" "$err"
  grep -q '^api repos/{owner}/{repo}/pulls/[0-9]* ' "$calls" && fail "S339/$1 — a candidate PR was read (guessing): $(cat "$calls")"
}
reset_data; echo 3 > "$D/behind-41"; echo 3 > "$D/behind-52"
printf '41\tfeature/work\n52\tfeature/work\n' > "$D/list"
run_guard "gh pr merge feature/work";     expect_open a-ambiguous
run_guard "gh pr merge o:feature/work";   expect_open e-ambiguous-owner
printf '41\tfeature/work\n' > "$D/list"
run_guard "gh pr merge feature/other";    expect_open b-no-match
: > "$D/list"
run_guard "gh pr merge feature/work";     expect_open d-empty-list
printf '41\tfeature/work\n' > "$D/list"; : > "$D/list-fail"
run_guard "gh pr merge feature/work"
[ "$st" -eq 0 ] || fail "S339/c — list failure did not fail open (status $st): $out"
assert_contains "S339/c — warns" "warning:" "$err"
rm -f "$D/list-fail"
# (f) exact string compare, not a pattern: regex-special names match only themselves.
printf '7\tfeatXa.b\n' > "$D/list"
run_guard "gh pr merge feat/a.b";         expect_open f-near-row-only
printf '7\tfeatXa.b\n8\tfeat/a.b\n' > "$D/list"
echo 3 > "$D/behind-8"
run_guard "gh pr merge feat/a.b"
[ "$st" -eq 2 ] || fail "S339/f-exact — the exact row was not matched (status $st): $out"
assert_contains "S339/f-exact — resolved to 8" "gh pr update-branch 8" "$err"
grep -q '^api repos/{owner}/{repo}/pulls/7 ' "$calls" && fail "S339/f-exact — the near row 7 was read"
# Fail-open is per check: a missing marker in an ambiguous case still blocks.
reset_data
printf '41\tfeature/work\n52\tfeature/work\n' > "$D/list"; : > "$D/nomarker"
run_guard "gh pr merge feature/work"
[ "$st" -eq 2 ] || fail "S339/per-check — fail-open skipped the marker check too (status $st): $out"
assert_contains "S339/per-check — the marker block applies" "review marker" "$err"

# --- S340: role-play and stray-Closes share the resolver ---------------------
id="process-multi-agent-roles"
yes_project="$(fresh_project roleplay-yes)"
git -C "$yes_project" commit -q --allow-empty -m start
git -C "$yes_project" checkout -q -b feature/current
write_adoption "$yes_project/WORKFLOW-ADOPTION.md" "$id" yes

all_in_one() { # a role-played run on PR 41 (the s186 fixture)
  reset_data
  json_pr "$D/pr-41.json" "Fix #239: x" "Closes #239"
  json_comments "$D/reviews-41.json"
  json_comments "$D/comments-239.json" "no markers"
  json_comments "$D/comments-41.json" "$(mr Discovery)
$(mr Planning)
$(mr Test)
$(mr Implementation)
$(mr Review)"
}
stray() { # a stray commit-level Closes #999 (the s108 fixture)
  reset_data
  json_pr "$D/pr-41.json" "Closes #10: some change" ""
  printf '%s\x01%s\x02' "aaaaaaa1111111" "First commit
Closes #999" > "$D/commits.dat"
}

for t in feature/work 41; do
  all_in_one
  run_guard "gh pr merge $t" "$yes_project"
  [ "$st" -eq 2 ] || fail "S340/a/$t — role-played run not blocked (status $st): $out"
  assert_contains "S340/a/$t — says why" "role-played" "$err"
  stray
  run_guard "gh pr merge $t"
  [ "$st" -eq 2 ] || fail "S340/b/$t — stray Closes not blocked (status $st): $out"
  assert_contains "S340/b/$t — names the stray issue" "#999" "$err"
done

# (d) ambiguous: each check warns for itself, one list call per check.
all_in_one
printf '41\tfeature/work\n52\tfeature/work\n' > "$D/list"
run_guard "gh pr merge feature/work" "$yes_project"
[ "$st" -eq 0 ] || fail "S340/d — ambiguity did not fail open (status $st): $out"
assert_contains "S340/d — up-to-date warns" "skips the up-to-date check" "$err"
assert_contains "S340/d — role-play warns" "skips the role-play check" "$err"
assert_contains "S340/d — stray-Closes warns" "skips the stray-Closes check" "$err"
[ "$(grep -c '^api repos/{owner}/{repo}/pulls --paginate' "$calls")" -eq 3 ] \
  || fail "S340/d — expected one list call per check (3): $(cat "$calls")"

test_done
