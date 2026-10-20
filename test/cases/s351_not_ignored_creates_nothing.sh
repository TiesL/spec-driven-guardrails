#!/usr/bin/env bash
# S351 — without a gitignore entry nothing is created, per name; warning text intact.
# Covers: F6, F9

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../skill-links-fixture.sh
. "$(dirname "${BASH_SOURCE[0]}")/../skill-links-fixture.sh"

sandbox_create
trap sandbox_destroy EXIT

# (a) managed block deleted, directory present and absent
for variant in present absent; do
  sl_make "s351a-$variant" pre-merge-review deploy-guards
  : > "$SL_PROJECT/.gitignore"
  [ "$variant" = absent ] && rm -rf "$SL_PROJECT/.claude/skills"
  sl_run
  [ ! -L "$SL_PROJECT/.claude/skills/pre-merge-review" ] || fail "S351a($variant) — link created without ignore"
  sl_assert_nothing_created "S351a($variant)"
  sl_assert_warns "S351a($variant)" "deploy-guards, pre-merge-review"
  # alphabetic glob order: deploy-guards first
  sl_assert_quiet "S351a($variant)"
  grep -q 'pre-merge-review' "$SL_OUT" && grep -q 'deploy-guards' "$SL_OUT" || fail "S351a($variant) — names missing"
done
# after manual install the warning disappears
mkdir -p "$SL_PROJECT/.claude/skills"
ln -s "$SL_REPO/skills/pre-merge-review" "$SL_PROJECT/.claude/skills/pre-merge-review"
ln -s "$SL_REPO/skills/deploy-guards" "$SL_PROJECT/.claude/skills/deploy-guards"
sl_run
sl_assert_no_warning "S351a after manual install"

# (b) per-name negation: b is not ignored, a and c are
sl_make s351b a b c
rm -rf "$SL_PROJECT/.claude/skills"
printf '.claude/skills/*\n!.claude/skills/b\n' > "$SL_PROJECT/.gitignore"
sl_run
sl_assert_created "S351b" a
sl_assert_created "S351b" c
[ ! -e "$SL_PROJECT/.claude/skills/b" ] || fail "S351b — b created although not ignored"
sl_assert_warns "S351b" "b"
sl_assert_quiet "S351b"

# (c) ignore only via .git/info/exclude
sl_make s351c a b
rm -rf "$SL_PROJECT/.claude/skills"
: > "$SL_PROJECT/.gitignore"
echo '.claude/skills/' >> "$SL_PROJECT/.git/info/exclude"
sl_run
sl_assert_created "S351c" a
sl_assert_created "S351c" b
sl_assert_no_warning "S351c"
sl_assert_quiet "S351c"

test_done
