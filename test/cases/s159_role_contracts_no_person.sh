#!/usr/bin/env bash
# S159 — The installed role-contracts skill names the decision-maker by role, not by person.
# Covers: F37
#
# Issue #369, AC5. Seam: the SKILL.md as an adopted project sees it. In an
# adopted project, escalations and decisions go to that project's own
# human decision-maker, not to this repo's owner.
#
# The owner's first name is checked by its SHA-256 only: this is a public
# repo, and the rule is never to write a real person's name into it, not
# even inside a test that forbids it.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

clone="$(sandbox_copy_repo clone)"
project="$(fresh_project adopter)"
SPEC_DRIVEN_GUARDRAILS_DIR="$clone" "$clone/adopt.sh" "$project" >/dev/null 2>&1

skill="$project/.claude/skills/role-contracts/SKILL.md"
if [ ! -r "$skill" ]; then
  fail "S159 — no installed role-contracts skill in the adopted project (see S155)"
  test_done
fi

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | cut -d' ' -f1
  else
    shasum -a 256 | cut -d' ' -f1
  fi
}

# Case-sensitive SHA-256 of names that must not appear as a word.
forbidden_hashes='a8c8354a453539e374fa8f9a069cad803c280871e99ca2ab2ab46afb23a1acb9'

# Then: no forbidden name appears as a word.
tr -cs 'A-Za-z' '\n' < "$skill" | sort -u > "$SANDBOX/words.txt"
while IFS= read -r word; do
  [ -n "$word" ] || continue
  h="$(printf '%s' "$word" | sha256)"
  case " $forbidden_hashes " in
    *" $h "*)
      lines="$(grep -nw "$word" "$skill" | cut -d: -f1 | tr '\n' ' ')"
      fail "S159 — the skill names a person (a forbidden name, by hash) on line(s): $lines" ;;
  esac
done < "$SANDBOX/words.txt"

# And: the owner's GitHub handle appears only as a repository qualifier
# (owner/repo), never as the person decisions go to.
if grep -nE '(^|[^A-Za-z0-9])TiesL([^/A-Za-z0-9]|$)' "$skill" > "$SANDBOX/handle.txt"; then
  fail "S159 — the skill names the owner's handle as a person, not as a repo qualifier:"
  cat "$SANDBOX/handle.txt" >&2
fi

# And: no gendered pronoun stands in for a specific person.
if grep -nwiE 'he|him|his|she|her|hers' "$skill" > "$SANDBOX/pronouns.txt"; then
  fail "S159 — a personal pronoun refers to a specific person; name the role instead:"
  cat "$SANDBOX/pronouns.txt" >&2
fi

# And: the role that receives decisions and escalations is named.
if ! grep -qi 'decision-maker' "$skill"; then
  fail "S159 — the skill never names the project's human decision-maker by role"
fi

test_done
