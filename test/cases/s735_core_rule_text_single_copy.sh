#!/usr/bin/env bash
# S735 — `./check` fails when a hook, gate script or adapter file carries a live core rule line's text; quoting by OR ID passes (#750 AC5; A66 AC5 drift)
# Covers: F38
#
# Seam (QA proposal, A66 names only "a new ./check assertion"):
# `check-core-rule-copies.sh [dir]`, run by `check` like the other
# check-*.sh scripts. Exit 0 clean; non-zero with one line per copy naming
# the file and the OR ID. Scope: every file under hooks/ and adapters/, every
# `hook:` and `gate:` path declared in CHANGES.md, and session-context.sh.
# A rule line is `- OR<n> <text>` in skills/role-contracts/ORCHESTRATOR.md;
# a copy is its text, whitespace normalized, inside a scoped file (also
# normalized), so a re-wrapped copy counts.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/core-delivery-750.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/core-delivery-750.sh"

sandbox_create
trap sandbox_destroy EXIT

NAME=check-core-rule-copies.sh
if [ ! -x "$TEST_REPO_ROOT/$NAME" ]; then
  fail "S735 — $NAME is missing or not executable"
  test_done
fi
grep -qF "$NAME" "$TEST_REPO_ROOT/check" || fail "S735 — check does not run $NAME"

rule_text() { # clone id -> the rule text after "- ORn "
  sed -n "s/^- $2 //p" "$1/$CORE750_ORCH_REL" | head -n 1
}
run_check() { # clone -> output in $out, exit in $rc
  out="$("$1/$NAME" "$1" 2>&1)"
  rc=$?
}

# --- the shipped tree is clean ------------------------------------------------
wf="$(sandbox_copy_repo clean)"
run_check "$wf"
[ "$rc" = 0 ] || fail "S735/clean — the shipped tree fails: $(head -n 3 <<<"$out" | tr '\n' ' ')"

# --- planted copies are caught ------------------------------------------------
# plant <label> <file> <id> <mode>: mode one = rule text on one line,
# wrapped = the same text re-wrapped at spaces into short lines.
plant() {
  local label="$1" rel="$2" id="$3" mode="$4" m text
  m="$(sandbox_copy_repo "m-$label")"
  text="$(rule_text "$m" "$id")"
  [ -n "$text" ] || { fail "S735/$label — no $id line in the core"; return; }
  if [ "$mode" = wrapped ]; then
    printf '\n%s\n' "$(printf '%s' "$text" | fold -s -w 30)" >> "$m/$rel"
  else
    printf '\n# %s\n' "$text" >> "$m/$rel"
  fi
  run_check "$m"
  [ "$rc" != 0 ] || { fail "S735/$label — $id text in $rel passed"; return; }
  grep -qw "$id" <<<"$(grep -F "$rel" <<<"$out")" || fail "S735/$label — the failure does not name $rel and $id: $(head -n 2 <<<"$out" | tr '\n' ' ')"
}
plant hook-py hooks/agent-dispatch.py OR10 one
plant hook-guard hooks/git-guardrails OR11 one
plant adapter-codex adapters/codex/INSTRUCTIONS.md OR30 wrapped
plant adapter-claude adapters/claude/INSTRUCTIONS.md OR8 one
plant gate skills/pre-merge-review/model-record-gate.sh OR10 wrapped
plant session-context session-context.sh OR1 one

# --- quoting by ID passes -------------------------------------------------------
m="$(sandbox_copy_repo ids)"
printf '\n# Enforces OR7, OR8, OR14, OR30 and OR31; quotes their lines from ORCHESTRATOR.md at run time.\n' >> "$m/hooks/agent-dispatch.py"
run_check "$m"
[ "$rc" = 0 ] || fail "S735/ids — quoting by OR ID fails the check: $(head -n 2 <<<"$out" | tr '\n' ' ')"

# --- the core itself and its inventory are not copies ----------------------------
[ -n "$(core750_rule_hits "$wf/$CORE750_ORCH_REL" "$wf/$CORE750_ORCH_REL")" ] \
  || fail "S735/self — the rule reader finds no rule lines in ORCHESTRATOR.md (control)"

test_done
