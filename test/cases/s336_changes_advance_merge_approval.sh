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
yes_means="$(awk '/^- \*\*Yes means:\*\*/{on=1} on && /^- \*\*Reaches session:\*\*/{exit} on{print}' <<<"$entry" | tr '\n' ' ' | tr -s ' ')"
for x in "in advance" "lapses" "gh pr update-branch" "hooks/git-guardrails" "regardless of this answer" "#511"; do
  grep -qF -- "$x" <<<"$yes_means" || fail "S336 — Yes means lacks '$x'"
done
grep -q '^- \*\*Reaches session:\*\* always-loaded: WORKFLOW.md' <<<"$entry" || fail "S336 — Reaches session must name always-loaded: WORKFLOW.md"
grep -q '^- \*\*PR:\*\* https://' <<<"$entry" || fail "S336 — no PR link"

# The advance-approval slice leaves meanings unchanged. The separately approved
# #663 exception is only process-multi-agent-roles v2 -> v3; retain all other pins.
base_ref="$(git -C "$R" merge-base HEAD origin/main 2>/dev/null)"
if [ -n "$base_ref" ]; then
  python3 - "$R" "$base_ref" <<'PY_CHECK' || fail "S336 — unapproved Meaning version change"
import pathlib, re, subprocess, sys
def versions(text):
    return {part.split('\n', 1)[0]: re.findall(r'^- \*\*Meaning version:\*\*.*$', part, re.M)
            for part in text.split('\n## ')[1:] if '**Meaning version:**' in part}
root, base = sys.argv[1:]
old = versions(subprocess.check_output(['git', '-C', root, 'show', base + ':CHANGES.md'], text=True))
new = versions((pathlib.Path(root) / 'CHANGES.md').read_text())
key = 'process-multi-agent-roles'
previous, current = old.pop(key), new.pop(key)
assert len(current) == 1
assert re.match(r'- \*\*Meaning version:\*\* 3 — #647 stage-selection rules and #651 epic stage inheritance$', current[0])
if previous != current:  # Before #663 merges, only its approved v2 -> v3 delta is allowed.
    assert len(previous) == 1 and re.match(r'- \*\*Meaning version:\*\* 2(?: |$)', previous[0])
assert old == new, (old, new)
PY_CHECK
fi

# A fresh adoption lists it as pending (question default, never seeded).
project="$(fresh_project fresh)"
adopt "$project"
pend="$(pending_ids "$project")"
grep -qx "$id" <<<"$pend" || fail "S336 — a fresh adoption does not list $id as pending"
seeded="$(seeded_ids "$project")"
grep -qx "$id" <<<"$seeded" && fail "S336 — $id was seeded at adoption (Default question must never seed)"

test_done
