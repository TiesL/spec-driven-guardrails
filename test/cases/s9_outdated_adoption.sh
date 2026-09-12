#!/usr/bin/env bash
# S9 — An outdated adoption reports itself.
# Covers: F6

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

repo="$(sandbox_copy_repo)"
# This scenario itself simulates the sequence "no skills -> skills exist, not
# yet installed". Since W9 the real checkout has a populated skills/,
# so remove that first — otherwise this scenario already starts in the second
# state and no longer tests its own first rule.
rm -rf "$repo/skills"
project="$(fresh_project doelproject)"
SPEC_DRIVEN_GUARDRAILS_DIR="$repo" "$repo/adopt.sh" "$project" >/dev/null 2>&1

# Beforehand: without a skills directory in the repo, nothing should be reported.
schoon="$SANDBOX/schoon.txt"
"$repo/pending-changes.sh" "$project" > "$schoon" 2>/dev/null
if grep -qi 'missing the skill' "$schoon"; then
  fail "S9 — message appeared even though this repo has no skills at all"
fi

# Given: the repo has skills, the project has not installed them.
mkdir -p "$repo/skills/pre-merge-review" "$repo/skills/deploy-guards"
echo "---" > "$repo/skills/pre-merge-review/SKILL.md"
echo "---" > "$repo/skills/deploy-guards/SKILL.md"

# When: a session starts.
uitvoer="$SANDBOX/uitvoer.txt"
"$repo/pending-changes.sh" "$project" > "$uitvoer" 2>/dev/null
status=$?

# Then: the hook reports that adopt.sh needs to run again.
grep -qi 'missing the skill' "$uitvoer" || {
  fail "S9 — no message about missing skills"
  cat "$uitvoer" >&2
}
grep -qi 'adopt.sh again' "$uitvoer" || fail "S9 — the message does not say what to do"

# And: multiple names are distinguishable from each other. Without a separator
# "deploy-guards pre merge review" cannot be read as two skills, one of which
# has a space in its name.
# Only look at the skills line: the question texts above themselves contain
# commas, so a grep over the whole output would always match.
skillregel="$(grep 'missing the skill' "$uitvoer")"
case "$skillregel" in
  *', '*) ;;
  *) fail "S9 — multiple missing skills are not separated: $skillregel" ;;
esac

# And: the missing skills are listed by name. Without those names the
# message is not usable — you would not know what is missing or why.
for skill in pre-merge-review deploy-guards; do
  grep -q "$skill" "$uitvoer" || fail "S9 — the message does not name the missing skill '$skill'"
done

# And: the session simply continues to start — a hook must never block.
[ "$status" -eq 0 ] || fail "S9 — pending-changes.sh gave status $status; that blocks a session"

# After installing the skills, the message disappears again.
mkdir -p "$project/.claude/skills"
ln -s "$repo/skills/pre-merge-review" "$project/.claude/skills/pre-merge-review"
ln -s "$repo/skills/deploy-guards" "$project/.claude/skills/deploy-guards"

na="$SANDBOX/na.txt"
"$repo/pending-changes.sh" "$project" > "$na" 2>/dev/null
if grep -qi 'missing the skill' "$na"; then
  fail "S9 — the message stays even though all skills are installed"
fi

test_done
