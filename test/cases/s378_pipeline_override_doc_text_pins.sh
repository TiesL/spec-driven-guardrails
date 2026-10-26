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

# pin_help_pointer <root>: #578 AC11, OR34 and the abbreviated-workflow paragraph of
# role-contracts/SKILL.md point to `pipeline-override.sh --help` for the refusal list.
pin_help_pointer() {
  local or34 para
  # the whole OR34 bullet: its first line and the indented lines below it, up to the next bullet
  or34="$(awk '/^- OR34 /{p=1;print;next} p&&/^- /{p=0} p' "$1/skills/role-contracts/ORCHESTRATOR.md")"
  grep -qF 'pipeline-override.sh --help' <<<"$or34" \
    || { echo "OR34 does not point to pipeline-override.sh --help"; return 1; }
  para="$(grep '^\*\*Abbreviated workflow' "$1/skills/role-contracts/SKILL.md")"
  grep -qF 'pipeline-override.sh --help' <<<"$para" \
    || { echo "the abbreviated-workflow paragraph of skills/role-contracts/SKILL.md does not point to pipeline-override.sh --help"; return 1; }
}

fresh_copy() { rm -rf "$SANDBOX/m"; sandbox_copy_repo m >/dev/null; echo "$SANDBOX/m"; }
sed_i() { local last="${*: -1}"; sed -i.bak "$@" && rm -f "$last.bak"; }

R="$TEST_REPO_ROOT"
for p in pin_abbrev pin_or34 pin_slot1 pin_quote pin_closes pin_help_pointer; do
  msg="$($p "$R")" || fail "S378/$p — on the real tree: $msg"
done

# arm <label> <pin> <expected-message> <mutation-command...>  (#578 AC9)
# Control: the pin passes on a fresh, unmutated copy. Mutation: the same pin on a
# copy changed by <mutation-command> (run with the copy's root as its first
# argument) must fail, and its output must contain the pin's own message, so a
# pin that is red for another reason is detected.
arm() {
  local label="$1" pin="$2" want="$3" m out
  shift 3
  m="$(fresh_copy)"
  out="$($pin "$m" 2>&1)" || { fail "S378/$label — control: the pin fails on an unmutated copy: $out"; return; }
  "$@" "$m" || { fail "S378/$label — the mutation could not be applied"; return; }
  if out="$($pin "$m" 2>&1)"; then
    fail "S378/$label — mutation not detected: the pin stayed green"
  else
    case "$out" in *"$want"*) : ;; *) fail "S378/$label — red for another reason: wanted '$want', got '$out'" ;; esac
  fi
}
mut_sed() { # <file> <sed-expr> <root>: sed -i on <root>/<file>
  sed_i "$2" "$3/$1"
}

arm abbrev-policy pin_abbrev "policy/WORKFLOW.md has no 'abbreviated workflow'" \
  mut_sed policy/WORKFLOW.md '/[Aa]bbreviated workflow/d'
arm abbrev-skill pin_abbrev "skills/role-contracts/SKILL.md has no 'abbreviated workflow'" \
  mut_sed skills/role-contracts/SKILL.md '/[Aa]bbreviated workflow/d'
arm abbrev-skiptest pin_abbrev "skills/role-contracts/SKILL.md: the abbreviated-workflow text lacks skip=Planning/skip=Test" \
  mut_sed skills/role-contracts/SKILL.md 's/skip=Test/skip=X/g'
arm or34 pin_or34 "OR34 does not name pipeline-override.sh" \
  mut_sed skills/role-contracts/ORCHESTRATOR.md '/^- OR34 /s/pipeline-override\.sh/the-script/g'
arm slot1 pin_slot1 "session-context.sh --slot 1 does not mention pipeline-override.sh" \
  mut_sed skills/role-contracts/ORCHESTRATOR.md '/^- OR34 /,/^- OR35 /s/pipeline-override\.sh/the-script/g'
for f in pipeline-override.sh skills/role-contracts/SKILL.md skills/role-contracts/ORCHESTRATOR.md; do
  arm "quote-$f" pin_quote "$f lacks the text 'single quote'" mut_sed "$f" 's/single quote/quote/g'
done
for f in skills/role-contracts/SKILL.md pipeline-override.sh; do
  arm "closes-$f" pin_closes "$f lacks 'Closes #'" mut_sed "$f" 's/Closes #/Closes /g'
done
# #578 AC11: the pointer, removed from each place in turn
arm help-or34 pin_help_pointer "OR34 does not point to pipeline-override.sh --help" \
  mut_sed skills/role-contracts/ORCHESTRATOR.md '/^- OR34 /,/^- OR35 /s/pipeline-override\.sh --help/pipeline-override.sh/g'
arm help-skill pin_help_pointer "the abbreviated-workflow paragraph of skills/role-contracts/SKILL.md does not point to pipeline-override.sh --help" \
  mut_sed skills/role-contracts/SKILL.md '/^\*\*Abbreviated workflow/s/pipeline-override\.sh --help/pipeline-override.sh/g'

test_done
