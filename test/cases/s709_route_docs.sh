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
# label of every statement no single sentence of the doc holds. A term
# starting with `=` matches case-sensitively; a term starting with `!` must be
# absent from the sentence (case-sensitive); a term "a OR b" matches either.
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
        if t.startswith("!"):
            return t[1:] not in s
        if " OR " in t:
            return any(has(a, s) for a in t.split(" OR "))
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
first-segment|key|first|segment
attached-form|attached|-p|-c
codex-env|Codex child|=NO_PROXY|=no_proxy|127.0.0.1,localhost OR loopback|!ANTHROPIC_BASE_URL|!_CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL|!ANTHROPIC_CUSTOM_HEADERS
codex-dotenv|.env|=NO_PROXY|=no_proxy|refuse OR refusal
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
plant_doc first-segment-dropped first-segment '(?i)segment' 'part'
plant_doc attached-dropped attached-form '(?i)attached' 'joined'
# Round 4: the Codex environment statement dropped, naming only one of the
# two variables, or moved into the Claude sentence.
plant_doc codex-env-dropped codex-env '(?i)codex child' 'child'
plant_doc codex-env-only-NO_PROXY codex-env '(?<![A-Za-z_])no_proxy(?![A-Za-z_])' 'X'
plant_doc codex-env-only-no_proxy codex-env '(?<![A-Za-z_])NO_PROXY(?![A-Za-z_])' 'X'
plant_doc codex-env-in-claude-sentence codex-env '(?i)codex child' 'Codex child, like a Claude child with ANTHROPIC_BASE_URL,'
# Round 5: the .env statement dropped, naming only one of the two variables,
# or without the refusal.
plant_doc dotenv-dropped codex-dotenv '\.env(?![A-Za-z_])' ' file'
plant_doc dotenv-only-NO_PROXY codex-dotenv '(?<![A-Za-z_])no_proxy(?![A-Za-z_])' 'X'
plant_doc dotenv-only-no_proxy codex-dotenv '(?<![A-Za-z_])NO_PROXY(?![A-Za-z_])' 'X'
plant_doc dotenv-without-refusal codex-dotenv '(?i)refus[a-z]*' 'stops'

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
# The item set is exactly the five options and the six -c/--config
# first-segment keys of Architect report 7 (no trailing `*`).
EXPECTED_ITEMS='key chatgpt_base_url
key model_provider
key model_providers
key openai_base_url
key profile
key profiles
option --ignore-user-config
option --local-provider
option --oss
option --profile
option -p'
selection_items_ok() { # <label> <wrapper file>
  local got
  got="$(wrapper_list "$2" CODEX_SELECTION | python3 -I -c '
import sys
out = []
for line in sys.stdin.read().split("\n"):
    f = line.split()
    if len(f) == 1:
        out.append("option " + f[0])
    elif len(f) == 2 and f[0] == "-c|--config":
        out.append("key " + f[1])
    elif f:
        out.append("malformed " + line)
print("\n".join(sorted(out)))
')"
  [ "$got" = "$EXPECTED_ITEMS" ] || fail "S709/$1 — CODEX_SELECTION is not exactly the five options and six first-segment keys:
$got"
}
selection_items_ok codex-items "$R/route-child.sh"

# Planted drift on either side, and the same drift on both.
drop_doc_item() { # <src doc> <dst doc> <item line>
  python3 -I - "$1" "$2" "$3" <<'PY2'
import sys
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
out, inside, dropped = [], False, False
for line in lines:
    if "BEGIN codex-selection" in line:
        inside = True
    elif "END codex-selection" in line:
        inside = False
    elif inside and line.strip() == sys.argv[3] and not dropped:
        dropped = True
        continue
    out.append(line)
open(sys.argv[2], "w", encoding="utf-8").write("\n".join(out))
PY2
}
drop_doc_item "$DOC" "$SANDBOX/drift.md" --oss
rc_expect_red "S709/neg/codex-list-item-dropped-from-doc" lists_equal neg "$R/route-child.sh" "$SANDBOX/drift.md" CODEX_SELECTION codex-selection
drop_doc_item "$DOC" "$SANDBOX/drift-iuc.md" --ignore-user-config
rc_expect_red "S709/neg/ignore-user-config-dropped-from-doc" lists_equal neg "$R/route-child.sh" "$SANDBOX/drift-iuc.md" CODEX_SELECTION codex-selection
sed "s/^CODEX_SELECTION='--profile$/CODEX_SELECTION='--profile\\
--model/" "$R/route-child.sh" >"$SANDBOX/drift.sh"
rc_expect_red "S709/neg/codex-list-item-added-to-wrapper" lists_equal neg "$SANDBOX/drift.sh" "$DOC" CODEX_SELECTION codex-selection
sed "s/^CODEX_SELECTION='--profile$/CODEX_SELECTION='--profile\\
-c|--config openai_base_url/" "$R/route-child.sh" >"$SANDBOX/drift-url.sh"
rc_expect_red "S709/neg/openai_base_url-added-to-wrapper" lists_equal neg "$SANDBOX/drift-url.sh" "$DOC" CODEX_SELECTION codex-selection
# The same drop on both sides passes the comparison but not the item set.
grep -vx -- '--ignore-user-config' "$R/route-child.sh" >"$SANDBOX/both.sh"
lists_equal both-dropped "$SANDBOX/both.sh" "$SANDBOX/drift-iuc.md" CODEX_SELECTION codex-selection
rc_expect_red "S709/neg/same-drop-on-both-sides" selection_items_ok neg "$SANDBOX/both.sh"
# The 17517e6 prefix items restored on both sides.
sed -e 's/^-c|--config profiles$/-c|--config profiles.*/' -e 's/^-c|--config model_providers$/-c|--config model_providers*/' \
  "$R/route-child.sh" >"$SANDBOX/stars.sh"
sed -e 's/^-c|--config profiles$/-c|--config profiles.*/' -e 's/^-c|--config model_providers$/-c|--config model_providers*/' \
  "$DOC" >"$SANDBOX/stars.md"
lists_equal stars "$SANDBOX/stars.sh" "$SANDBOX/stars.md" CODEX_SELECTION codex-selection
rc_expect_red "S709/neg/17517e6-star-items-restored" selection_items_ok neg "$SANDBOX/stars.sh"

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
release_base=892dec572cb6232853ef28cb2d8d5fe4bfdc3499
if git -C "$R" merge-base --is-ancestor "$release_base" HEAD; then
  base_ref="$release_base"
else
  base_ref="$(git -C "$R" merge-base HEAD origin/main 2>/dev/null)"
fi
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
