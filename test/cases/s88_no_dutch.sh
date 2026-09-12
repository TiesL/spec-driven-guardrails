#!/usr/bin/env bash
# S88 — No Dutch outside layer C.
# Covers: F13

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

script="$TEST_REPO_ROOT/check-no-dutch.sh"
[ -x "$script" ] || { fail "S88 — check-no-dutch.sh is missing or not executable"; test_done; }

# Given: the real repo, as it stands today.
output="$("$script" "$TEST_REPO_ROOT" 2>&1)"; status=$?
[ "$status" -eq 0 ] || fail "S88 — the real repo is not clean: $output"

sandbox_create
trap sandbox_destroy EXIT

repo="$(sandbox_copy_repo)"

# When: a real, untranslated Dutch sentence is introduced in an ordinary
# file — proving the check is actually sensitive, not just accidentally
# green because nothing exercises it (red-before-green for this new
# mechanism itself).
echo "Dit wordt niet vertaald en dat moet gemeld worden." >> "$repo/README.md"
output_dirty="$("$script" "$repo" 2>&1)"; status_vuil=$?
[ "$status_vuil" -ne 0 ] || fail "S88 — a real Dutch sentence in README.md was not caught"
assert_contains "S88 — the offending file is named" "README.md" "$output_dirty"

# And: the same sentence in a permanently excluded file (layer C) is not
# reported — the exclusion is by design, not a gap.
echo "Dit wordt niet vertaald en dat moet gemeld worden." >> "$repo/ARCHITECTURE.md"
output_layer_c="$("$script" "$repo" 2>&1)"; status_laag_c=$?
case "$output_layer_c" in
  *"ARCHITECTURE.md"*) fail "S88 — a permanently excluded (layer C) file was reported anyway" ;;
esac
# README.md's own violation must still be reported — the exclusion list
# doesn't accidentally swallow everything.
[ "$status_laag_c" -ne 0 ] || fail "S88 — README.md's violation disappeared once another file was excluded"

# And: a file tracked as a pending exclusion is not reported either — a
# real, already-tracked gap isn't silently fixed by this check pretending
# it doesn't exist. Rather than relying on a real file currently on the
# pending list (that list is empty once #136/#137/#138 are all done, so
# hardcoding one here would make this test fragile against exactly that
# progress), inject a synthetic pending entry into the sandboxed script.
sed -i.bak "s|pending_uitgesloten=''|pending_uitgesloten='./NEP-PENDING.md'|" "$repo/check-no-dutch.sh"
rm -f "$repo/check-no-dutch.sh.bak"
echo "Dit wordt niet vertaald en dat moet gemeld worden." >> "$repo/NEP-PENDING.md"
output_pending="$("$repo/check-no-dutch.sh" "$repo" 2>&1)"
case "$output_pending" in
  *"NEP-PENDING.md"*) fail "S88 — a tracked-pending file was reported anyway" ;;
esac

# And: the script excludes itself from its own scan — its marker-word list
# is a necessary literal, not untranslated prose.
output_self="$("$script" "$repo" 2>&1)"
case "$output_self" in
  *"check-no-dutch.sh"*) fail "S88 — the script flagged itself for its own marker-word list" ;;
esac

test_done
