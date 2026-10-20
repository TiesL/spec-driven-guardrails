#!/usr/bin/env bash
# S324-S329 — the merge guard refuses a PR that is behind its base, fails open on lookup trouble, and names update-branch, never a force-push (#516 AC1-AC3; A43)
# Covers: F8
#
# Seam: `gh` on PATH (fake_gh_merge_bin with a behind_by answer, or a
# per-case fake_gh_bin for error shapes), the guard run through PreToolUse
# JSON as in S119. S329 is the regression half: the older fakes, which
# answer no `gh api` call, stay green; their own case files run unchanged.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

guard="$TEST_REPO_ROOT/hooks/git-guardrails"
[ -x "$guard" ] || { fail "S324 — hooks/git-guardrails is missing"; test_done; }

sandbox_create
trap sandbox_destroy EXIT

project="$(fresh_project up-to-date)"
git -C "$project" commit -q --allow-empty -m start
git -C "$project" checkout -q -b feature/work

green='[{"name":"check","bucket":"pass"}]'
head_sha="1111111111111111111111111111111111111111"
calls="$SANDBOX/fakegh/calls.log"

# run_guard <guard> <PATH prefix or "-" for an exact PATH> <command>
# Sets out (stderr+stdout), err (stderr only), st.
run_guard() {
  local g="$1" p="$2" cmd="$3" input path errf
  input='{"tool_name":"Bash","cwd":"'"$project"'","tool_input":{"command":"'"$cmd"'"}}'
  case "$p" in
    -*) path="${p#-}" ;;
    *) path="$p:$PATH" ;;
  esac
  errf="$SANDBOX/err.txt"
  rm -f "$calls"
  out="$(printf '%s' "$input" | PATH="$path" "$g" 2>"$errf")"; st=$?
  err="$(cat "$errf")"
  out="$out$err"
}

# --- S324: behind, for every base -------------------------------------------
for base in main release/40-epic develop; do
  for n in 3 1; do
    fb="$(fake_gh_merge_bin match "$green" "$n" "$base")"
    run_guard "$guard" "$fb" "gh pr merge"
    [ "$st" -eq 2 ] || fail "S324/$base/$n — a PR $n behind '$base' was not blocked (status $st): $out"
    assert_contains "S324/$base/$n — names the base" "$base" "$err"
    assert_contains "S324/$base/$n — names the count" "$n commit" "$err"
    assert_contains "S324/$base/$n — names the remedy" "gh pr update-branch 41" "$err"
  done
done

# Runs before the marker lookup: no marker and behind 3 shows the up-to-date block.
fb="$(fake_gh_merge_bin "" "$green" 3 main)"
run_guard "$guard" "$fb" "gh pr merge"
[ "$st" -eq 2 ] || fail "S324/order — no marker and behind 3 was not blocked (status $st): $out"
assert_contains "S324/order — the up-to-date block is the one shown" "behind its base" "$err"
case "$err" in *"review marker"*) fail "S324/order — the review-marker block was shown first: $err" ;; esac
grep -q '^pr view' "$calls" && fail "S324/order — the marker lookup ran before the up-to-date block"

# Negative control: a main-only filter in a copy fails the release/* and develop cases by name.
mut="$SANDBOX/mut/hooks"
mkdir -p "$mut"
cp "$TEST_REPO_ROOT"/hooks/* "$mut/" 2>/dev/null
sed 's/^\(  *\)\[ "\$behind" -eq 0 \] && return 0$/&\
\1[ "$base_ref" = main ] || return 0/' "$guard" > "$mut/git-guardrails"
chmod +x "$mut/git-guardrails"
grep -q '\[ "\$base_ref" = main \] || return 0' "$mut/git-guardrails" \
  || fail "S324/neg — the main-only mutation did not apply (anchor line moved)"
for base in release/40-epic develop; do
  fb="$(fake_gh_merge_bin match "$green" 3 "$base")"
  run_guard "$mut/git-guardrails" "$fb" "gh pr merge"
  [ "$st" -ne 2 ] || fail "S324/neg/$base — a main-only filter still blocked '$base' (control broken)"
done
fb="$(fake_gh_merge_bin match "$green" 3 main)"
run_guard "$mut/git-guardrails" "$fb" "gh pr merge"
[ "$st" -eq 2 ] || fail "S324/neg/main — the mutant no longer blocks main either (control broken)"

# --- S325: up to date passes, paired with 1 behind ---------------------------
for base in main release/40-epic; do
  fb="$(fake_gh_merge_bin match "$green" 0 "$base")"
  run_guard "$guard" "$fb" "gh pr merge"
  [ "$st" -eq 0 ] || fail "S325/$base — an up-to-date PR (behind_by 0) was blocked (status $st): $out"
  case "$err" in *"behind its base"*) fail "S325/$base — up-to-date message shown for behind_by 0: $err" ;; esac
  grep -q "/compare/$base\.\.\.$head_sha" "$calls" || fail "S325/$base — the compare call did not use the PR's own base.ref and head.sha: $(cat "$calls")"
done
fb="$(fake_gh_merge_bin match "$green" 1 main)"
run_guard "$guard" "$fb" "gh pr merge"
[ "$st" -eq 2 ] || fail "S325/pair — the same fake with behind_by 1 was not blocked"

# --- S326: fail open with a warning, per check -------------------------------
# fake_case <behind answer shape> <marker: match|none>: builds an error-shape fake.
fake_case() {
  local shape="$1" marker="$2" body
  case "$marker" in
    match) body="findings\\\\n<!-- pre-merge-review:done sha=$head_sha -->" ;;
    *) body="no marker here" ;;
  esac
  local pull='printf "main\t'"$head_sha"'\n"; exit 0'
  local list='printf "41\tfeature/work\n"; exit 0'
  local compare
  case "$shape" in
    pull-fails) pull='echo "HTTP 502" >&2; exit 1'; compare='exit 0' ;;
    compare-fails) compare='echo "HTTP 404: No common ancestor" >&2; exit 1' ;;
    empty) compare='exit 0' ;;
    garbage) compare='printf "garbage\n"; exit 0' ;;
    no-number) list='exit 1'; compare='printf "3\n"; exit 0' ;;
    noisy) compare='echo "a routine gh notice 7" >&2; printf "0\n"; exit 0' ;;
  esac
  fake_gh_bin '
printf "%s\n" "$*" >> "$(dirname "$0")/calls.log"
case "$*" in
  "pr view --json comments,headRefOid")
    printf "%s" "{\"headRefOid\":\"'"$head_sha"'\",\"comments\":[{\"body\":\"'"$body"'\"}]}"; exit 0 ;;
  "pr checks --json bucket,name")
    printf "%s" "[{\"name\":\"check\",\"bucket\":\"pass\"}]"; exit 0 ;;
  "api repos/{owner}/{repo}/pulls --paginate --jq "*) '"$list"' ;;
  "api repos/{owner}/{repo}/pulls/41 --jq .base.ref"*) '"$pull"' ;;
  "api repos/{owner}/{repo}/compare/"*) '"$compare"' ;;
esac
exit 1'
}

for shape in pull-fails compare-fails empty garbage no-number; do
  fb="$(fake_case "$shape" match)"
  run_guard "$guard" "$fb" "gh pr merge"
  [ "$st" -eq 0 ] || fail "S326/$shape — a lookup failure did not fail open (status $st): $out"
  assert_contains "S326/$shape — warns" "warning:" "$err"
  assert_contains "S326/$shape — names the skipped check" "skips the up-to-date check" "$err"
  # Per-check fail-open: a missing marker in the same case still blocks.
  fb="$(fake_case "$shape" none)"
  run_guard "$guard" "$fb" "gh pr merge"
  [ "$st" -eq 2 ] || fail "S326/$shape/no-marker — fail-open skipped the other checks too (status $st): $out"
  assert_contains "S326/$shape/no-marker — the marker block still applies" "review marker" "$err"
done

# gh absent from PATH: fails open, and the warning names the up-to-date check.
run_guard "$guard" "-$(path_without_gh)" "gh pr merge"
[ "$st" -eq 0 ] || fail "S326/no-gh — gh missing was blocked (status $st): $out"
assert_contains "S326/no-gh — names the skipped check" "up-to-date" "$err"

# Separate streams: stderr noise holding a digit does not change behind_by 0.
fb="$(fake_case noisy match)"
run_guard "$guard" "$fb" "gh pr merge"
[ "$st" -eq 0 ] || fail "S326/noisy — stderr noise from gh corrupted behind_by (status $st): $out"

# --- S327: escape hatch and substantiated no make no gh api call -------------
fb="$(fake_gh_merge_bin match "$green" 3 main)"
run_guard "$guard" "$fb" "CLAUDE_WORKFLOW_MERGE_GUARD_OFF=1 gh pr merge"
[ "$st" -eq 0 ] || fail "S327/a — the escape hatch did not skip the up-to-date check (status $st): $out"
assert_contains "S327/a — loudly reports the skip" "explicitly skipped" "$err"
assert_contains "S327/a — names the up-to-date check as skipped" "up-to-date" "$err"
{ [ -f "$calls" ] && grep -q '^api ' "$calls"; } && fail "S327/a — a gh api call was made under the escape hatch: $(cat "$calls")"

cat > "$project/WORKFLOW-ADOPTION.md" <<'EOF'
# Adoption of shared workflow changes

| Change | Answer | Date | Notes |
|---|---|---|---|
| quality-review-before-merge | no | 2026-01-01 | single-person project without PRs |
EOF
fb="$(fake_gh_merge_bin match "$green" 3 main)"
run_guard "$guard" "$fb" "gh pr merge"
[ "$st" -eq 0 ] || fail "S327/b — a substantiated no did not skip the up-to-date check (status $st): $out"
{ [ -f "$calls" ] && grep -q '^api ' "$calls"; } && fail "S327/b — a gh api call was made under a substantiated no: $(cat "$calls")"
rm -f "$project/WORKFLOW-ADOPTION.md"

fb="$(fake_gh_merge_bin match "$green" 3 main)"
run_guard "$guard" "$fb" "gh pr merge"
[ "$st" -eq 2 ] || fail "S327/c — neither escape applied, yet not blocked (status $st)"
assert_contains "S327/c — the block names the merge-guard escape hatch" "CLAUDE_WORKFLOW_MERGE_GUARD_OFF=1" "$err"

# --- S328: the remedy is update-branch, never a force-push -------------------
for base in main release/40-epic develop; do
  fb="$(fake_gh_merge_bin match "$green" 3 "$base")"
  run_guard "$guard" "$fb" "gh pr merge"
  assert_contains "S328/$base — names update-branch" "gh pr update-branch" "$err"
  for bad in "--force" "push -f" "--force-with-lease" "reset --hard"; do
    case "$err" in *"$bad"*) fail "S328/$base — the block message suggests '$bad': $err" ;; esac
  done
  assert_contains "S328/$base — says to wait for CI on the new head" "CI" "$err"
  assert_contains "S328/$base — says to re-run the pre-merge review" "pre-merge review" "$err"
done

# --- S329: older fakes (no gh api answers) stay green and quiet --------------
fb="$(fake_gh_merge_bin match "")"
run_guard "$guard" "$fb" "gh pr merge"
[ "$st" -eq 0 ] || fail "S329 — an older-style fake (no gh api branch) was blocked (status $st): $out"
fb="$(fake_gh_merge_bin "" "")"
run_guard "$guard" "$fb" "gh pr merge"
[ "$st" -eq 2 ] || fail "S329 — an older-style fake without marker no longer blocks (status $st)"
assert_contains "S329 — the older block is still the marker block" "review marker" "$err"

test_done
