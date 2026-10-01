#!/usr/bin/env bash
# S182 — Every CHANGES.md entry carries Reaches session; the new entry's
# values are the decided ones.
# Covers: F37
#
# Issue #371, AC10 + human decision 4 (all existing entries now, no exempt
# list). Seam: this repo's own CHANGES.md. Structure only; the per-value
# rules are S181's, through ./check.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

changes="$TEST_REPO_ROOT/CHANGES.md"
id="process-multi-agent-roles"

# Every `## <id>` entry, up to the NFR note, has a non-empty field.
bad="$(awk '
  function flush() { if (cur != "" && !ok) print cur }
  /^## / { flush(); cur = substr($0, 4); ok = 0; next }
  /^### / { flush(); cur = ""; next }
  cur != "" && /^- \*\*Reaches session:\*\* *[^ ]/ { ok = 1 }
  END { flush() }
' "$changes")"
if [ -n "$bad" ]; then
  fail "S182 — entries without a Reaches session value:"
  printf '%s\n' "$bad" | sed 's/^/    - /' >&2
fi
total="$(grep -c '^## ' "$changes")"
[ "$total" -gt 20 ] || fail "S182 — only $total entries found; the parse is off"

# The preamble documents the field and its vocabulary.
preamble="$(awk '/^## /{exit} {print}' "$changes")"
assert_contains "S182 — the preamble documents the field" "Reaches session" "$preamble"
for kw in none always-loaded session-context hook gate; do
  assert_contains "S182 — the preamble lists '$kw'" "$kw" "$preamble"
done

# The decided values for this entry.
entry_line="$(awk -v h="## $id" '
  $0 == h { on = 1; next }
  on && /^## / { exit }
  on && /^- \*\*Reaches session:\*\*/ { print; exit }
' "$changes")"
assert_contains "S182 — $id reaches a session through ORCHESTRATOR.md" "session-context: skills/role-contracts/ORCHESTRATOR.md" "$entry_line"
assert_contains "S182 — $id is also checked by the model-record gate" "gate: skills/pre-merge-review/model-record-gate.sh" "$entry_line"

# Adding the field is not a meaning change: no version bump on this entry.
entry="$(awk -v h="## $id" '$0 == h { on = 1; next } on && /^## / { exit } on { print }' "$changes")"
case "$entry" in
  *"**Meaning version:**"*) fail "S182 — $id carries a Meaning version; #371 ships in the same release and must not bump it" ;;
esac

test_done
