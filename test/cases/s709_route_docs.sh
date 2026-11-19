#!/usr/bin/env bash
# S709 — The docs say what routing does and does not do, in the right place only (#707; AC10 and the ARCHITECTURE.md decision)
# Covers: F75
#
# Seam: file reads. Each required statement is one sentence of
# docs/model-routing.md that holds all of its distinguishing terms (not one
# shared keyword; a term starting with `=` is matched case-sensitively); the
# settings-location list and the Codex selection list are each compared with
# the wrapper's single list definition; the doc passes the shared not-yes
# wording checker; the stamped files, WORKFLOW.md and its generated copies are
# searched for routing terms; the behavior stamp is checked with the runner's
# own stamp-check. Planted copies of the doc and the wrapper must turn each
# check red.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/route-child-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/route-child-helpers.sh"

sandbox_create
trap sandbox_destroy EXIT

R="$TEST_REPO_ROOT"
DOC="$R/docs/model-routing.md"
[ -f "$DOC" ] || { fail "S709 — docs/model-routing.md does not exist"; test_done; }

# statements <doc> <spec>: spec lines are "label|term|term|..."; prints the
# label of every statement no single sentence of the doc holds.
missing_statements() {
  python3 -I - "$1" "$2" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
text = re.sub(r"```.*?```", " ", text, flags=re.S)
flat = re.sub(r"\s+", " ", text)
sentences = re.split(r"(?<=[.!?:;])\s+(?=[A-Z`*(\-])|\s-\s(?=\*\*)", flat)
for line in open(sys.argv[2], encoding="utf-8"):
    line = line.rstrip("\n")
    if not line:
        continue
    label, *terms = line.split("|")
    def has(t, s):
        return t[1:] in s if t.startswith("=") else t.lower() in s.lower()
    if not any(all(has(t, s) for t in terms) for s in sentences):
        print(label)
PY
}

cat >"$SANDBOX/spec" <<'SPEC'
orchestrator-direct|Orchestrator|directly|never routed
children-through-wrapper|process|route-child.sh|proxy
subagents-not-routable|Agent tool|spawn_agent|not routable
runner-direct|behavior runner|direct by design
opt-in-answer|process-model-routing|answered_yes|only
off-only|SDG_MODEL_ROUTE=off|only switches routing off
codex-direct|model_provider="openai"|directly
never-bare|--bare|subscription
settings-outrank|outranks|refuses|=ANTHROPIC_BASE_URL|=_CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL|=NO_PROXY|=no_proxy|=ANTHROPIC_CUSTOM_HEADERS
credential-flow|bearer|API key|plain HTTP|127.0.0.1:8787|identify|accept
cut-stays-cut|stays cut|caveman_retrieve
seams-together|SDG_ROUTE_PROBE|SDG_ROUTE_MANAGED_SETTINGS
unknown-platform|other platform|refuses
managed-paths|/Library/Application Support/ClaudeCode/managed-settings.json|/etc/claude-code/managed-settings.json
proxy-down|exit 3|SDG_MODEL_ROUTE=off
pass-through-header|x-cave-transforms: caveman.pass-through.v1|byte-identical
SPEC
miss="$(missing_statements "$DOC" "$SANDBOX/spec")"
[ -z "$miss" ] || fail "S709 — docs/model-routing.md lacks these statements: $(echo $miss)"

# Each statement is required: a planted copy without it is caught.
# plant_doc <label> <expected missing label> <python regex> <replacement>
plant_doc() {
  python3 -I - "$DOC" "$SANDBOX/cut.md" "$3" "$4" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
open(sys.argv[2], "w", encoding="utf-8").write(re.sub(sys.argv[3], sys.argv[4], text))
PY
  grep -qx "$2" <<<"$(missing_statements "$SANDBOX/cut.md" "$SANDBOX/spec")" \
    || fail "S709/neg/$1 — the planted copy was not caught as missing '$2'"
}
plant_doc caveman_retrieve cut-stays-cut '(?i)caveman_retrieve' 'the recovery tool'
for v in _CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL NO_PROXY no_proxy ANTHROPIC_CUSTOM_HEADERS; do
  plant_doc "settings-only-$v-dropped" settings-outrank "(?<![A-Za-z_])$v(?![A-Za-z_])" 'X'
done
plant_doc credential-without-plain-http credential-flow '(?i)plain HTTP' 'HTTP'
plant_doc credential-without-bearer credential-flow '(?i)bearer' 'token'
plant_doc credential-without-api-key credential-flow '(?i)API key' 'key'
plant_doc credential-without-identify credential-flow '(?i)identify' 'check'
plant_doc credential-without-accept credential-flow '(?i)accept' 'note'

# --- the lists equal the wrapper's single list definitions ---------------------------
block() { # <file> <name> -> lines between the BEGIN/END <name> markers, trimmed, no comment prefix
  awk -v b="BEGIN $2" -v e="END $2" 'index($0, b) { on = 1; next } on && index($0, e) { exit } on' "$1" \
    | sed -E 's/^[#[:space:]]*//; s/[[:space:]]+$//' | grep -v '^```' | grep -v '^$'
}
wrapper_list() { # <wrapper file> <variable>
  sed -n "/^$2='/,/'\$/p" "$1" | sed "s/^$2='//; s/'\$//" | grep -v '^$'
}
lists_equal() { # <label> <wrapper file> <doc file> <variable> <block name>
  local w d
  w="$(wrapper_list "$2" "$4")"
  d="$(block "$3" "$5")"
  [ -n "$w" ] || fail "S709/$1 — route-child.sh has no $4 list"
  [ "$w" = "$d" ] || fail "S709/$1 — the doc's $5 list differs from the wrapper's $4:
wrapper:
$w
doc:
$d"
}
lists_equal list "$R/route-child.sh" "$DOC" SETTINGS_LOCATIONS settings-locations
lists_equal codex-list "$R/route-child.sh" "$DOC" CODEX_SELECTION codex-selection
# Planted drift on either side.
python3 -I - "$DOC" "$SANDBOX/drift.md" <<'PY'
import sys
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
out, inside, dropped = [], False, False
for line in lines:
    if "BEGIN codex-selection" in line:
        inside = True
    elif "END codex-selection" in line:
        inside = False
    elif inside and line.strip() == "--oss" and not dropped:
        dropped = True
        continue
    out.append(line)
open(sys.argv[2], "w", encoding="utf-8").write("\n".join(out))
PY
rc_expect_red "S709/neg/codex-list-item-dropped-from-doc" lists_equal neg "$R/route-child.sh" "$SANDBOX/drift.md" CODEX_SELECTION codex-selection
sed "s/^CODEX_SELECTION='--profile$/CODEX_SELECTION='--profile\\
--model/" "$R/route-child.sh" >"$SANDBOX/drift.sh"
rc_expect_red "S709/neg/codex-list-item-added-to-wrapper" lists_equal neg "$SANDBOX/drift.sh" "$DOC" CODEX_SELECTION codex-selection

# --- the not-yes wording checker ---------------------------------------------------
rc_not_yes_ok "S709/not-yes" "$DOC" codex
# Planted negative controls: the d51ba0d wording, and a planted "no means direct".
cat >"$SANDBOX/old.md" <<'OLD'
When the proxy does not answer, the wrapper stops with exit 3 without starting
the child and prints one line naming `http://127.0.0.1:8787`, the probe's exit
status, `SDG_MODEL_ROUTE=off` and the opt-out (answer `process-model-routing`
no). There is no silent fallback to a direct launch.

Before this change, Codex role children ran through the proxy in compress mode.
OLD
rc_expect_red "S709/neg/d51ba0d-opt-out-sentence" rc_not_yes_ok neg "$SANDBOX/old.md" codex
{ cat "$DOC"; echo; echo "Answer process-model-routing no to run children direct."; } >"$SANDBOX/planted.md"
rc_expect_red "S709/neg/planted-no-means-direct" rc_not_yes_ok neg "$SANDBOX/planted.md" codex

# --- no routing text in the stamped files, WORKFLOW.md or its generated copies --
terms='route-child|SDG_MODEL_ROUTE|SDG_ROUTE_PROBE|SDG_ROUTE_MANAGED_SETTINGS|8787|ANTHROPIC_BASE_URL|model routing'
for f in skills/role-contracts/ORCHESTRATOR.md WORKFLOW.md policy/WORKFLOW.md AGENTS.md adapters/codex/AGENTS.md \
  test/behavior/orchestrator-scenarios.md; do
  [ -f "$R/$f" ] || { fail "S709 — $f is missing"; continue; }
  hit="$(grep -niE "$terms" "$R/$f" | head -3)"
  [ -z "$hit" ] || fail "S709 — $f mentions routing: $hit"
done
cp "$R/WORKFLOW.md" "$SANDBOX/WORKFLOW.md"
echo "Model routing lives in docs." >>"$SANDBOX/WORKFLOW.md"
grep -qiE "$terms" "$SANDBOX/WORKFLOW.md" || fail "S709/neg — a planted term in a WORKFLOW.md copy was not caught"

# --- the stamp still holds, no new OR rule -----------------------------------------
python3 -I "$R/test/behavior/orchestrator_diff.py" stamp-check --repo "$R" >/dev/null 2>&1 \
  || fail "S709 — the behavior stamp check fails (a stamped file changed)"
base_ref="$(git -C "$R" merge-base HEAD origin/main 2>/dev/null)"
if [ -n "$base_ref" ]; then
  for f in skills/role-contracts/ORCHESTRATOR.md test/behavior/orchestrator-scenarios.md skills/role-contracts/orchestrator-rules.tsv; do
    git -C "$R" diff --quiet "$base_ref" -- "$f" || fail "S709 — $f changed against the merge base"
  done
else
  echo "S709 — origin/main is not available; the merge-base comparison was skipped (stamp-check still ran)" >&2
fi

# --- ARCHITECTURE.md decision entry A61 ----------------------------------------------
entry="$(awk '/^### A61 — /{on=1; print; next} on && /^### /{exit} on' "$R/ARCHITECTURE.md")"
grep -qE '^### A61 — .+ \(#707; F75\)$' <<<"$(head -1 <<<"$entry")" || fail "S709 — no '### A61 — ... (#707; F75)' heading in ARCHITECTURE.md"
for need in route-child.sh process-model-routing SDG_MODEL_ROUTE=off '**Violated when:**'; do
  grep -qF -- "$need" <<<"$entry" || fail "S709 — A61 does not name '$need'"
done

test_done
