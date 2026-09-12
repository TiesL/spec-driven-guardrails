#!/usr/bin/env bash
# S84 — install.sh installs a pinned version, not the current main.
# Covers: F17

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# Given: a sandbox copy of this repo, with its own git history and a
# tag on the "old" state, followed by a commit that changes WORKFLOW.md —
# so a successful pin demonstrably returns the old content, not the
# new one.
repo="$(sandbox_copy_repo)"
git -C "$repo" init -q -b main
git -C "$repo" -c user.name=test -c user.email=test@example.invalid \
  add -A
git -C "$repo" -c user.name=test -c user.email=test@example.invalid \
  commit -q -m "oude versie"
git -C "$repo" tag oude-versie

echo "NIEUWE INHOUD DIE NIET GEPIND MAG WORDEN" >> "$repo/WORKFLOW.md"
git -C "$repo" -c user.name=test -c user.email=test@example.invalid \
  add -A
git -C "$repo" -c user.name=test -c user.email=test@example.invalid \
  commit -q -m "nieuwe versie"

old_commit="$(git -C "$repo" rev-parse oude-versie)"

# When: install.sh runs with an explicit, existing tag.
output="$(cd "$repo" && ./install.sh oude-versie 2>&1)"
status=$?

# Then: HEAD is on the pinned commit, not the new one.
[ "$status" -eq 0 ] || fail "S84 — install.sh with a valid tag gave exit status $status: $output"
current_commit="$(git -C "$repo" rev-parse HEAD)"
[ "$current_commit" = "$old_commit" ] \
  || fail "S84 — after install.sh oude-versie, HEAD is not on the pinned commit"
if grep -q "NIEUWE INHOUD" "$repo/WORKFLOW.md"; then
  fail "S84 — WORKFLOW.md still contains the newer content after the pin"
fi

# And: a dirty working directory is refused, without checking out anything.
echo "local, uncommitted change" >> "$repo/README.md"
dirty_output="$(cd "$repo" && ./install.sh oude-versie 2>&1)"
dirty_status=$?
[ "$dirty_status" -ne 0 ] || fail "S84 — install.sh with a dirty working directory was not refused"
assert_contains "S84 — the refusal names the uncommitted changes" "uncommitted changes" "$dirty_output"
git -C "$repo" checkout -q -- README.md

# And: an unknown tag fails with a clear message.
unknown_output="$(cd "$repo" && ./install.sh nonexistent-tag 2>&1)"
unknown_status=$?
[ "$unknown_status" -ne 0 ] || fail "S84 — an unknown tag was not refused"
assert_contains "S84 — the message says the tag does not exist" "doesn't exist" "$unknown_output"

# And: without an argument, the latest tag is used, reported explicitly.
without_arg_output="$(cd "$repo" && ./install.sh 2>&1)"
without_arg_status=$?
[ "$without_arg_status" -eq 0 ] || fail "S84 — install.sh without an argument failed: $without_arg_output"
assert_contains "S84 — without an argument, install.sh reports which tag it chose" "oude-versie" "$without_arg_output"

test_done
