#!/usr/bin/env bash
# S85 — A pre-migration project is reported per row, with a tracking issue.
# Covers: F6, W42/#114

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# Given: a real git project, with its own github.com origin (the target the
# tracking issue must be pinned to — see the git-root-only case further
# down for what happens without one), and an old-format answer file with
# two answered rows (one ja, one nee) that are not otherwise pending.
project="$(fresh_project pre-migration)"
git -C "$project" remote add origin 'https://github.com/example-org/pre-migratie.git'
cat > "$project/WORKFLOW-ADOPTIE.md" <<'EOF'
# Adoption of shared workflow changes

| Change | Answer | Date | Notes |
|---|---|---|---|
| ci-convention | ja | 2026-01-01 | outdated answer |
| deploy-guards | nee | 2026-01-01 | outdated answer |
EOF

# A fake gh that reports no matching existing issue and records the exact
# calls made — including the -R flag, to prove the target repo is pinned
# explicitly rather than left to gh's own cwd/GH_REPO-based detection.
gh_log="$SANDBOX/gh-calls.txt"
: > "$gh_log"
fakebin="$(fake_gh_bin '
echo "$*" >> "'"$gh_log"'"
case "$*" in
  "issue list -R github.com/example-org/pre-migratie --state open --limit 200 --json body --jq .[].body")
    printf ""
    exit 0 ;;
  "issue create -R github.com/example-org/pre-migratie --title "*)
    exit 0 ;;
esac
exit 1
')"

# When: pending-changes.sh runs.
output="$(PATH="$fakebin:$PATH" "$TEST_REPO_ROOT/pending-changes.sh" "$project" 2>&1)"

# Then: each old-format row is named individually, with a bullet that does
# not collide with the pending-question list's own "  - " prefix (that
# prefix is what test/lib.sh's pending_ids() greps for).
assert_contains "S85 — mentions the pre-migration notice" "pre-migration format" "$output"
assert_contains "S85 — names ci-convention" "* ci-convention" "$output"
assert_contains "S85 — names deploy-guards" "* deploy-guards" "$output"
# <<< here-string, not a piped printf | grep -q: SIGPIPE/pipefail race,
# see issue #218. Scoped to the "Pending workflow changes" block itself
# (#258, same fix as test/lib.sh's pending_ids()): ci-convention's own
# "Applies if" narrowed since (#248), so with no package.json/check in
# this fixture it now legitimately appears under the separate "may no
# longer be asked" report below — that's a different, correct signal,
# not the bug this check exists to catch.
pending_block="$(awk '
  /^Pending workflow changes for this project/ { in_block = 1; next }
  in_block && /^  - / { print; next }
  { in_block = 0 }
' <<<"$output")"
if grep -qE '^  - (ci-convention|deploy-guards)( |$)' <<<"$pending_block"; then
  fail "S85 — an already-answered old-format row was listed as a pending question"
fi

# And: those two rows do not appear in the pending set at all — they have
# real answers, just in the old vocabulary.
#
# pending_ids() calls pending-changes.sh itself, with no PATH override
# of its own — this is exactly the kind of call this test exists to catch:
# without a fake gh here, it would reach a real `gh` again. A dedicated
# fake that reports the marker as already present, so it can never create
# an issue, keeps this check from perturbing the $gh_log count asserted
# on below.
actual="$SANDBOX/actual.txt"
fakebin_readonly="$(fake_gh_bin '
case "$*" in
  "issue list -R github.com/example-org/pre-migratie --state open --limit 200 --json body --jq .[].body")
    printf "<!-- workflow-adoptie-migratie -->"
    exit 0 ;;
esac
exit 1
')"
PATH="$fakebin_readonly:$PATH" pending_ids "$project" > "$actual"
if grep -qx 'ci-convention' "$actual" || grep -qx 'deploy-guards' "$actual"; then
  fail "S85 — an already-answered old-format row was swept into the pending ID set"
fi

# And: a tracking issue was filed, pinned explicitly to the project's own
# repo via -R (not left to gh's cwd/GH_REPO-based detection).
assert_contains "S85 — reports the tracking issue" "Filed a tracking issue" "$output"
[ "$(grep -c '^issue create' "$gh_log")" -eq 1 ] \
  || fail "S85 — expected exactly one 'gh issue create' call, got $(grep -c '^issue create' "$gh_log")"
grep -q 'ci-convention' "$gh_log" || fail "S85 — the issue body/title does not mention ci-convention"
grep -q -- '-R github.com/example-org/pre-migratie' "$gh_log" \
  || fail "S85 — gh was not called with an explicit -R for the project's own repo"

# When: pending-changes.sh runs again, but this time an open issue with the
# marker already exists.
gh_log2="$SANDBOX/gh-calls-2.txt"
: > "$gh_log2"
fakebin2="$(fake_gh_bin '
echo "$*" >> "'"$gh_log2"'"
case "$*" in
  "issue list -R github.com/example-org/pre-migratie --state open --limit 200 --json body --jq .[].body")
    printf "bestaande body\\n<!-- workflow-adoptie-migratie -->"
    exit 0 ;;
  "issue create -R github.com/example-org/pre-migratie --title "*)
    exit 0 ;;
esac
exit 1
')"
PATH="$fakebin2:$PATH" "$TEST_REPO_ROOT/pending-changes.sh" "$project" > /dev/null 2>&1

# Then: no second issue gets created — idempotent, marker-driven.
[ "$(grep -c '^issue create' "$gh_log2")" -eq 0 ] \
  || fail "S85 — a second tracking issue was created even though one already exists"

# When: the idempotency lookup itself fails (bad token, network, rate
# limit) rather than succeeding with no marker found.
gh_log3="$SANDBOX/gh-calls-3.txt"
: > "$gh_log3"
fakebin3="$(fake_gh_bin '
echo "$*" >> "'"$gh_log3"'"
case "$*" in
  "issue list -R github.com/example-org/pre-migratie --state open --limit 200 --json body --jq .[].body")
    echo "HTTP 401 Bad credentials" >&2
    exit 1 ;;
  "issue create -R github.com/example-org/pre-migratie --title "*)
    exit 0 ;;
esac
exit 1
')"
output3="$(PATH="$fakebin3:$PATH" "$TEST_REPO_ROOT/pending-changes.sh" "$project" 2>&1)"

# Then: a failed lookup must never be treated as "no marker found" — that
# would file a duplicate tracking issue every session the lookup happens
# to fail. Fail closed instead: skip, don't create, report the failure.
[ "$(grep -c '^issue create' "$gh_log3")" -eq 0 ] \
  || fail "S85 — a transient 'gh issue list' failure still created an issue (possible duplicate)"
assert_contains "S85 — reports the lookup failure" "could not check for an existing" "$output3"

# And: a project directory that is not its own git root (e.g. a directory
# nested inside a different repo, like the frozen baseline fixtures) never
# triggers a gh call at all — never write to the wrong repository, and this
# holds regardless of GH_REPO being set in the environment.
nested_dir="$project/inside"
mkdir -p "$nested_dir"
cp "$project/WORKFLOW-ADOPTIE.md" "$nested_dir/WORKFLOW-ADOPTIE.md"
gh_log4="$SANDBOX/gh-calls-4.txt"
: > "$gh_log4"
fakebin4="$(fake_gh_bin '
echo "$*" >> "'"$gh_log4"'"
exit 1
')"
PATH="$fakebin4:$PATH" GH_REPO="TiesL/spec-driven-guardrails" \
  "$TEST_REPO_ROOT/pending-changes.sh" "$nested_dir" > /dev/null 2>&1
[ -s "$gh_log4" ] && fail "S85 — gh was called for a directory that is not its own git root"

# And: a project with no github.com origin at all (true for every
# sandboxed test project, and for a project that has never been pushed
# anywhere) never calls gh either — there is nothing to pin -R to, and
# guessing would reintroduce the exact ambiguity -R exists to remove.
without_remote="$(fresh_project without-remote)"
cp "$project/WORKFLOW-ADOPTIE.md" "$without_remote/WORKFLOW-ADOPTIE.md"
gh_log5="$SANDBOX/gh-calls-5.txt"
: > "$gh_log5"
fakebin5="$(fake_gh_bin '
echo "$*" >> "'"$gh_log5"'"
exit 1
')"
PATH="$fakebin5:$PATH" "$TEST_REPO_ROOT/pending-changes.sh" "$without_remote" > /dev/null 2>&1
[ -s "$gh_log5" ] && fail "S85 — gh was called for a project with no github.com origin remote"

test_done
