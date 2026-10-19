#!/usr/bin/env bash
# S314 — the hook is wired once, drift is caught, and real captured input
# passes through it (#499 AC10)
# Covers: F38
#
# Seam: settings/session-hooks.json read as data, `agent-dispatch.py
# --print-contract` (the one place the tool name and input field names are
# defined), the committed fixture test/fixtures/agent-dispatch/
# agent-pretooluse-2.1.301.json, and an adopted project whose
# .claude/settings.json is the existing symlink into a clone copy.
#
# Fixture provenance: tool_name, tool_input (prompt, subagent_type, model,
# description, run_in_background) and tool_use_id are a real orchestrator
# `Agent` call recorded verbatim in a Claude Code 2.1.301 session transcript
# (a QA dispatch, 2026-10-16); the PreToolUse envelope fields around it
# (session_id, transcript_path, cwd, permission_mode, hook_event_name) are
# filled from the same transcript entry in the documented hook-input shape.
# The home directory in transcript_path is replaced by <user>.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"
# shellcheck source=../fixtures/agent-dispatch-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/agent-dispatch-helpers.sh"

sandbox_create
trap sandbox_destroy EXIT

FIX="$TEST_REPO_ROOT/test/fixtures/agent-dispatch/agent-pretooluse-2.1.301.json"
SETTINGS="$TEST_REPO_ROOT/settings/session-hooks.json"
[ -r "$AD_CORE" ] || { fail "S314 — hooks/agent-dispatch.py is missing"; test_done; }
[ -r "$FIX" ] || { fail "S314 — the captured input fixture is missing"; test_done; }

contract="$(python3 -I "$AD_CORE" --print-contract 2>/dev/null)"
[ -n "$contract" ] || fail "S314 — --print-contract printed nothing"

# wiring_ok <settings> : one PreToolUse entry whose matcher is the
# contract's tool name, timeout 10, through the readlink dispatcher.
wiring_ok() {
  python3 -I - "$1" "$contract" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); c = json.loads(sys.argv[2])
hits = []
for g in d.get("hooks", {}).get("PreToolUse", []):
    for h in g.get("hooks", []):
        if "hooks/agent-dispatch" in h.get("command", ""):
            hits.append((g.get("matcher"), h))
if len(hits) != 1:
    sys.exit("expected one PreToolUse entry for hooks/agent-dispatch, got %d" % len(hits))
m, h = hits[0]
if m != c["tool_name"]:
    sys.exit("matcher %r differs from the contract's tool name %r" % (m, c["tool_name"]))
if h.get("timeout") != 10:
    sys.exit("timeout %r, expected 10" % h.get("timeout"))
if 'readlink "$p/.claude/settings.json"' not in h["command"]:
    sys.exit("the command does not resolve the clone through the readlink dispatcher")
PY
}
msg="$(wiring_ok "$SETTINGS" 2>&1)" || fail "S314/wiring — $msg"
python3 -I - "$SETTINGS" "$SANDBOX/drift.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for g in d["hooks"]["PreToolUse"]:
    if any("hooks/agent-dispatch" in h.get("command", "") for h in g["hooks"]):
        g["matcher"] = "Task"
json.dump(d, open(sys.argv[2], "w"))
PY
wiring_ok "$SANDBOX/drift.json" >/dev/null 2>&1 && fail "S314/drift — a changed matcher was not caught"

# The fixture carries every field the contract names, and is the platform's
# real tool name.
python3 -I - "$FIX" "$contract" <<'PY' || fail "S314/fields — the captured input lacks a contract field"
import json, sys
d = json.load(open(sys.argv[1])); c = json.loads(sys.argv[2])
assert d["tool_name"] == c["tool_name"], "tool_name"
for f in c["fields"]:
    cur = d
    for part in f.split("."):
        if part == "agent_id":
            break  # absent on a top-level call by definition
        cur = cur[part]
PY

ad_run_core "$(cat "$FIX")"
[ "$ad_st" = 0 ] && [ -z "$ad_err" ] || fail "S314/captured — the captured compliant dispatch was not allowed silently ($ad_st: $ad_err)"
stripped="$(python3 -I - "$FIX" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
p = d["tool_input"]["prompt"].split("\n")
d["tool_input"]["prompt"] = "\n".join(p[1:])
print(json.dumps(d))
PY
)"
ad_run_core "$stripped"
[ "$ad_st" = 2 ] && grep -qxF -- "$(ad_core_line OR8)" <<<"$ad_err" \
  || fail "S314/captured-stripped — first line removed must exit 2 with the OR8 line ($ad_st: $ad_err)"

# An adopted project picks the hook up through its existing symlink, with no
# further adopt.sh run: the settings command, run as Claude Code runs it.
clone="$(sandbox_copy_repo clone)"
project="$(fresh_project adopter)"
SPEC_DRIVEN_GUARDRAILS_DIR="$clone" "$clone/adopt.sh" "$project" >/dev/null 2>&1
[ -L "$project/.claude/settings.json" ] || { fail "S314/adopted — no settings symlink"; test_done; }
write_adoption "$project/WORKFLOW-ADOPTION.md" process-multi-agent-roles yes
cmd="$(python3 -I - "$project/.claude/settings.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for g in d["hooks"]["PreToolUse"]:
    for h in g["hooks"]:
        if "hooks/agent-dispatch" in h["command"]:
            print(h["command"])
PY
)"
[ -n "$cmd" ] || fail "S314/adopted — the project's settings have no agent-dispatch command"
printf '%s' "$stripped" | (cd "$SANDBOX" && CLAUDE_PROJECT_DIR="$project" bash -c "$cmd") >/dev/null 2>"$SANDBOX/err"
st=$?
[ "$st" = 2 ] || fail "S314/adopted — the hook did not run through the symlink (exit $st: $(cat "$SANDBOX/err"))"

# CHANGES.md: Reaches session names the hook, Yes means gains the sentence,
# Meaning version unchanged (2, as on main).
entry="$(awk '/^## process-multi-agent-roles$/{f=1; next} f && /^## /{exit} f' "$TEST_REPO_ROOT/CHANGES.md")"
grep -q '^- \*\*Reaches session:\*\* .*hook: hooks/agent-dispatch' <<<"$entry" \
  || fail "S314/changes — Reaches session does not name hook: hooks/agent-dispatch"
yes_means="$(awk '/^- \*\*Yes means:\*\*/{f=1} f && /^- \*\*Reaches session/{exit} f' <<<"$entry")"
grep -q 'hooks/agent-dispatch' <<<"$yes_means" || fail "S314/changes — Yes means does not mention the dispatch hook"
grep -q '^- \*\*Meaning version:\*\* 2 —' <<<"$entry" || fail "S314/changes — Meaning version changed"

test_done
