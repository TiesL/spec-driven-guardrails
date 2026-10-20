#!/usr/bin/env bash
# S354 — a link made by the hook equals the link adopt.sh makes.
# Covers: F9

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../skill-links-fixture.sh
. "$(dirname "${BASH_SOURCE[0]}")/../skill-links-fixture.sh"

sandbox_create
trap sandbox_destroy EXIT

# P: adopted with the skills already present (real adopt.sh makes the links)
SL_REPO="$(sandbox_copy_repo repo-s354)"
mkdir -p "$SL_REPO/skills/one" "$SL_REPO/skills/two"
echo "---" > "$SL_REPO/skills/one/SKILL.md"
echo "---" > "$SL_REPO/skills/two/SKILL.md"
p="$(fresh_project proj-p)"
SPEC_DRIVEN_GUARDRAILS_DIR="$SL_REPO" "$SL_REPO/adopt.sh" "$p" >/dev/null 2>&1

# Q: adopted first, then the hook creates the links
q="$(fresh_project proj-q)"
mv "$SL_REPO/skills" "$SL_REPO/skills.hold"; mkdir "$SL_REPO/skills"
SPEC_DRIVEN_GUARDRAILS_DIR="$SL_REPO" "$SL_REPO/adopt.sh" "$q" >/dev/null 2>&1
rmdir "$SL_REPO/skills"; mv "$SL_REPO/skills.hold" "$SL_REPO/skills"
rm -rf "$q/.claude/skills"
SL_PROJECT="$q"
sl_run
sl_assert_quiet "S354"

for name in one two; do
  lp="$(readlink "$p/.claude/skills/$name")"
  lq="$(readlink "$q/.claude/skills/$name")"
  [ -n "$lq" ] || { fail "S354 — hook made no link for $name"; continue; }
  [ "$lp" = "$lq" ] || fail "S354 — $name: adopt.sh '$lp' vs hook '$lq'"
  case "$lq" in /*) ;; *) fail "S354 — $name target is not absolute: $lq" ;; esac
  case "$lq" in */) fail "S354 — $name target has a trailing slash: $lq" ;; esac
  [ -d "$q/.claude/skills/$name" ] || fail "S354 — $name does not resolve to a directory"
done

# adopt.sh afterwards changes nothing
SPEC_DRIVEN_GUARDRAILS_DIR="$SL_REPO" "$SL_REPO/adopt.sh" "$q" >/dev/null 2>&1
for name in one two; do
  [ "$(readlink "$q/.claude/skills/$name")" = "$(readlink "$p/.claude/skills/$name")" ] \
    || fail "S354 — adopt.sh changed the hook's link for $name"
done

test_done
