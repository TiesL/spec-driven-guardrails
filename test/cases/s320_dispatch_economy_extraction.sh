#!/usr/bin/env bash
# S320 — the documented transcript extraction command reports cache-read, cache-write, turns and last-turn context by agent id (#532 AC7, C4; A42)
# Covers: F38
#
# Seam: the command documented in skills/dispatch-economy/SKILL.md (the fenced
# block whose info string is `bash dispatch-economy-extract`, run verbatim as
# `bash <block> <transcript-dir> <agent-id>...`) against a sanitized fixture
# transcript directory. Field names come from a real Claude Code subagent
# transcript (see the fixture's SOURCE note): one JSON object per line, type
# "assistant", message.id (one response can span several lines, same usage),
# message.usage.{input_tokens, cache_creation_input_tokens,
# cache_read_input_tokens, output_tokens}. Files:
# <dir>/<session>/subagents/agent-<id>.jsonl. Advisory, local-only, never CI.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

SKILL="$TEST_REPO_ROOT/skills/dispatch-economy/SKILL.md"
[ -r "$SKILL" ] || { fail "S320 — skills/dispatch-economy/SKILL.md is missing"; test_done; }
sandbox_create
trap sandbox_destroy EXIT

cmd="$SANDBOX/extract.sh"
awk '/^```bash dispatch-economy-extract$/{on=1; next} /^```$/{if(on){exit}} on{print}' "$SKILL" > "$cmd"
[ -s "$cmd" ] || { fail "S320 — no \`\`\`bash dispatch-economy-extract block in the skill"; test_done; }
grep -qi 'local' "$SKILL" && grep -qi 'advisory' "$SKILL" || fail "S320 — the skill must say the extraction is local-only and advisory"

# Fixture: generated here from known numbers, in the real transcript's shape.
D="$SANDBOX/tx/sess-1/subagents"
mkdir -p "$D"
python3 -I - "$D" <<'PY'
import json, sys
d = sys.argv[1]
def line(agent, i, inp, cw, cr, out, split=False):
    base = {"agentId": agent, "type": "assistant", "isSidechain": True,
            "message": {"id": "msg_%s_%d" % (agent, i), "role": "assistant",
                        "usage": {"input_tokens": inp, "cache_creation_input_tokens": cw,
                                  "cache_read_input_tokens": cr, "output_tokens": out}}}
    return json.dumps(base)
def user(agent):
    return json.dumps({"agentId": agent, "type": "user", "message": {"role": "user", "content": "x"}})
# a-small: 7 turns. cache_read = 1000*i, cache_write = 10*i, input 2 each.
with open(d + "/agent-a-small.jsonl", "w") as f:
    f.write(user("a-small") + "\n")
    for i in range(1, 8):
        f.write(line("a-small", i, 2, 10 * i, 1000 * i, 5) + "\n")
        if i == 3:  # one response split over two lines: same id, same usage, one turn
            f.write(line("a-small", i, 2, 10 * i, 1000 * i, 5) + "\n")
        f.write(user("a-small") + "\n")
# a-big: 120 turns, last-turn context 310000 = 3 + 10000 + 299997
with open(d + "/agent-a-big.jsonl", "w") as f:
    for i in range(1, 121):
        if i < 120:
            f.write(line("a-big", i, 3, 100, 2000 * i, 7) + "\n")
        else:
            f.write(line("a-big", i, 3, 10000, 299997, 7) + "\n")
        if i == 50:
            f.write("{this is not json\n")
PY
# Known sums.
# a-small: turns 7, cache_read 1000*28=28000, cache_write 10*28=280, last context 2+70+7000=7072
# a-big: turns 120, cache_read 2000*(1+..+119)=2000*7140=14280000 + 299997, cache_write 100*119+10000
big_read=$((2000 * 7140 + 299997))
big_write=$((100 * 119 + 10000))

out="$(bash "$cmd" "$SANDBOX/tx" a-small a-big 2>"$SANDBOX/err")"
st=$?
[ "$st" = 0 ] || fail "S320 — known ids must exit 0, got $st: $out"
row() { grep "agent=$1 " <<<"$out"; }
s="$(row a-small)"; b="$(row a-big)"
for want in "turns=7" "cache_read=28000" "cache_write=280" "last_context=7072" "flagged=no"; do
  grep -qF -- "$want" <<<"$s" || fail "S320/a-small — expected $want in: $s"
done
for want in "turns=120" "cache_read=$big_read" "cache_write=$big_write" "last_context=310000" "flagged=yes"; do
  grep -qF -- "$want" <<<"$b" || fail "S320/a-big — expected $want in: $b"
done
grep -qiE 'skip|malformed' "$SANDBOX/err" || fail "S320/malformed — the malformed line must be skipped with a warning on stderr"

out="$(bash "$cmd" "$SANDBOX/tx" a-nope 2>&1)"
st=$?
[ "$st" -ne 0 ] || fail "S320/unknown — an unknown id must exit non-zero"
grep -qi 'not-found' <<<"$out" || fail "S320/unknown — expected a not-found line: $out"

# Flag by last context alone (turns well under 100): 160k final context.
mkdir -p "$SANDBOX/tx2/s/subagents"
printf '%s\n' '{"agentId":"a-ctx","type":"assistant","message":{"id":"m1","usage":{"input_tokens":1,"cache_creation_input_tokens":1000,"cache_read_input_tokens":159000,"output_tokens":3}}}' > "$SANDBOX/tx2/s/subagents/agent-a-ctx.jsonl"
out="$(bash "$cmd" "$SANDBOX/tx2" a-ctx 2>/dev/null)"
grep -q 'flagged=yes' <<<"$out" || fail "S320/ctx — 160k last context must be flagged: $out"

test_done
