#!/usr/bin/env bash
# S321 — the dispatch-economy skill is installed by adopt.sh and offered by CHANGES.md (#532 AC8; A42)
# Covers: F38
#
# Seam: a fresh sandbox adoption (adopt helper of lib.sh), pending-changes.sh,
# and a textual check of the skill. No model call. The CHANGES.md entry has
# Default `yes`, so a fresh adoption seeds it and the pending list of R2 is
# unchanged (one consistent outcome: R2's expected list gains nothing).

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

R="$TEST_REPO_ROOT"
SK="$R/skills/dispatch-economy/SKILL.md"
sandbox_create
trap sandbox_destroy EXIT

[ -r "$SK" ] || { fail "S321 — skills/dispatch-economy/SKILL.md is missing"; test_done; }
[ "$(head -1 "$SK")" = '---' ] || fail "S321 — frontmatter must open with ---"
fm="$(awk 'NR==1{next} /^---$/{exit} {print}' "$SK")"
grep -qx 'name: dispatch-economy' <<<"$fm" || fail "S321 — frontmatter name must be dispatch-economy"
grep -q '^description: .\+' <<<"$fm" || fail "S321 — frontmatter needs a description"

project="$(fresh_project p)"
adopt "$project"
link="$project/.claude/skills/dispatch-economy"
[ -L "$link" ] || fail "S321 — adopt.sh did not symlink .claude/skills/dispatch-economy"
[ "$(cd "$link" 2>/dev/null && pwd -P)" = "$(cd "$R/skills/dispatch-economy" && pwd -P)" ] \
  || fail "S321 — the symlink does not point at the canonical skill"

# Reasoning only: no obligation. A session obeys the core; the skill holds the rest.
grep -qiE '^[^`]*\b(you must|must not|never|always)\b' "$SK" \
  && fail "S321 — the skill carries an obligation line (a rule belongs in the core): $(grep -iE '^[^`]*\b(you must|must not|never|always)\b' "$SK" | head -1)"
grep -qi 'threshold' "$SK" || fail "S321 — the skill must hold the threshold derivation"
grep -qi 'worked' "$SK" || fail "S321 — the skill must hold a worked log example"
grep -q 'dispatch-economy-extract' "$SK" || fail "S321 — the skill must hold the extraction command"
grep -qiE 'revis' "$SK" || fail "S321 — the skill must say the limits are revised from extracted data (Human decision 2.3)"
grep -q '#500' "$SK" || fail "S321 — the skill must cite #500"
grep -qE '/clear' "$SK" && ! grep -qiE 'no .?/clear.? rule|adds no .?/clear' "$SK" && fail "S321 — the skill mentions /clear without saying no /clear rule is added"

# CHANGES.md entry, closed question, Default yes: seeded, so R2's pending list is unchanged.
sec="$(awk '/^## process-dispatch-economy$/{on=1; print; next} /^## /{on=0} /^---$/{on=0} on{print}' "$R/CHANGES.md")"
[ -n "$sec" ] || fail "S321 — CHANGES.md has no '## process-dispatch-economy' entry"
grep -q '^- \*\*Question:\*\* .*?' <<<"$sec" || fail "S321 — the entry needs a one-line closed question"
grep -q '^- \*\*Default:\*\* yes$' <<<"$sec" || fail "S321 — the entry's Default must be yes (R2's pending list stays unchanged)"
grep -q 'dispatch-economy' <<<"$sec" || fail "S321 — the entry must name the skill"
pending="$(pending_ids "$project")"
grep -q '^process-dispatch-economy$' <<<"$pending" && fail "S321 — a Default yes entry must be seeded, not pending"
seeded="$(seeded_ids "$project")"
grep -q '^process-dispatch-economy$' <<<"$seeded" || fail "S321 — fresh adoption did not seed process-dispatch-economy"
exp="$SANDBOX/exp"
awk '/^cat > "\$expected" <<.IDS.$/{on=1; next} /^IDS$/{on=0} on{print}' "$R/test/cases/r2_pending_after_fresh_adoption.sh" | sort > "$exp"
act="$SANDBOX/act"; printf '%s\n' "$pending" > "$act"
assert_ids_equal "S321/R2-consistency" "$exp" "$act"

# Negative control: the skill renamed in a copy gives no symlink.
cp_repo="$SANDBOX/copy"
mkdir -p "$cp_repo"
(cd "$R" && tar --exclude='./.git' --exclude='./wip' -cf - .) | (cd "$cp_repo" && tar -xf -)
mv "$cp_repo/skills/dispatch-economy" "$cp_repo/skills/dispatch-economy-renamed"
p2="$(fresh_project p2)"
SPEC_DRIVEN_GUARDRAILS_DIR="$cp_repo" "$cp_repo/adopt.sh" "$p2" >/dev/null 2>&1
[ -e "$p2/.claude/skills/dispatch-economy" ] && fail "S321/neg — a renamed skill still produced the dispatch-economy symlink"

test_done
