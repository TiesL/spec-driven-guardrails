#!/usr/bin/env bash
# test/fixtures/loopback-helpers.sh — text helpers for the #410 rule-text
# scenarios (S213, S214, S215, S218). Source after test/lib.sh.
# shellcheck disable=SC2034  # LB_* are used by the sourcing tests
# Not a test case. Bash 3.2: no declare -A, no mapfile.
#
# A "unit" is one table row, one list item, or one paragraph (hard-wrapped
# lines joined). A "sentence" is a unit cut at ". ". A rule has to sit in ONE
# unit or ONE sentence, so words scattered over unrelated sections cannot
# satisfy it. The patterns the tests pass are DIRECTIONAL (negation before
# the thing negated, role A before role B, "before" and not "after"), so an
# inverted rule fails, which a bag-of-words test would not.

lb_files() {
  LB_ROLES="$TEST_REPO_ROOT/skills/role-contracts/SKILL.md"
  LB_ORCH="$TEST_REPO_ROOT/skills/role-contracts/ORCHESTRATOR.md"
  LB_PMR="$TEST_REPO_ROOT/skills/pre-merge-review/SKILL.md"
}

# lb_units <file>: one unit per line; each unit is prefixed "L " when it is a
# list item (a line starting "- ", "* " or "N. "), else "P ".
lb_units() {
  awk '
    function flush() { if (cur != "") print tag " " cur; cur = ""; tag = "P" }
    BEGIN { cur = ""; tag = "P" }
    /^[[:space:]]*$/ { flush(); next }
    /^\|/ { flush(); print "P " $0; next }
    /^[[:space:]]*([-*]|[0-9]+\.)[[:space:]]/ { flush(); tag = "L"; sub(/^[[:space:]]+/, ""); cur = $0; next }
    { sub(/^[[:space:]]+/, ""); cur = (cur == "" ? $0 : cur " " $0) }
    END { flush() }
  ' "$1"
}

# lb_sentences <file>: lb_units output with each unit cut into sentences,
# tags kept.
lb_sentences() {
  lb_units "$1" | awk '
    {
      tag = substr($0, 1, 1); body = substr($0, 3)
      n = split(body, parts, /[.!?] +/)
      for (i = 1; i <= n; i++) if (parts[i] != "") print tag " " parts[i]
    }'
}

# lb_unit_has_all / lb_sentence_has_all <file> <ere> ...: success when ONE
# unit (sentence) matches every ERE, case-insensitively. The EREs may
# assume order (a.*b) to be directional.
lb_unit_has_all() { _lb_has_all "$(lb_units "$1")" "${@:2}"; }
lb_sentence_has_all() { _lb_has_all "$(lb_sentences "$1")" "${@:2}"; }
# lb_any_has_all: unit OR sentence (a rule may be a table row or a sentence)
lb_any_has_all() { lb_unit_has_all "$@" || lb_sentence_has_all "$@"; }

_lb_has_all() {
  local text="$1" line ere ok
  shift
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    ok=1
    for ere in "$@"; do grep -qiE -- "$ere" <<<"$line" || { ok=0; break; }; done
    [ "$ok" -eq 1 ] && return 0
  done <<<"$text"
  return 1
}

# lb_block <file> <start-ere>: the unit matching <start-ere> (matched against
# the tagged unit, "P " or "L " first) plus what belongs to it: the list items
# that follow, and an unlabelled paragraph that follows (an intro such as
# "Also in the self-check:"). It ends at the next paragraph that opens with a
# bold label (**...**), a heading or a table row. One unit per line.
lb_block() {
  lb_units "$1" | awk -v re="$2" '
    on && substr($0, 1, 1) == "P" && substr($0, 3, 2) == "**" { exit }
    on && substr($0, 1, 1) == "P" && substr($0, 3, 1) ~ /[#|]/ { exit }
    !on && tolower($0) ~ tolower(re) { on = 1 }
    on { print }'
}

# lb_block_has_all <file> <start-ere> <ere> ...: a sentence of the block
# matches every ERE.
lb_block_has_all() {
  local file="$1" start="$2" blk
  shift 2
  blk="$(lb_block "$file" "$start" | awk '
    {
      body = substr($0, 3)
      n = split(body, parts, /[.!?] +/)
      for (i = 1; i <= n; i++) if (parts[i] != "") print parts[i]
    }')"
  _lb_has_all "$blk" "$@"
}
