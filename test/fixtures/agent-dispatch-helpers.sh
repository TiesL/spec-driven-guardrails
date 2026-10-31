#!/usr/bin/env bash
# test/fixtures/agent-dispatch-helpers.sh — shared helpers for the #499
# dispatch-hook scenarios (S312-S314). Source after test/lib.sh. Not a test.
#
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

AD_CORE="$TEST_REPO_ROOT/hooks/agent-dispatch.py"
AD_ADAPTER="$TEST_REPO_ROOT/hooks/agent-dispatch"
AD_ORCH="$TEST_REPO_ROOT/skills/role-contracts/ORCHESTRATOR.md"
AD_TSV="$TEST_REPO_ROOT/skills/role-contracts/orchestrator-rules.tsv"
AD_HARNESS="$TEST_REPO_ROOT/test/fixtures/orchestrator-core.py"

# ad_input <prompt> [subagent_type] [model|-] [agent_id] [tool_name]
# A synthetic PreToolUse JSON input on stdout. model "-" leaves it out.
ad_input() {
  python3 -I - "$1" "${2:-general-purpose}" "${3-sonnet}" "${4:-}" "${5:-Agent}" <<'PY'
import json, sys
prompt, sub, model, agent_id, tool = sys.argv[1:6]
ti = {"description": "fixture", "prompt": prompt, "subagent_type": sub}
if model != "-":
    ti["model"] = model
d = {"session_id": "fixture", "hook_event_name": "PreToolUse",
     "tool_name": tool, "tool_input": ti}
if agent_id:
    d["agent_id"] = agent_id
print(json.dumps(d))
PY
}

# ad_prompt <role> [stage] : a compliant role prompt for that role.
ad_prompt() {
  local role="$1" stage="${2:-}"
  if [ -z "$stage" ]; then
    case "$role" in
      Product) stage=Discovery ;; Architect) stage=Planning ;; QA) stage=Test ;;
      "Fullstack Developer") stage=Implementation ;; Reviewer) stage=Review ;;
    esac
  fi
  printf 'ROLE SESSION: %s\n\nQuoted contract here.\n\n/clone/skills/pre-merge-review/model-record-emit.sh --stage %s --model <your id>\n' "$role" "$stage"
  if [ "$role" = Reviewer ]; then
    printf 'PR #42, head 0123abc4567def, run finding-carryforward-gate.sh 42 first.\n'
  fi
}

# ad_core_line <ID> : that rule's physical line in the real core.
ad_core_line() {
  python3 -I "$AD_HARNESS" line --orch "${2:-$AD_ORCH}" "$1"
}

# ad_run_core <json> [orch] [tsv] : runs the core; sets ad_out, ad_err, ad_st.
ad_run_core() {
  local e
  e="$(mktemp)"
  ad_out="$(printf '%s' "$1" | python3 -I "$AD_CORE" "${2:-$AD_ORCH}" "${3:-$AD_TSV}" 2>"$e")"
  ad_st=$?
  ad_err="$(cat "$e")"
  rm -f "$e"
}

# ad_role_prompt <prefix role> [flag role]: role-only form, kept beside ad_prompt.
ad_role_prompt() {
  local role="$1" flag_role="${2:-$1}"
  [ "$flag_role" != "Fullstack Developer" ] || flag_role=Developer
  ad_prompt "$role" | sed "s/--stage [A-Za-z]*/--role $flag_role/"
}
