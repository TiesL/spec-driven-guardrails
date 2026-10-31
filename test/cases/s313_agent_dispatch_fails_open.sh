#!/usr/bin/env bash
# S313 — the dispatch hook allows everything outside its scope and fails
# open (#499 AC9)
# Covers: F38
#
# Seam: the bash adapter `hooks/agent-dispatch` (adoption check, kill
# switch, python3 lookup) in front of the core, behind a recording fake
# `gh` on PATH. Every case exits 0; only malformed input, unreadable files,
# a mapped ID with no line and a missing python3 write one diagnostic line.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/agent-dispatch-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"
# shellcheck source=../fixtures/agent-dispatch-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/agent-dispatch-helpers.sh"

sandbox_create
trap sandbox_destroy EXIT

[ -x "$AD_ADAPTER" ] || { fail "S313 — hooks/agent-dispatch is missing or not executable"; test_done; }

gh_log="$SANDBOX/gh-calls"
fbin="$SANDBOX/fakebin"
mkdir -p "$fbin"
printf '#!/bin/sh\necho "$@" >> "%s"\nexit 0\n' "$gh_log" > "$fbin/gh"
for t in curl wget nc; do printf '#!/bin/sh\necho "%s $*" >> "%s"\nexit 1\n' "$t" "$gh_log" > "$fbin/$t"; done
chmod +x "$fbin"/*
FPATH="$fbin:$PATH"

yes_proj="$SANDBOX/yes"; mkdir -p "$yes_proj"
write_adoption "$yes_proj/WORKFLOW-ADOPTION.md" process-multi-agent-roles yes
no_proj="$SANDBOX/no"; mkdir -p "$no_proj"
write_adoption "$no_proj/WORKFLOW-ADOPTION.md" process-multi-agent-roles no
pend_proj="$SANDBOX/pending"; mkdir -p "$pend_proj"
write_adoption "$pend_proj/WORKFLOW-ADOPTION.md" other-change yes
none_proj="$SANDBOX/none"; mkdir -p "$none_proj"

bad="$(ad_input "Hello
/c/model-record-emit.sh --stage Test" fork -)"   # breaks prefix, no-fork, model

# allows <case> <want-diag 0|1> <project> <json> [env...] : run the adapter.
allows() {
  local name="$1" diag="$2" proj="$3" json="$4" e t0 t1 n
  shift 4
  e="$SANDBOX/err"
  t0="$(date +%s)"
  out="$(printf '%s' "$json" | env PATH="$FPATH" CLAUDE_PROJECT_DIR="$proj" "$@" "$AD_ADAPTER" 2>"$e")"
  st=$?
  t1="$(date +%s)"
  [ "$st" = 0 ] || fail "S313/$name — expected exit 0, got $st ($(cat "$e"))"
  [ -z "$out" ] || fail "S313/$name — stdout must be empty"
  n="$(grep -c . "$e")"
  if [ "$diag" = 1 ]; then
    [ "$n" = 1 ] || fail "S313/$name — expected one diagnostic line, got $n: $(cat "$e")"
  else
    [ "$n" = 0 ] || fail "S313/$name — expected no output, got: $(cat "$e")"
  fi
  [ $((t1 - t0)) -le 2 ] || fail "S313/$name — took $((t1 - t0)) s"
}

# Sanity: the same bad input is denied in the opted-in project.
printf '%s' "$bad" | env PATH="$FPATH" CLAUDE_PROJECT_DIR="$yes_proj" "$AD_ADAPTER" >/dev/null 2>&1
[ $? = 2 ] || fail "S313/sanity — the non-compliant dispatch is not denied in an opted-in project"

allows no-file 0 "$none_proj" "$bad"
allows answered-no 0 "$no_proj" "$bad"
allows pending 0 "$pend_proj" "$bad"
allows guardrails-off 0 "$yes_proj" "$bad" CLAUDE_WORKFLOW_GUARDRAILS_OFF=1
allows subagent-call 0 "$yes_proj" "$(ad_input "Hello
/c/model-record-emit.sh --stage Test" fork - agent-7f3)"
allows not-role-dispatch 0 "$yes_proj" "$(ad_input "Find where X is defined." fork -)"
allows bash-tool 0 "$yes_proj" "$(ad_input "ROLE SESSION: nobody" fork - "" Bash)"
allows not-json 1 "$yes_proj" "this is not json"
allows no-tool-input 1 "$yes_proj" '{"tool_name":"Agent","tool_input":"x"}'
allows prompt-not-string 1 "$yes_proj" '{"tool_name":"Agent","tool_input":{"prompt":["ROLE SESSION: QA"]}}'

# Unreadable inventory / ORCHESTRATOR.md, and a mapped ID with no line:
# the core in a copied clone.
clone="$(sandbox_copy_repo clone)"
c_orch="$clone/skills/role-contracts/ORCHESTRATOR.md"
c_tsv="$clone/skills/role-contracts/orchestrator-rules.tsv"
mv "$c_tsv" "$c_tsv.away"
allows_clone() { # name -> adapter of the copied clone
  local a="$clone/hooks/agent-dispatch"
  local save_ad="$AD_ADAPTER"
  AD_ADAPTER="$a"
  allows "$1" 1 "$yes_proj" "$bad"
  AD_ADAPTER="$save_ad"
}
allows_clone inventory-unreadable
mv "$c_tsv.away" "$c_tsv"
mv "$c_orch" "$c_orch.away"
allows_clone orchestrator-unreadable
mv "$c_orch.away" "$c_orch"
grep -v '^- OR8 ' "$c_orch" > "$c_orch.new" && mv "$c_orch.new" "$c_orch"
allows_clone mapped-id-no-line

# No python3 on PATH.
nopy="$SANDBOX/nopy"
mkdir -p "$nopy"
for t in bash sh dirname cat sed awk grep tr printf env readlink; do
  p="$(command -v "$t" 2>/dev/null)" && ln -sf "$p" "$nopy/$t"
done
cp "$fbin/gh" "$nopy/gh"
out="$(printf '%s' "$bad" | env PATH="$nopy" CLAUDE_PROJECT_DIR="$yes_proj" "$(command -v bash)" "$AD_ADAPTER" 2>"$SANDBOX/err")"
st=$?
[ "$st" = 0 ] || fail "S313/no-python3 — expected exit 0, got $st"
[ "$(grep -c . "$SANDBOX/err")" = 1 ] || fail "S313/no-python3 — expected one diagnostic line: $(cat "$SANDBOX/err")"

# Never gh or the network, and no state written.
[ ! -s "$gh_log" ] || fail "S313/network — gh or a network tool was called: $(cat "$gh_log")"
grep -Eq '\bgh\b|curl|urllib|socket|http' "$AD_CORE" && fail "S313/network — the core names gh or a network module"
grep -Eq '(^|[^-])\bgh\b|curl|wget' "$AD_ADAPTER" && fail "S313/network — the adapter names gh or a network tool"
grep -Eq "open\([^)]*['\"][wa]" "$AD_CORE" && fail "S313/state — the core opens a file for writing"

# #599: role-only detection retains every out-of-scope allow policy.
bad_role="$(ad_input 'Hello
/c/model-record-emit.sh --role Product' fork -)"
for proj in "$none_proj" "$no_proj" "$pend_proj"; do
  allows role-not-opted-in 0 "$proj" "$bad_role"
done
allows role-guardrails-off 0 "$yes_proj" "$bad_role" CLAUDE_WORKFLOW_GUARDRAILS_OFF=1
allows role-subagent 0 "$yes_proj" "$(ad_input '/c/model-record-emit.sh --role Product' fork - agent-7f3)"
ad_run_core "$bad_role" "$SANDBOX/missing-orch" "$AD_TSV"
[ "$ad_st" = 0 ] && [ -z "$ad_out" ] && [ "$(printf '%s\n' "$ad_err" | grep -c .)" = 1 ] || fail "S313/#599 — detected role-only dispatch with unreadable core must allow with one diagnostic"
test_done
