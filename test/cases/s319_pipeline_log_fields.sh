#!/usr/bin/env bash
# S319 — pipeline-log-fields.sh reports dispatch lines missing a field and agents over the flag limit without a reason (#532 AC7, C4; A42)
# Covers: F38
#
# Seam: `pipeline-log-fields.sh <issue>` against a fake `gh` on PATH that serves
# a fixture Pipeline log comment body (what the script's --jq filter would
# print). A dispatch line carries `agent=<id>`, `model=`, `continued=yes|no`,
# `rule=`, `tokens=` and `tools=` (reported size) and, when the agent is over
# the flag limit (tokens above 150k or tools above 100), `reason="..."`. Other
# lines (an OR46 command-and-result line) are not dispatch lines. The script
# reports and never blocks: exit 0 in every case (A33a).

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

SCRIPT="$TEST_REPO_ROOT/pipeline-log-fields.sh"
[ -x "$SCRIPT" ] || { fail "S319 — pipeline-log-fields.sh is missing or not executable"; test_done; }
sandbox_create
trap sandbox_destroy EXIT

mkdir -p "$SANDBOX/bin"
cat > "$SANDBOX/bin/gh" <<'GH'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_GH_LOG"
[ "${FAKE_GH_MODE:-ok}" = fail ] && { echo "gh: boom" >&2; exit 1; }
[ -f "$FAKE_GH_BODY" ] && cat "$FAKE_GH_BODY"
exit 0
GH
chmod +x "$SANDBOX/bin/gh"
export FAKE_GH_LOG="$SANDBOX/gh-calls" FAKE_GH_BODY="$SANDBOX/body"

run() { # run <fixture body or ''> [mode]: sets out, st
  if [ -n "${1:-}" ]; then printf '%s\n' "$1" > "$FAKE_GH_BODY"; else rm -f "$FAKE_GH_BODY"; fi
  out="$(PATH="$SANDBOX/bin:$PATH" FAKE_GH_MODE="${2:-ok}" "$SCRIPT" 532 2>&1)"
  st=$?
}

H='Pipeline log'
L_OK='- Implementation agent=a-ok model=claude-sonnet-5-5 continued=no rule=OR13 tokens=57k tools=7'
L_OK2='- Test agent=a-qa model=claude-opus-5-5 continued=yes rule=OR13 tokens=90k tools=40'
L_NOCONT='- Test agent=a-nocont model=claude-opus-5-5 rule=OR13 tokens=90k tools=40'
L_NOSIZE='- Test agent=a-nosize model=claude-opus-5-5 continued=no rule=OR13'
L_BIG='- Implementation agent=a-big model=claude-opus-5-5 continued=no rule=OR13 tokens=310k tools=120'
L_BIG_REASON='- Implementation agent=a-big model=claude-opus-5-5 continued=no rule=OR13 tokens=310k tools=120 reason="spec needs one long session"'
L_CMD='- ran ./check on branch: 276 passed, 0 failed (OR46 a)'

run "$H
$L_OK
$L_OK2
$L_CMD"
[ "$st" = 0 ] || fail "S319/(1)(6) — exit $st"
grep -qiE 'missing|over the limit' <<<"$out" && fail "S319/(1)(6) — a complete log and a command line reported a violation: $out"
grep -q 'issues/532/comments' "$FAKE_GH_LOG" || fail "S319 — the script did not read issue 532's comments through gh: $(cat "$FAKE_GH_LOG")"

run "$H
$L_OK
$L_NOCONT"
[ "$st" = 0 ] || fail "S319/(2) — must exit 0, got $st"
grep -q 'a-nocont' <<<"$out" && grep -q 'missing continued' <<<"$out" || fail "S319/(2) — expected a line naming a-nocont and 'missing continued': $out"
grep -q 'a-ok' <<<"$out" && fail "S319/(2) — the complete line was reported: $out"

run "$H
$L_NOSIZE"
[ "$st" = 0 ] || fail "S319/(3) — must exit 0, got $st"
grep -q 'a-nosize' <<<"$out" && grep -q 'missing reported size' <<<"$out" || fail "S319/(3) — expected a line naming a-nosize and 'missing reported size': $out"

run "$H
$L_BIG"
[ "$st" = 0 ] || fail "S319/(4) — must exit 0, got $st"
grep -q 'a-big' <<<"$out" && grep -q 'over the limit without a reason' <<<"$out" || fail "S319/(4) — expected a line naming a-big and 'over the limit without a reason': $out"

run "$H
$L_BIG_REASON"
[ "$st" = 0 ] || fail "S319/(5) — exit $st"
grep -qiE 'missing|over the limit' <<<"$out" && fail "S319/(5) — an over-limit line with a reason was reported: $out"

# A reason on a different agent id does not clear the over-limit agent.
run "$H
$L_BIG
- Test agent=a-other model=claude-opus-5-5 continued=no rule=OR13 tokens=20k tools=5 reason=\"unrelated\""
grep -q 'a-big' <<<"$out" && grep -q 'over the limit without a reason' <<<"$out" || fail "S319/other-id — a reason on another agent id cleared a-big: $out"

# Limits: exactly 150k tokens and exactly 100 tools are not over.
run "$H
- Test agent=a-edge model=m continued=no rule=OR13 tokens=150k tools=100"
grep -qiE 'missing|over the limit' <<<"$out" && fail "S319/edge — exactly at the limit was reported: $out"
run "$H
- Test agent=a-edge2 model=m continued=no rule=OR13 tokens=100k tools=101"
grep -q 'over the limit without a reason' <<<"$out" || fail "S319/edge2 — 101 tool uses must be over the limit: $out"

run ""
[ "$st" = 0 ] || fail "S319/(7) — no Pipeline log comment must still exit 0, got $st"
grep -qi 'could not read\|no Pipeline log' <<<"$out" || fail "S319/(7) — expected a warning that the log could not be read: $out"

run "$H
$L_OK" fail
[ "$st" = 0 ] || fail "S319/(8) — gh failing must still exit 0, got $st"
grep -qi 'could not read' <<<"$out" || fail "S319/(8) — expected a warning that the log could not be read: $out"

# Bad usage is a usage error, not a pass.
out="$("$SCRIPT" 2>&1)"; [ $? -ne 0 ] || fail "S319/usage — no argument must fail"
out="$("$SCRIPT" abc 2>&1)"; [ $? -ne 0 ] || fail "S319/usage — non-numeric issue must fail"

test_done
