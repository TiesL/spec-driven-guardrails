#!/usr/bin/env bash
# S378 — the pipeline-override texts the docs must carry are pinned, each with a mutation arm
# Covers: F38
#
# Issue #564 (AC7, AC9, AC10 and the doc-text pins clause). Seam: the doc and
# script texts read as data (grep on the real tree) and the output of
# `session-context.sh --slot 1` for an opted-in project. Each pin has a
# mutation arm on a sandbox copy: remove that text and the pin must go red.
#
# Falsifiers: a pin that stays green when its text is deleted; a pin that
# greps a file other than the one the session reads.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"

sandbox_create
trap sandbox_destroy EXIT

# pin_abbrev <root>: policy/WORKFLOW.md and role-contracts/SKILL.md both name the
# abbreviated workflow (any case) on a line that holds skip=Planning and skip=Test.
pin_abbrev() {
  local f line
  for f in policy/WORKFLOW.md skills/role-contracts/SKILL.md; do
    line="$(grep -i 'abbreviated workflow' "$1/$f" 2>/dev/null)"
    [ -n "$line" ] || { echo "$f has no 'abbreviated workflow'"; return 1; }
    grep -q 'skip=Planning' <<<"$line" && grep -q 'skip=Test' <<<"$line" \
      || { echo "$f: the abbreviated-workflow text lacks skip=Planning/skip=Test"; return 1; }
  done
}
# pin_or34 <root>: OR34 names the script.
pin_or34() {
  local or34
  or34="$(grep '^- OR34 ' "$1/skills/role-contracts/ORCHESTRATOR.md")"
  grep -q 'pipeline-override\.sh' <<<"$or34" \
    || { echo "OR34 does not name pipeline-override.sh"; return 1; }
}
# pin_slot1 <root>: the session text a project gets in slot 1 names the script.
pin_slot1() {
  local proj="$SANDBOX/slotproj"
  rm -rf "$proj"; mkdir -p "$proj"; git -C "$proj" init -q -b main
  write_adoption "$proj/WORKFLOW-ADOPTION.md" process-multi-agent-roles yes
  local out
  out="$("$1/session-context.sh" --slot 1 "$proj" 2>/dev/null)"
  grep -q 'pipeline-override\.sh' <<<"$out" \
    || { echo "session-context.sh --slot 1 does not mention pipeline-override.sh"; return 1; }
}
# pin_quote <root>: AC10, the text says single quote(s) in all three files.
pin_quote() {
  local f
  for f in pipeline-override.sh skills/role-contracts/SKILL.md skills/role-contracts/ORCHESTRATOR.md; do
    grep -q 'single quote' "$1/$f" || { echo "$f lacks the text 'single quote'"; return 1; }
  done
}
# pin_closes <root>: AC9, the closing keyword is named in SKILL.md and the script.
pin_closes() {
  local f
  for f in skills/role-contracts/SKILL.md pipeline-override.sh; do
    grep -q 'Closes #' "$1/$f" || { echo "$f lacks 'Closes #'"; return 1; }
  done
}

fresh_copy() { rm -rf "$SANDBOX/m"; sandbox_copy_repo m >/dev/null; echo "$SANDBOX/m"; }
sed_i() { local last="${*: -1}"; sed -i.bak "$@" && rm -f "$last.bak"; }

R="$TEST_REPO_ROOT"
for p in pin_abbrev pin_or34 pin_slot1 pin_quote pin_closes; do
  msg="$($p "$R")" || fail "S378/$p — on the real tree: $msg"
done

# Mutation arms: each deletion must turn its pin red.
m="$(fresh_copy)"; sed_i '/[Aa]bbreviated workflow/d' "$m/policy/WORKFLOW.md"
pin_abbrev "$m" >/dev/null && fail "S378/abbrev-policy — deleting the policy bullet left the pin green"
m="$(fresh_copy)"; sed_i '/[Aa]bbreviated workflow/d' "$m/skills/role-contracts/SKILL.md"
pin_abbrev "$m" >/dev/null && fail "S378/abbrev-skill — deleting the SKILL.md paragraph left the pin green"
m="$(fresh_copy)"; sed_i 's/skip=Test/skip=X/g' "$m/skills/role-contracts/SKILL.md"
pin_abbrev "$m" >/dev/null && fail "S378/abbrev-skiptest — dropping skip=Test left the pin green"
m="$(fresh_copy)"; sed_i '/^- OR34 /s/pipeline-override\.sh/the-script/g' "$m/skills/role-contracts/ORCHESTRATOR.md"
pin_or34 "$m" >/dev/null && fail "S378/or34 — removing the script name from OR34 left the pin green"
pin_slot1 "$m" >/dev/null && fail "S378/slot1 — removing the script name from OR34 left the slot-1 pin green"
for f in pipeline-override.sh skills/role-contracts/SKILL.md skills/role-contracts/ORCHESTRATOR.md; do
  m="$(fresh_copy)"; sed_i 's/single quote/quote/g' "$m/$f"
  pin_quote "$m" >/dev/null && fail "S378/quote-$f — removing 'single quote' left the pin green"
done
for f in skills/role-contracts/SKILL.md pipeline-override.sh; do
  m="$(fresh_copy)"; sed_i 's/Closes #/Closes /g' "$m/$f"
  pin_closes "$m" >/dev/null && fail "S378/closes-$f — removing 'Closes #' left the pin green"
done

test_done
