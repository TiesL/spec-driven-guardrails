#!/usr/bin/env bash
# S19 through S23 — adopt.sh installs skills and manages the .gitignore block.
# Covers: F9
#
# This work item writes into other repos and migrates a tracked .gitignore.
# Everything below runs against sandbox fixtures; the four real projects are
# never touched.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# A copy of this repo, so a test may add skills without touching the real
# checkout.
source="$(sandbox_copy_repo)"
mkdir -p "$source/skills/pre-merge-review" "$source/skills/tdd-seams"
echo "# review" > "$source/skills/pre-merge-review/SKILL.md"
echo "# seams"  > "$source/skills/tdd-seams/SKILL.md"

adopt_from() {
  SPEC_DRIVEN_GUARDRAILS_DIR="$1" "$1/adopt.sh" "$2" >/dev/null 2>&1
}

# Same, but with the output visible and the exit status usable.
adopt_from_loud() {
  SPEC_DRIVEN_GUARDRAILS_DIR="$1" "$1/adopt.sh" "$2"
}

# The markers as adopt.sh writes them, read from the script itself instead of
# retyped here - otherwise this test would be checking its own copy.
GITIGNORE_BEGIN="$(sed -n 's/^GITIGNORE_BEGIN="\(.*\)"$/\1/p' "$source/adopt.sh")"
GITIGNORE_END="$(sed -n 's/^GITIGNORE_END="\(.*\)"$/\1/p' "$source/adopt.sh")"
[ -n "$GITIGNORE_BEGIN" ] && [ -n "$GITIGNORE_END" ] \
  || fail "S21 — the markers cannot be read from adopt.sh"

# --- S19 -------------------------------------------------------------------
project="$(fresh_project s19)"
adopt_from "$source" "$project"

skills="$project/.claude/skills"
[ -d "$skills" ] || fail "S19 — .claude/skills was not created"
if [ -L "$skills" ]; then
  fail "S19 — .claude/skills is itself a symlink, which makes the namespace owned by claude-workflow"
fi

for name in pre-merge-review tdd-seams; do
  [ -L "$skills/$name" ] || fail "S19 — $name is not a symlink"
  target="$(readlink "$skills/$name")"
  case "$target" in
    "$source"/skills/*) ;;
    *) fail "S19 — $name points to $target, not to the repo's skills directory" ;;
  esac
done

# --- S20 -------------------------------------------------------------------
# An orphaned symlink: points to a skill that no longer exists. That is not
# inert - Claude Code reports a load error for it every session, in four
# projects at once.
mkdir -p "$skills"
ln -s "$source/skills/gone" "$skills/gone"
mkdir -p "$skills/own-skill"
echo "# from the project itself" > "$skills/own-skill/SKILL.md"
# And two symlinks the project itself placed elsewhere: not ours, so not ours
# to clean up. The second one is deliberately dead - only that one proves the
# prefix check actually works. If a foreign link points at something that
# still exists, it's luck protecting it, not the prefix check.
mkdir -p "$SANDBOX/elders/foreign-skill"
ln -s "$SANDBOX/elders/foreign-skill" "$skills/foreign-skill"
ln -s "$SANDBOX/elders/never-existed" "$skills/weird-dead-skill"

adopt_from "$source" "$project"

if [ -e "$skills/gone" ] || [ -L "$skills/gone" ]; then
  fail "S20 — the orphaned symlink 'gone' was left in place"
fi
[ -d "$skills/own-skill" ] || fail "S20 — the project's own 'own-skill' directory was removed"
[ -f "$skills/own-skill/SKILL.md" ] || fail "S20 — the contents of 'own-skill' are gone"
[ -L "$skills/foreign-skill" ] || fail "S20 — a symlink outside this repo was cleaned up; only our own orphaned links may be removed"
[ -L "$skills/weird-dead-skill" ] || fail "S20 — a dead symlink outside this repo was cleaned up; the criterion is the target, not whether the link works"

# A dead orphan with a relative path. Without first resolving the path
# meaningfully, it falls outside the prefix check and stays forever - and then
# Claude Code reports a load error for it every session.
ln -s "$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$source/skills/also-gone" "$skills")" "$skills/relative-orphan"
adopt_from "$source" "$project"
if [ -e "$skills/relative-orphan" ] || [ -L "$skills/relative-orphan" ]; then
  fail "S20 — an orphaned symlink with a relative path was left in place"
fi

# --- S21 -------------------------------------------------------------------
# The most dangerous case, modeled on the real tennis-admin: rules that
# exclude nested git repos. If those disappear, git suddenly sees two entire
# repos as untracked content.
project="$(fresh_project s21)"
cat > "$project/.gitignore" <<'IGNORE'
tennis-registration/
tennis-invoicing/
.DS_Store
CLAUDE.md
.claude/settings.json

# clasp link is machine-specific
.clasp.json
IGNORE
before="$(cat "$project/.gitignore")"

adopt_from "$source" "$project"
after="$project/.gitignore"

for line in "tennis-registration/" "tennis-invoicing/" ".DS_Store" ".clasp.json"; do
  grep -qxF "$line" "$after" || fail "S21 — the existing rule '$line' disappeared from .gitignore"
done
grep -q '^# clasp link is machine-specific$' "$after" \
  || fail "S21 — a comment line outside the block disappeared"

# Blank lines in the middle of the file separate groups. Discarding them is
# exactly the unsolicited rewriting of someone else's .gitignore that has no
# place here - and it is not theoretical: an earlier version of this script
# did it, and only a dry run against a copy of a real project surfaced that.
expected_heading="$(printf 'tennis-registration/\ntennis-invoicing/\n.DS_Store\n\n# clasp link is machine-specific\n.clasp.json')"
actual_heading="$(sed -n '1,6p' "$after")"
[ "$actual_heading" = "$expected_heading" ] \
  || fail "S21 — the content outside the block was rewritten:
$actual_heading"

# And the block appears exactly once, even after the second run.
markers="$(grep -c '^# claude-workflow: begin' "$after")"
[ "$markers" -eq 1 ] || fail "S21 — the managed block appears $markers times, expected 1"

for line in "CLAUDE.md" ".claude/settings.json"; do
  count="$(grep -cxF "$line" "$after")"
  [ "$count" -eq 1 ] || fail "S21 — '$line' appears $count times in .gitignore, expected 1"
done

# And they are inside the managed block, not as loose leftovers outside it.
inside="$(awk '/^# claude-workflow: begin/{i=1;next} /^# claude-workflow: end/{i=0} i' "$after")"
for line in "CLAUDE.md" ".claude/settings.json" ".claude/skills/"; do
  printf '%s\n' "$inside" | grep -qxF "$line" \
    || fail "S21 — '$line' is not inside the managed block"
done

# --- S21b: edge cases in the existing .gitignore ---------------------------
# The eight mutations above test what goes wrong if the script is built
# incorrectly. This block tests the other side: what goes wrong if the input
# has an edge case. That's where the heaviest bug was.

# A block with only a begin marker made an earlier version silently wipe
# everything after it. The file is tracked; silently plowing through it is
# the most expensive mistake this script can make.
project="$(fresh_project s21b-broken)"
printf 'important-line.txt\n%s\nCLAUDE.md\nline-after-broken-block\n' "$GITIGNORE_BEGIN" > "$project/.gitignore"
before="$(cat "$project/.gitignore")"
output="$(adopt_from_loud "$source" "$project" 2>&1)"; status=$?
[ "$status" -ne 0 ] || fail "S21b — a corrupted block was not rejected"
[ "$(cat "$project/.gitignore")" = "$before" ] \
  || fail "S21b — the file was touched while the block was corrupted"
assert_contains "S21b — the message explains what is wrong" "corrupted managed block" "$output"

# Nested: two begin markers before the first end marker. Counting alone is not
# enough, because the counts still match in that case.
project="$(fresh_project s21b-nested)"
printf 'x\n%s\n%s\nCLAUDE.md\n%s\n%s\n' "$GITIGNORE_BEGIN" "$GITIGNORE_BEGIN" "$GITIGNORE_END" "$GITIGNORE_END" > "$project/.gitignore"
before="$(cat "$project/.gitignore")"
adopt_from_loud "$source" "$project" >/dev/null 2>&1
[ "$?" -ne 0 ] || fail "S21b — a nested block was not rejected"
[ "$(cat "$project/.gitignore")" = "$before" ] || fail "S21b — the nested case still touched the file"

# CRLF and trailing spaces: the same rule as far as git is concerned, but not
# for an exact comparison. Without normalizing, the old rule stays alongside
# the new one.
project="$(fresh_project s21b-variants)"
printf 'CLAUDE.md\r\nCLAUDE.md   \nnode_modules/\n   \n*.log\n' > "$project/.gitignore"
adopt_from "$source" "$project"
count="$(grep -c 'CLAUDE.md' "$project/.gitignore")"
[ "$count" -eq 1 ] || fail "S21b — CLAUDE.md appears $count times; CRLF and whitespace variants were not migrated"

# A line with only spaces keeps its spaces. awk splits on whitespace, so NF is
# zero there - writing that back as an empty line is a change to content
# outside the block.
grep -q '^   $' "$project/.gitignore" \
  || fail "S21b — a whitespace-only line was rewritten to an empty line"

# .claude/skills/ belongs in the block: these are symlinks to an absolute path
# on this machine. Without this rule, every project ends up with a pile of
# untracked files after W9.
grep -qxF '.claude/skills/' "$project/.gitignore" \
  || fail "S21b — .claude/skills/ is not in the managed block"

# --- S22 -------------------------------------------------------------------
project="$(fresh_project s22)"
adopt_from "$source" "$project"
tree_one="$(cd "$project" && find . -not -path './.git/*' -not -name '.git' | sort)"
ignore_one="$(cat "$project/.gitignore")"

adopt_from "$source" "$project"
tree_two="$(cd "$project" && find . -not -path './.git/*' -not -name '.git' | sort)"
ignore_two="$(cat "$project/.gitignore")"

[ "$tree_one" = "$tree_two" ] || fail "S22 — the file tree differs after the second run"
[ "$ignore_one" = "$ignore_two" ] || fail "S22 — .gitignore differs after the second run"

# --- S23 -------------------------------------------------------------------
# A checkout without a skills/ directory: the installer lands before the
# content, so this is the normal state until W9 is done.
bare="$(sandbox_copy_repo bare)"
rm -rf "$bare/skills"
project="$(fresh_project s23)"
output="$(SPEC_DRIVEN_GUARDRAILS_DIR="$bare" "$bare/adopt.sh" "$project" 2>&1)"; status=$?
[ "$status" -eq 0 ] || fail "S23 — adoption without skills/ failed with exit $status: $output"
if [ -e "$project/.claude/skills" ]; then
  fail "S23 — an empty .claude/skills was left behind"
fi
[ -L "$project/CLAUDE.md" ] || fail "S23 — ordinary adoption stopped working without skills/"

test_done "S19-S23"
