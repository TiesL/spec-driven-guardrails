#!/usr/bin/env bash
# test/fixtures/fresh-reviewer-helpers.sh — shared text helpers for the #414
# scenarios (S209-S211): the fresh-Reviewer-per-round rule. Source after
# test/lib.sh and test/fixtures/review-floor-helpers.sh (para_has_all).
# shellcheck disable=SC2034  # FR_* are used by the sourcing tests
# Not a test case. Bash 3.2: no declare -A, no mapfile.

# sentences_of <file>: the file flattened and split into one sentence per
# line (a sentence ends at ". " or at the end of a line that ends in "."),
# so a rule can be required to sit in ONE sentence.
sentences_of() {
  tr '\n' ' ' < "$1" | sed -E 's/([.!?]) +/\1\
/g'
}

# sentence_has_all <file> <ere> [<ere> ...]: success when ONE sentence of
# <file> matches every ERE, case-insensitively.
sentence_has_all() {
  local file="$1" s ere ok
  shift
  while IFS= read -r s; do
    ok=1
    for ere in "$@"; do grep -qiE -- "$ere" <<<"$s" || { ok=0; break; }; done
    [ "$ok" -eq 1 ] && return 0
  done < <(sentences_of "$file")
  return 1
}

# section_of <file> <heading-ere>: the body of the first "## " section whose
# heading matches, up to the next "## " heading.
section_of() {
  awk -v re="$2" '
    /^## / { if (on) exit; if ($0 ~ re) { on = 1; next } }
    on { print }
  ' "$1"
}

# rule files for the three places the rule lives
fr_files() {
  FR_ROLES="$TEST_REPO_ROOT/skills/role-contracts/SKILL.md"
  FR_ORCH="$TEST_REPO_ROOT/skills/role-contracts/ORCHESTRATOR.md"
  FR_PMR="$TEST_REPO_ROOT/skills/pre-merge-review/SKILL.md"
}
