#!/usr/bin/env bash
# S336 — CHANGES.md offers the advance-approval rule through one new entry, and fresh adoption lists it as pending (#516 Part 3; A43)
# Covers: F55
#
# Seam: CHANGES.md through lib/changes.sh (the parser adopt.sh and
# pending-changes.sh share) and a fresh adoption. The fresh-adoption expected
# list itself is R2's (r2_pending_after_fresh_adoption.sh), updated with it.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

R="$TEST_REPO_ROOT"
C="$R/CHANGES.md"

sandbox_create
trap sandbox_destroy EXIT

id=process-advance-merge-approval
[ "$(grep -c "^## $id\$" "$C")" = 1 ] || fail "S336 — CHANGES.md has no single '## $id' entry"
entry="$(awk -v h="## $id" '$0==h{on=1; next} on && /^(## |---)/{exit} on{print}' "$C")"
q="$(grep -m1 '^- \*\*Question:\*\*' <<<"$entry")"
[ -n "$q" ] || fail "S336 — no Question line"
grep -q '?$' <<<"$q" || fail "S336 — the Question is not one closed line ending in '?': $q"
grep -qx -- '- \*\*Default:\*\* question' <<<"$entry" || fail "S336 — Default is not 'question'"
grep -qx -- '- \*\*Applies if:\*\* always' <<<"$entry" || fail "S336 — Applies if is not 'always'"
yes_means="$(awk '/^- \*\*Yes means:\*\*/{on=1} on && /^- \*\*Reaches session:\*\*/{exit} on{print}' <<<"$entry" | tr '\n' ' ')"
for x in "in advance" "lapses" "gh pr update-branch" "hooks/git-guardrails" "regardless of this answer" "#511"; do
  grep -qF -- "$x" <<<"$yes_means" || fail "S336 — Yes means lacks '$x'"
done
grep -q '^- \*\*Reaches session:\*\* always-loaded: WORKFLOW.md' <<<"$entry" || fail "S336 — Reaches session must name always-loaded: WORKFLOW.md"
grep -q '^- \*\*PR:\*\* https://' <<<"$entry" || fail "S336 — no PR link"

# No existing entry's meaning version changed (Human decision 3a assumed: no bump).
base_ref="$(git -C "$R" merge-base HEAD origin/main 2>/dev/null)"
if [ -n "$base_ref" ]; then
  old="$(git -C "$R" show "$base_ref:CHANGES.md" 2>/dev/null | grep -n 'Meaning version' | sed 's/^[0-9]*://')"
  new="$(grep 'Meaning version' "$C")"
  [ "$old" = "$new" ] || fail "S336 — a Meaning version line changed against the merge base"
fi

# A fresh adoption lists it as pending (question default, never seeded).
project="$(fresh_project fresh)"
adopt "$project"
pend="$(pending_ids "$project")"
grep -qx "$id" <<<"$pend" || fail "S336 — a fresh adoption does not list $id as pending"
seeded="$(seeded_ids "$project")"
grep -qx "$id" <<<"$seeded" && fail "S336 — $id was seeded at adoption (Default question must never seed)"

test_done
