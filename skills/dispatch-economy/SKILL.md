---
name: dispatch-economy
description: Why the orchestrator's continue-or-fresh limits, no-agent steps and run scope are what they are, how the 100k and 60 numbers were derived, the transcript extraction command, and a worked Pipeline log line. Reasoning and tools only; the rules themselves are in the orchestrator's session rules (OR13, OR46, OR47, OR48). Use when revising the limits or auditing a heavy agent.
---

# Dispatch economy

The run rules a session obeys are injected at session start (`ORCHESTRATOR.md`,
rules OR13, OR46, OR47, OR48 and the OR22/OR23 log fields). Obeying them does
not need this file. It holds what is not a rule: why the numbers are what they
are, the command that measures an agent, and an example.

## Why (the case that produced them)

On #499 one Fullstack Developer agent ran 269 turns: 54.5M cache-read tokens,
5.0M cache-write tokens, a final context near 300k. It was continued three
times for a script run and a commit. Each continuation re-read the whole
context, and after each usage-limit pause the context had to be written again.
The work of those steps was a command and a commit; the cost was the reread.
A fresh agent with a brief reads a few thousand tokens instead.

Three costs sit under the rules:

- A continued agent pays for its whole history on every turn (cache-read), and
  for the whole history again once the cache expires (cache-write).
- A fresh agent pays for its brief plus the files it reads, and nothing else.
- A step that is a script run or a commit of a generated file needs no judgment,
  so it needs no agent at all (OR46).

## Threshold derivation (OR13)

Continue only when the next step needs the agent's working context and its
dispatch result reported at most 100k tokens and at most 60 tool uses.

- Bad case: the #499 Developer averaged 54.5M / 269, about 203k cache-read per
  turn, at a final context near 300k. Each continuation of it cost a 200-300k
  reread plus a rewrite after expiry.
- Good case: Product on #532 used 7 tool uses and 57k tokens. Continuing it is
  cheap.
- 100k is about a third of the bad case and about twice the good one. It is a
  judgment, not a fitted number. The flag limit for the log check (150k final
  context or 100 turns) is higher than the continue limit, so a continued agent
  has headroom before it is flagged.
- The orchestrator can read only the dispatch result's reported tokens and tool
  uses, a proxy for context and not context itself (accepted in #532 Human
  decision 2.2). The transcript command below measures the real numbers.

The limits are revised from the first few work items' extracted data (Human
decision 2.3 on #532). When the data shows the rule is ignored, an automatic
block on over-threshold continuation is the next step; it needs hook state and
is not built yet. #500 and #501 cover context reset and may reuse the
extraction; this change adds no `/clear` rule.

## What is checkable where

- GitHub-visible: `pipeline-log-fields.sh <issue>` reads the Pipeline log
  comment and prints dispatch lines that miss a field and agents reported over
  the flag limit without a `reason=`. It reports and exits 0; it does not block
  a merge. The log is a recorded self-check, not proof.
- Local only: the transcript command below, on the maintainer's machine. It is
  advisory and is not a CI step; paste its output into the Pipeline log when
  used.

## Transcript extraction command (local-only, advisory)

Runtime: this command is Claude-only (it reads Claude Code's subagent
transcripts). No Codex counterpart ships until the Codex rollout-file format
is verified on a real run; until then a Codex orchestrator logs `n/a` for sizes.

Claude Code writes each subagent's transcript to
`~/.claude/projects/<project>/<session>/subagents/agent-<agent-id>.jsonl`, one
JSON object per line. The fields used: `type` is `assistant`; `message.id`
names one model response (a response can span several lines with the same id
and the same usage, so lines are counted once per id);
`message.usage.input_tokens`, `cache_creation_input_tokens` (cache-write),
`cache_read_input_tokens` and `output_tokens`. Context of a turn = input +
cache-write + cache-read tokens of that response.

Run it with the transcripts directory and one or more agent ids. It prints per
agent the turn count, summed cache-read, summed cache-write, the last turn's
context and a flag (more than 150k last-turn context or more than 100 turns).
An unknown id prints a `not-found` line and the command exits non-zero. A
malformed line is skipped with a warning on stderr.

```bash dispatch-economy-extract
# bash extract.sh <transcripts-dir> <agent-id>...
dir="${1:?transcripts dir}"; shift
python3 -I - "$dir" "$@" <<'PY'
import json, os, sys
root, ids = sys.argv[1], sys.argv[2:]
missing = 0
for aid in ids:
    path = None
    for d, _, fs in os.walk(root):
        if "agent-%s.jsonl" % aid in fs:
            path = os.path.join(d, "agent-%s.jsonl" % aid)
            break
    if path is None:
        print("agent=%s not-found" % aid)
        missing = 1
        continue
    turns = {}
    for n, line in enumerate(open(path, encoding="utf-8", errors="replace"), 1):
        line = line.strip()
        if not line:
            continue
        try:
            d = json.loads(line)
        except ValueError:
            sys.stderr.write("warning: skipped malformed line %d of %s\n" % (n, path))
            continue
        if not isinstance(d, dict) or d.get("type") != "assistant":
            continue
        m = d.get("message") or {}
        u = m.get("usage") or {}
        turns[m.get("id") or "line-%d" % n] = u
    rd = sum(u.get("cache_read_input_tokens", 0) for u in turns.values())
    wr = sum(u.get("cache_creation_input_tokens", 0) for u in turns.values())
    last = list(turns.values())[-1] if turns else {}
    ctx = sum(last.get(k, 0) for k in ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"))
    why = []
    if ctx > 150000:
        why.append("context>150k")
    if len(turns) > 100:
        why.append("turns>100")
    print("agent=%s turns=%d cache_read=%d cache_write=%d last_context=%d flagged=%s" % (
        aid, len(turns), rd, wr, ctx, ("yes (%s)" % ",".join(why)) if why else "no"))
sys.exit(1 if missing else 0)
PY
```

The fixture in `test/cases/s320_dispatch_economy_extraction.sh` is generated
from known numbers in this shape; no real transcript content is stored in the
repository.

## Worked Pipeline log example

One line per dispatch, at dispatch, fields as `key=value` (OR22):

```
- Implementation agent=a91762 model=claude-sonnet-5-5 continued=no rule=OR13 tokens=310k tools=269 reason="design spike needed the whole file set"
- Test agent=a2f0c7 model=claude-opus-5-5 continued=yes rule=OR13 tokens=57k tools=7
- ran ./check on the branch: 276 passed, 0 failed (OR46 a)
```

Line one carries a reason because 310k tokens is over the flag limit; line two
is a continuation that stayed under both continue limits; line three is a
no-agent step, so it has no `agent=` and the script skips it. Run
`pipeline-log-fields.sh <issue>` to list lines that miss a field.
