#!/usr/bin/env bash
# S709 — The docs say what routing does and does not do, in the right place only (#707; AC10 and the ARCHITECTURE.md decision)
# Covers: F75
#
# Seam: file reads. Each required statement is one sentence of
# docs/model-routing.md that holds all of its distinguishing terms (not one
# shared keyword); the settings-location list is compared with the wrapper's
# single list definition; the stamped files, WORKFLOW.md and its generated
# copies are searched for routing terms; the behavior stamp is checked with
# the runner's own stamp-check.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

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
    if not any(all(t.lower() in s.lower() for t in terms) for s in sentences):
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
settings-outrank|outranks|ANTHROPIC_BASE_URL|refuses
cut-stays-cut|stays cut|caveman_retrieve
seams-together|SDG_ROUTE_PROBE|SDG_ROUTE_MANAGED_SETTINGS
unknown-platform|other platform|refuses
managed-paths|/Library/Application Support/ClaudeCode/managed-settings.json|/etc/claude-code/managed-settings.json
proxy-down|exit 3|SDG_MODEL_ROUTE=off
pass-through-header|x-cave-transforms: caveman.pass-through.v1|byte-identical
SPEC
miss="$(missing_statements "$DOC" "$SANDBOX/spec")"
[ -z "$miss" ] || fail "S709 — docs/model-routing.md lacks these statements: $(echo $miss)"

# Each statement is required: a doc without that sentence is caught.
python3 -I - "$DOC" "$SANDBOX/cut.md" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
open(sys.argv[2], "w", encoding="utf-8").write(re.sub(r"(?i)caveman_retrieve", "the recovery tool", text))
PY
grep -qx cut-stays-cut <<<"$(missing_statements "$SANDBOX/cut.md" "$SANDBOX/spec")" \
  || fail "S709/neg — dropping caveman_retrieve from the doc was not caught"

# --- the location list equals the wrapper's single list ---------------------------
block() { # <file> <begin-marker> -> lines between the markers, trimmed, no comment prefix
  awk -v b="$2" 'index($0, b) { on = 1; next } on && /END settings-locations/ { exit } on' "$1" \
    | sed -E 's/^[#[:space:]]*//; s/[[:space:]]+$//' | grep -v '^```' | grep -v '^$'
}
wrapper_list="$(sed -n "/^SETTINGS_LOCATIONS='/,/'$/p" "$R/route-child.sh" | sed "s/^SETTINGS_LOCATIONS='//; s/'$//" | grep -v '^$')"
doc_list="$(block "$DOC" "BEGIN settings-locations")"
[ -n "$wrapper_list" ] || fail "S709/list — route-child.sh has no SETTINGS_LOCATIONS list"
[ "$wrapper_list" = "$doc_list" ] || fail "S709/list — the doc's location list differs from the wrapper's:
wrapper:
$wrapper_list
doc:
$doc_list"

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
