#!/usr/bin/env bash
# S330-S332 — the merge rule admits a conditional advance approval, lapses on a required change, survives only an update-only head, and takes a relayed approval only verbatim (#516 AC4-AC6; A43)
# Covers: F55
#
# Seam: the text of policy/WORKFLOW.md and its generated copies (WORKFLOW.md,
# adapters/codex/AGENTS.md; generator sync is ./check's own adapter check),
# plus the survival test of S331 run as read-only git on sandbox fixtures. The
# survival test lives in the rule text as two pinned git commands (no helper
# script): `git rev-list --parents -n1 <new-head>` must print the new head, the
# approved head as first parent and one second parent, and
# `git merge-base --is-ancestor <second-parent> origin/<base>` must succeed.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

R="$TEST_REPO_ROOT"
SRC="$R/policy/WORKFLOW.md"
GEN="$R/WORKFLOW.md $R/adapters/codex/AGENTS.md"

sandbox_create
trap sandbox_destroy EXIT

# The Wrapping-up section of a WORKFLOW-shaped file, as one line per paragraph
# or list item (wrapped lines joined), so a phrase broken over a line still matches.
wrapping_up() {
  awk '/^## Wrapping up/{on=1; next} on && /^## /{exit} on{print}' "$1"
}

# rule_problems <file>: one line per missing or forbidden phrase.
rule_problems() {
  local f="$1" w
  w="$(wrapping_up "$f" | tr '\n' ' ')"
  [ -n "$w" ] || { echo "no Wrapping up section"; return; }
  need() { grep -qiF -- "$1" <<<"$w" || echo "$2 (missing '$1')"; }
  # S330 / AC4
  need "in advance" "S330 advance approval"
  need "Review approves" "S330 condition Review"
  need "CI is green" "S330 condition CI"
  need "every pre-merge check passes" "S330 condition gates"
  need "mergeable without further changes" "S330 holds only while mergeable"
  need "names no head SHA" "S330 no head SHA"
  need "Pipeline log" "S330/S332 Pipeline log"
  need "head at which the approval was given" "S330/S332 approval head"
  need "head it merged" "S330/S332 merged head"
  need "#511" "S330 #511 pointer"
  # S331 / AC5
  need "a finding to fix" "S331 lapse on finding"
  need "red CI" "S331 lapse on red CI"
  need "a failing gate" "S331 lapse on failing gate"
  need "lapses" "S331 lapse word"
  need "ask again after the fix" "S331 asks again"
  need "gh pr update-branch" "S331 update-branch"
  need "green again on the new head" "S331 green again"
  need "first parent" "S331 first-parent condition"
  need "git rev-list --parents -n1" "S331 pinned rev-list command"
  need "git merge-base --is-ancestor" "S331 pinned ancestry command"
  # S332 / AC6
  need "verbatim words about that PR" "S332 verbatim relay"
  need "#513" "S332 manager epic"
  # Old rule gone (R5).
  for old in "final head" "confirms the final head SHA" "after the final head"; do
    grep -qiF -- "$old" <<<"$w" && echo "S330 old phrase '$old' still present"
  done
  # release-branch-workflow unchanged: the release branch's merge into main still needs the maintainer.
  need "a release branch's own eventual merge into \`main\` still needs the maintainer's" "S330 release-branch paragraph"
}

for f in "$SRC" $GEN; do
  [ -f "$f" ] || { fail "S330 — $f is missing"; continue; }
  p="$(rule_problems "$f")"
  [ -z "$p" ] || fail "S330-S332 — ${f#"$R"/}: $p"
done
# The claude adapter carries no copy of the rule; it must not carry the old one either.
for f in "$R/adapters/claude/INSTRUCTIONS.md" "$R/CLAUDE.md"; do
  [ -f "$f" ] || continue
  grep -qiE "confirms the final head SHA|after the final head" "$f" && fail "S330 — ${f#"$R"/} still states the old final-head rule"
done

# Negative controls, each failing by name.
d="$SANDBOX"
sed 's/#511/#999/g' "$SRC" > "$d/no511.md"
grep -q "S330 #511 pointer" <<<"$(rule_problems "$d/no511.md")" || fail "S330/neg-511 — the #511 pointer removed passed"
sed 's/names no head SHA/names the head SHA/g' "$SRC" > "$d/sha.md"
grep -q "S330 no head SHA" <<<"$(rule_problems "$d/sha.md")" || fail "S330/neg-sha — the no-head-SHA sentence removed passed"
sed 's/verbatim words about that PR/summary/g' "$SRC" > "$d/relay.md"
grep -q "S332 verbatim relay" <<<"$(rule_problems "$d/relay.md")" || fail "S332/neg-relay — a non-verbatim relay passed"

# --- S331 (b): the survival test on git fixtures -----------------------------
repo="$(fresh_project shape)"
g() { git -C "$repo" "$@"; }
g config user.email t@example.invalid; g config user.name t
c() { echo "$1" > "$repo/$1"; g add "$1"; g commit -q -m "$1"; }
c b0; b0="$(g rev-parse HEAD)"
g checkout -q -b work; c a; approved="$(g rev-parse HEAD)"
g checkout -q main; c b1
g checkout -q -b side "$b0"; c s1                          # a commit not on the base
g branch -q origin-main main                            # stands in for origin/<base>

mk() { g checkout -q -B "$1" "$approved"; }
mk i;   g merge -q --no-ff -m update main
mk ii;  c fix2; g merge -q --no-ff -m update main
mk iii; g merge -q --no-ff -m update main; c fix3
mk iv;  g rebase -q main >/dev/null 2>&1
mk v;   g merge -q --no-ff -m "not the base" side

# survives <head> <approved> <base>: the two commands pinned in the rule text.
survives() {
  local line
  line="$(g rev-list --parents -n1 "$1")"
  set -- $line "$2" "$3"
  [ $# -eq 5 ] || return 1                # head, first, second parent, approved, base
  [ "$2" = "$4" ] || return 1
  g merge-base --is-ancestor "$3" "$5"
}
any_merge() { local line; line="$(g rev-list --parents -n1 "$1")"; set -- $line; [ $# -eq 3 ]; }
first_parent_only() { local line; line="$(g rev-list --parents -n1 "$1")"; set -- $line "$2"; [ $# -eq 4 ] && [ "$2" = "$4" ]; }

survives i "$approved" origin-main || fail "S331/i — an update-only merge commit did not survive"
for f in ii iii iv v; do
  survives "$f" "$approved" origin-main && fail "S331/$f — a head carrying work survived the approval"
done
# Negative controls: weaker tests pass a fixture that carries work.
any_merge ii || fail "S331/neg-any — control broken: (ii) is not a merge commit"
any_merge v || fail "S331/neg-any — control broken: (v) is not a merge commit"
first_parent_only v "$approved" || fail "S331/neg-first — control broken: (v)'s first parent is not the approved head"

test_done
