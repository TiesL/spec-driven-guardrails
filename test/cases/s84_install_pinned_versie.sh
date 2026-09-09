#!/usr/bin/env bash
# S84 — install.sh installs a pinned version, not the current main.
# Dekt: F17

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

oude_commit="$(git -C "$repo" rev-parse oude-versie)"

# When: install.sh runs with an explicit, existing tag.
uitvoer="$(cd "$repo" && ./install.sh oude-versie 2>&1)"
status=$?

# Then: HEAD is on the pinned commit, not the new one.
[ "$status" -eq 0 ] || fail "S84 — install.sh with a valid tag gave exit status $status: $uitvoer"
huidige_commit="$(git -C "$repo" rev-parse HEAD)"
[ "$huidige_commit" = "$oude_commit" ] \
  || fail "S84 — after install.sh oude-versie, HEAD is not on the pinned commit"
if grep -q "NIEUWE INHOUD" "$repo/WORKFLOW.md"; then
  fail "S84 — WORKFLOW.md still contains the newer content after the pin"
fi

# And: a dirty working directory is refused, without checking out anything.
echo "lokale, niet-gecommitte wijziging" >> "$repo/README.md"
vies_uitvoer="$(cd "$repo" && ./install.sh oude-versie 2>&1)"
vies_status=$?
[ "$vies_status" -ne 0 ] || fail "S84 — install.sh with a dirty working directory was not refused"
assert_contains "S84 — the refusal names the uncommitted changes" "wijziging" "$vies_uitvoer"
git -C "$repo" checkout -q -- README.md

# And: an unknown tag fails with a clear message.
onbekend_uitvoer="$(cd "$repo" && ./install.sh deze-tag-bestaat-niet 2>&1)"
onbekend_status=$?
[ "$onbekend_status" -ne 0 ] || fail "S84 — an unknown tag was not refused"
assert_contains "S84 — the message says the tag does not exist" "bestaat niet" "$onbekend_uitvoer"

# And: without an argument, the latest tag is used, reported explicitly.
zonder_arg_uitvoer="$(cd "$repo" && ./install.sh 2>&1)"
zonder_arg_status=$?
[ "$zonder_arg_status" -eq 0 ] || fail "S84 — install.sh without an argument failed: $zonder_arg_uitvoer"
assert_contains "S84 — without an argument, install.sh reports which tag it chose" "oude-versie" "$zonder_arg_uitvoer"

test_klaar
