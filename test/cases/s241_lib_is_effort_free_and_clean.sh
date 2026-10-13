#!/usr/bin/env bash
# S241 — the shared lib no longer mentions effort at all, and its comments carry no stray `;;`.
# Covers: F39, F40
#
# Issue #424, review round 1 of PR #447 (finding pr447-lib-comment-typo-and-
# effort-word; QA round 1 Developer note 2: "do not even mention the word in
# lib/model-record.sh"). Seam: the text of lib/*.sh.
#   - no file under lib/ contains the word effort in any case or form (a
#     comment included): effort left the marker pipeline (A33), and the
#     Developer's report says the word is gone from the lib. The two scripts
#     that still READ legacy effort attributes do so without naming it in the
#     lib; the legacy fixtures live in test/.
#   - a pure comment line (first non-blank character `#`) contains no `;;`: a
#     doubled semicolon in prose is a typo; `;;` ends a case arm only in
#     code, never inside a comment. (Comment lines only: a case arm's own `;;`
#     followed by a trailing comment is code and is not looked at.)

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

root="$TEST_REPO_ROOT"
[ -d "$root/lib" ] || { fail "S241 — lib/ is missing"; test_done; }
found=0
for f in "$root"/lib/*.sh; do
  [ -f "$f" ] || continue
  found=$((found + 1))
  rel="lib/${f##*/}"
  hit="$(LC_ALL=C grep -n -i 'effort' "$f" | cut -c1-140 | head -3)"
  [ -z "$hit" ] || fail "S241 — $rel still mentions effort: $hit"
  typo="$(LC_ALL=C grep -n -E '^[[:space:]]*#.*;;' "$f" | cut -c1-140 | head -3)"
  [ -z "$typo" ] || fail "S241 — $rel has a comment line with a doubled semicolon: $typo"
done
[ "$found" -ge 3 ] || fail "S241 — found only $found files under lib/: the scan would be vacuous"

test_done
