#!/usr/bin/env bash
# S309 — both parts are within budget in the worst case, the slots split
# exactly, and the wiring matches K (#499 AC4, AC6)
# Covers: F38
#
# Seam (A41): `session-context.sh [--runtime R] --slot <n> <project>` output,
# measured by `context_chars` of lib/context-budget.sh against
# CONTEXT_BUDGET_CHARS (sourced, never a literal here), and
# settings/session-hooks.json read as data. Worst case: every CHANGES.md
# entry that declares `session-context:` answered yes, the CLAUDE.md link
# broken so the warning prints, clone and project paths of 100+ characters.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"

sandbox_create
trap sandbox_destroy EXIT

MARKER='<!-- session-context: slot -->'

if [ ! -r "$TEST_REPO_ROOT/lib/context-budget.sh" ]; then
  fail "S309 — lib/context-budget.sh is missing"
  test_done
fi
# shellcheck source=../../lib/context-budget.sh
. "$TEST_REPO_ROOT/lib/context-budget.sh"
case "${CONTEXT_BUDGET_CHARS:-}" in
  ''|*[!0-9]*) fail "S309 — CONTEXT_BUDGET_CHARS is not a number: '${CONTEXT_BUDGET_CHARS:-}'"; test_done ;;
esac
[ "$(printf 'a\xc3\xa9\xe2\x86\x92' | context_chars)" = 3 ] \
  || fail "S309 — context_chars must count UTF-8 code points (a, e-acute, arrow = 3)"

# --- worst-case fixture --------------------------------------------------
long="$(printf 'p%.0s' $(seq 1 100))"
wf="$SANDBOX/clone-$long"
mkdir -p "$wf"
(cd "$TEST_REPO_ROOT" && tar --exclude='./.git' --exclude='./wip' --exclude='./CLAUDE.md' \
  --exclude='./.claude/settings.json' --exclude='./.claude/skills' -cf - .) | (cd "$wf" && tar -xf -)
proj="$SANDBOX/project-$long"
mkdir -p "$proj"
git -C "$proj" init -q -b main
ids=()
while IFS='|' read -r id value _; do
  case "$value" in session-context:*) ids+=("$id" yes) ;; esac
done < <(. "$wf/lib/changes.sh"; reaches_session_values "$wf/CHANGES.md")
[ "${#ids[@]}" -ge 2 ] || fail "S309 — no CHANGES.md entry declares session-context:"
write_adoption "$proj/WORKFLOW-ADOPTION.md" "${ids[@]}"
ln -s "$SANDBOX/nowhere/WORKFLOW.md" "$proj/CLAUDE.md"

# K and the wiring: the matcher-less SessionStart group's --slot commands.
slots_in_settings() { # settings.json -> one slot number per line, in order
  python3 -I - "$1" <<'PY'
import json, re, sys
d = json.load(open(sys.argv[1]))
for g in d.get("hooks", {}).get("SessionStart", []):
    if "matcher" in g:
        continue
    for h in g.get("hooks", []):
        m = re.search(r"--slot\s+(\S+)", h.get("command", ""))
        if m:
            print(m.group(1))
PY
}
wiring_ok() { # settings.json K -> 0 when the --slot commands are exactly 1..K
  local got want
  got="$(slots_in_settings "$1" | tr '\n' ' ')"
  want="$(seq 1 "$2" | tr '\n' ' ')"
  [ "$got" = "$want" ]
}
markers="$(grep -cxF "$MARKER" "$wf/skills/role-contracts/ORCHESTRATOR.md")"
K=$((markers + 1))
[ "$K" = 2 ] || fail "S309 — expected K=2 chunks (one marker line), got $K"
wiring_ok "$wf/settings/session-hooks.json" "$K" \
  || fail "S309/wiring — settings --slot commands ($(slots_in_settings "$wf/settings/session-hooks.json" | tr '\n' ' ')) are not exactly --slot 1..$K"
# Negative control: a third --slot command fails the K match.
cp "$wf/settings/session-hooks.json" "$SANDBOX/three.json"
python3 -I - "$SANDBOX/three.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
for g in d["hooks"]["SessionStart"]:
    if "matcher" not in g:
        g["hooks"].append({"type": "command", "command": "x --slot 3"})
json.dump(d, open(p, "w"))
PY
if wiring_ok "$SANDBOX/three.json" "$K"; then
  fail "S309/neg-wiring — a third --slot command was not caught"
fi

# --- budget per slot -----------------------------------------------------
budget_ok() { # clone project n -> 0 within budget; prints the failure
  local out size
  out="$("$1/session-context.sh" --slot "$3" "$2" 2>/dev/null; printf x)"
  out="${out%x}"
  size="$(printf '%s' "$out" | context_chars)"
  if [ "$size" -gt "$CONTEXT_BUDGET_CHARS" ]; then
    echo "slot $3 is $size characters, over the budget of $CONTEXT_BUDGET_CHARS"
    return 1
  fi
}
for n in $(seq 1 "$K"); do
  msg="$(budget_ok "$wf" "$proj" "$n")" || fail "S309/budget — $msg"
done
# Negative control: part 2 padded to budget + 1 fails, naming slot and size.
pad="$SANDBOX/pad-$long"
mkdir -p "$pad"
(cd "$wf" && tar -cf - .) | (cd "$pad" && tar -xf -)
python3 -I - "$pad/skills/role-contracts/ORCHESTRATOR.md" "$CONTEXT_BUDGET_CHARS" <<'PY'
import sys
p, b = sys.argv[1], int(sys.argv[2])
t = open(p, encoding="utf-8").read()
head, sep, tail = t.partition("<!-- session-context: slot -->\n")
tail = tail + "x" * (b + 1 - len(tail)) + "\n"
open(p, "w", encoding="utf-8").write(head + sep + tail)
PY
msg="$(budget_ok "$pad" "$proj" 2)" && fail "S309/neg-budget — a part over budget passed"
case "$msg" in
  *"slot 2"*"$((CONTEXT_BUDGET_CHARS + 2))"*"$CONTEXT_BUDGET_CHARS"*) ;;
  *) fail "S309/neg-budget — the failure must name slot, size and budget: '$msg'" ;;
esac

# --- split, join, unsplit -----------------------------------------------
capture() { # var args... -> the command's stdout, trailing newlines kept
  local __v="$1" o
  shift
  o="$("$@" 2>/dev/null; printf x)"
  printf -v "$__v" '%s' "${o%x}"
}
capture s1 "$wf/session-context.sh" --slot 1 "$proj"
capture s2 "$wf/session-context.sh" --slot 2 "$proj"
capture all "$wf/session-context.sh" "$proj"
orch_nomarker="$(grep -vxF "$MARKER" "$wf/skills/role-contracts/ORCHESTRATOR.md"; printf x)"
orch_nomarker="${orch_nomarker%x}"
case "$s1" in
  "Warning: CLAUDE.md in $proj is not a link"*) ;;
  *) fail "S309/slot1 — slot 1 does not start with the CLAUDE.md warning" ;;
esac
grep -q '^# Multi-agent pipeline run rules, part 1 of 2: fundamentals$' <<<"$s1" \
  || fail "S309/slot1 — slot 1 lacks the part 1 heading"
case "$s2" in
  "# Multi-agent pipeline run rules, part 2 of 2: procedure"*) ;;
  *) fail "S309/slot2 — slot 2 does not start with the part 2 heading" ;;
esac
for o in "$s1" "$s2" "$all"; do
  case "$o" in *"$MARKER"*) fail "S309/marker — an output contains the marker line" ;; esac
done
[ "$s1$s2" = "$all" ] || fail "S309/join — slots 1..K joined differ from the output without --slot"
warn_line="$(head -n 1 <<<"$all")"
[ "$all" = "$warn_line"$'\n\n'"$orch_nomarker" ] \
  || fail "S309/unsplit — the output without --slot is not the warning plus ORCHESTRATOR.md minus the marker line"
capture codex "$wf/session-context.sh" --runtime codex "$proj"
case "$codex" in
  *"$orch_nomarker") ;;
  *) fail "S309/codex — Codex output does not end with ORCHESTRATOR.md minus the marker line" ;;
esac
case "$codex" in *"$MARKER"*) fail "S309/codex — Codex output contains the marker line" ;; esac
capture cs1 "$wf/session-context.sh" --runtime codex --slot 1 "$proj"
capture cs2 "$wf/session-context.sh" --runtime codex --slot 2 "$proj"
[ "$cs1$cs2" = "$codex" ] || fail "S309/codex-join — Codex slots joined differ from Codex output"

# Past the last chunk: nothing, exit 0.
out="$("$wf/session-context.sh" --slot $((K + 1)) "$proj" 2>&1)"; st=$?
[ "$st" = 0 ] || fail "S309/past — --slot $((K + 1)) exited $st"
[ -z "$out" ] || fail "S309/past — --slot $((K + 1)) printed output"

# Invalid n: exit 2 before any read. The declared file is removed in this
# copy, so a read would print the missing-file warning.
miss="$SANDBOX/miss"
mkdir -p "$miss"
(cd "$wf" && tar -cf - .) | (cd "$miss" && tar -xf -)
rm -f "$miss/skills/role-contracts/ORCHESTRATOR.md"
probe="$("$miss/session-context.sh" --slot 1 "$proj" 2>&1)"
case "$probe" in *"doesn't exist"*) ;; *) fail "S309/invalid — the missing-file probe does not show a read" ;; esac
for bad in 0 -1 x 1x ""; do
  out="$("$miss/session-context.sh" --slot "$bad" "$proj" 2>&1)"; st=$?
  [ "$st" = 2 ] || fail "S309/invalid — --slot '$bad' exited $st, expected 2"
  case "$out" in *"doesn't exist"*|*Warning*) fail "S309/invalid — --slot '$bad' read before exiting" ;; esac
done
out="$("$miss/session-context.sh" "$proj" --slot 2>&1)"; st=$?
[ "$st" = 2 ] || fail "S309/invalid — --slot with no value exited $st, expected 2"
out="$("$miss/session-context.sh" --slot 2>&1)"; st=$?
[ "$st" = 2 ] || fail "S309/invalid — bare --slot exited $st, expected 2"

# --- the docs state the constant -----------------------------------------
doc_number() { # file -> the N of "`CONTEXT_BUDGET_CHARS` (N characters" (commas dropped)
  grep -oE '`CONTEXT_BUDGET_CHARS` \([0-9,]+ characters' "$1" | head -n 1 \
    | sed -E 's/.*\(([0-9,]+) characters/\1/' | tr -d ,
}
for doc in CHANGES.md PRD.md; do
  got="$(doc_number "$wf/$doc")"
  [ "$got" = "$CONTEXT_BUDGET_CHARS" ] \
    || fail "S309/docs — $doc states '${got:-nothing}' for CONTEXT_BUDGET_CHARS, constant is $CONTEXT_BUDGET_CHARS"
done
sed -E 's/`CONTEXT_BUDGET_CHARS` \([0-9,]+ characters/`CONTEXT_BUDGET_CHARS` (8,500 characters/' \
  "$wf/CHANGES.md" > "$SANDBOX/CHANGES.bad"
[ "$(doc_number "$SANDBOX/CHANGES.bad")" = "$CONTEXT_BUDGET_CHARS" ] \
  && fail "S309/neg-docs — a doc number different from the constant passed"

test_done
