#!/usr/bin/env bash
# S284 — CHANGELOG.md has dated release sections that match the tags (#420, AC1).
# Covers: F15

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

r="$TEST_REPO_ROOT"
cl="$r/CHANGELOG.md"

# Headings, in order (version-neutral, #474): Unreleased first; the dated release
# headings after it in strictly descending numeric version order; the pinned
# v0.3.0, v0.2.1, v0.2.0 adjacent and in that relative order. Older sections
# (v0.1.0, ...) follow and are not asserted.
first="$(grep '^## ' "$cl" | head -n 1)"
[ "$first" = "## Unreleased" ] || fail "S284 — first '## ' heading is '$first', expected '## Unreleased'"
prev=""
pinned=""
while IFS= read -r h; do
  grep -Eq '^## v[0-9]+\.[0-9]+\.[0-9]+ — .+ \([0-9]{4}-[0-9]{2}-[0-9]{2}\)$' <<<"$h" || break
  ver="${h#\#\# v}"; ver="${ver%% *}"
  if [ -n "$prev" ]; then
    IFS=. read -r a1 a2 a3 <<<"$prev"; IFS=. read -r b1 b2 b3 <<<"$ver"
    if [ "$b1" -gt "$a1" ] || { [ "$b1" -eq "$a1" ] && { [ "$b2" -gt "$a2" ] || { [ "$b2" -eq "$a2" ] && [ "$b3" -ge "$a3" ]; }; }; }; then
      fail "S284 — heading v$ver is not strictly below v$prev (descending order)"
    fi
  fi
  prev="$ver"
  case "$ver" in 0.3.0|0.2.1|0.2.0) pinned="$pinned$ver " ;; esac
done < <(grep '^## ' "$cl" | tail -n +2)
[ "$pinned" = "0.3.0 0.2.1 0.2.0 " ] \
  || fail "S284 — pinned releases appear as '$pinned', expected '0.3.0 0.2.1 0.2.0 ' (adjacent, in order)"
# Adjacent: nothing between the pinned three.
mid="$(grep '^## ' "$cl" | sed -n '/^## v0\.3\.0 /,/^## v0\.2\.0 /p' | wc -l | tr -d ' ')"
[ "$mid" = 3 ] || fail "S284 — $mid headings from v0.3.0 to v0.2.0, expected exactly 3 (nothing between)"

# Each version heading: title and the tag date.
check_heading() {
  local ver="$1" date="$2" line
  line="$(grep "^## $ver " "$cl" | head -n 1)"
  grep -Eq "^## $ver — .+ \\($date\\)$" <<<"$line" \
    || fail "S284 — heading for $ver is '$line', expected '## $ver — <title> ($date)'"
}
check_heading 'v0\.3\.0' 2026-10-04
check_heading 'v0\.2\.1' 2026-10-03
check_heading 'v0\.2\.0' 2026-10-01

v030="$(changelog_section "$cl" '## v0.3.0')"
v021="$(changelog_section "$cl" '## v0.2.1')"
unrel="$(changelog_section "$cl" '## Unreleased')"
[ -n "$v030" ] || fail "S284 — CHANGELOG has no non-empty '## v0.3.0' section"
[ -n "$v021" ] || fail "S284 — CHANGELOG has no non-empty '## v0.2.1' section"

mentions() { grep -Eq "#$2([^0-9]|\$)" <<<"$1"; }

for n in 370 372 373 374 378 377; do
  mentions "$v021" "$n" || fail "S284 — v0.2.1 section does not mention #$n"
done
for n in 369 371 392 402 398; do
  mentions "$v021" "$n" && fail "S284 — v0.2.1 section mentions #$n, which belongs to v0.3.0"
  mentions "$v030" "$n" || fail "S284 — v0.3.0 section does not mention #$n"
done
for n in 370 378 377 417 407; do
  mentions "$v030" "$n" && fail "S284 — v0.3.0 section mentions #$n"
done

for h in 'Fix #378' 'Fix #377' 'Fix #371' 'Fix #392' 'Fix #402' 'Epic #370' 'Epic #369'; do
  grep -qF "$h" <<<"$unrel" && fail "S284 — Unreleased still holds the moved entry '$h'"
done

# S172 stays green on the real file and fails when its #378 line leaves v0.2.1.
sandbox_create
trap sandbox_destroy EXIT
bash "$r/test/cases/s172_docs_describe_commit_check_split.sh" >/dev/null 2>&1 \
  || fail "S284 — the retargeted S172 is not green on the real repo"
mkdir -p "$SANDBOX/copy"
( cd "$r" && tar --exclude=.git -cf - . ) | ( cd "$SANDBOX/copy" && tar -xf - )
grep -v '#378' "$r/CHANGELOG.md" > "$SANDBOX/copy/CHANGELOG.md"
if bash "$SANDBOX/copy/test/cases/s172_docs_describe_commit_check_split.sh" >/dev/null 2>&1; then
  fail "S284 — S172 stays green when the #378 line is removed from CHANGELOG.md"
fi

test_done
