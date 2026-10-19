#!/usr/bin/env bash
# S317 — the core carries the dispatch-economy rules by ID, tier and part, and the inventory matches (#532 AC1-AC6, AC8; A42)
# Covers: F38
#
# Seam: the S311 harness test/fixtures/orchestrator-core.py on the real
# ORCHESTRATOR.md, orchestrator-rules.tsv and orchestrator-scenarios.md, plus
# content assertions on single rule items. No model call. Each negative control
# breaks one thing in a copy and must fail by its own name.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

R="$TEST_REPO_ROOT"
H="$R/test/fixtures/orchestrator-core.py"
ORCH="$R/skills/role-contracts/ORCHESTRATOR.md"
TSV="$R/skills/role-contracts/orchestrator-rules.tsv"
SCEN="$R/test/behavior/orchestrator-scenarios.md"
HOOK="$R/hooks/agent-dispatch.py"
PINS="$R/test/fixtures/orchestrator-core-pins.tsv"
checks="$(python3 -I "$HOOK" --list-checks 2>/dev/null | tr '\n' ' ')"

harness() { # orch tsv scen [repo]: output in $out, status in $st
  out="$(python3 -I "$H" check --orch "$1" --tsv "$2" --scen "$3" --pins "$PINS" --repo "${4:-$R}" --list-checks "$checks" 2>&1)"
  st=$?
}

item() { grep -m1 "^- $1 " "$2"; } # item <id> <orch file>
has() { grep -qF -- "$2" <<<"$1"; } # has <text> <needle>

# cc <orch> <tsv>: prints one line per content failure; nothing when all hold.
cc() {
  local o="$1" t="$2" id line row marker_line
  for id in OR4 OR13 OR22 OR23 OR28 OR33 OR46 OR47 OR48; do
    [ -n "$(item "$id" "$o")" ] || echo "missing-item: $id is not in the core"
  done
  row() { awk -F'\t' -v i="$1" '$1==i{print $2" "$3" "$4" "$5}' "$t"; }
  [[ "$(row OR46)" == "no-agent-steps judgment 1 "OB* ]] || echo "row-or46: expected 'no-agent-steps judgment 1' with covered_by OBs, got '$(row OR46)'"
  [[ "$(row OR47)" == "fresh-brief-size judgment 2 "OB* ]] || echo "row-or47: expected 'fresh-brief-size judgment 2' with covered_by OBs, got '$(row OR47)'"
  [[ "$(row OR48)" == "run-scope judgment 2 "OB* ]] || echo "row-or48: expected 'run-scope judgment 2' with covered_by OBs, got '$(row OR48)'"
  [[ "$(row OR13)" == "continuation-rule judgment 1 "* ]] || echo "row-or13: OR13 must be 'continuation-rule judgment 1', got '$(row OR13)'"
  grep -q 'continuing-other-roles-undecided' "$t" && echo "row-or13-old-name: continuing-other-roles-undecided is still in the inventory"
  for id in OR4 OR22 OR23 OR28 OR33; do
    case "$id" in OR4|OR33) p=1 ;; *) p=2 ;; esac
    [[ "$(row "$id")" == *" judgment $p "* ]] || echo "row-$id: tier or part changed"
  done
  line="$(item OR4 "$o")"
  has "$line" "authored" || echo "or4-authored: OR4 must limit the ban to authored work-item content"
  has "$line" "OR46" || echo "or4-pointer: OR4 must point to OR46"
  has "$line" "other work-item artifact" && echo "or4-old: OR4 still bans every other work-item artifact"
  line="$(item OR46 "$o")"
  for k in "(a)" "(b)" "(c)" "(d)"; do has "$line" "$k" || echo "or46-step: OR46 lacks step $k"; done
  has "$line" "(e)" && echo "or46-fifth: OR46 has a fifth step kind"
  has "$line" "dispatch" || echo "or46-dispatch: OR46 must say anything else is a dispatch"
  has "$line" "never repair" || echo "or46-repair: OR46 must say the orchestrator never repairs a failing command"
  has "$line" "generated" || echo "or46-generated: OR46 (b) is about generated, unedited files"
  has "$line" "read-only" || echo "or46-readonly: OR46 (c) is read-only git or gh"
  has "$line" "Pipeline log" || echo "or46-label-log: OR46 (d) names label and Pipeline log"
  line="$(item OR33 "$o")"
  has "$line" "OR46" || echo "or33-or46: OR33 must say an OR46 step never replaces a stage's dispatch or counts as stage done"
  line="$(item OR13 "$o")"
  has "$line" "working context" || echo "or13-context: OR13 must state the next-step-needs-its-working-context condition"
  has "$line" "100k" || echo "or13-100k: OR13 must state 100k tokens"
  has "$line" "60 tool uses" || echo "or13-60: OR13 must state 60 tool uses"
  has "$line" "SendMessage" || echo "or13-sendmessage: OR13 must name SendMessage"
  has "$line" "fork" || echo "or13-fork: OR13 must forbid fork"
  has "$line" "OR12" || echo "or13-or12: OR13 must keep Reviewer under OR12"
  has "$line" "work item" || echo "or13-across: OR13 must forbid continuing across work items"
  has "$line" "not decided" && echo "or13-undecided: OR13 still says not decided"
  line="$(item OR47 "$o")"
  has "$line" "links" || echo "or47-links: OR47 must say artifact links"
  has "$line" "scope" || echo "or47-scope: OR47 must say stated scope"
  has "$line" "history" || echo "or47-history: OR47 must forbid conversation or issue history"
  line="$(item OR48 "$o")"
  has "$line" "affected" || echo "or48-affected: OR48 (1) must scope a paid run to affected scenarios"
  has "$line" "stamp" || echo "or48-stamp: OR48 (1) must name the stamp exception"
  has "$line" "gate" || echo "or48-gate: OR48 (1) must name the gate exception"
  has "$line" "pre-commit" || echo "or48-doc-only: OR48 (2) must say a doc-only commit runs the pre-commit hooks only"
  has "$line" "doc-only" || echo "or48-doc-only-word: OR48 (2) must name the doc-only commit"
  has "$line" "once" || echo "or48-once: OR48 (2) must limit the full check to once before the PR opens"
  has "$line" "per commit" || echo "or48-per-commit: OR48 (2) must forbid the full check per commit"
  line="$(item OR28 "$o")"
  has "$line" "mechanical" || echo "or28-mechanical: OR28 must carry the mechanical-dispatch clause"
  has "$line" "OR39" || echo "or28-or39: OR28 must put the floor reason in the OR39 line"
  line="$(item OR22 "$o")"
  has "$line" "continued" || echo "or22-continued: OR22 must add continued yes/no"
  has "$line" "tool uses" || echo "or22-size: OR22 must add reported tokens and tool uses"
  has "$line" "OR46" || echo "or22-rule: OR22 must add the rule (OR13/OR46)"
  line="$(item OR23 "$o")"
  has "$line" "every dispatch line" || echo "or23-fields: OR23 must check every dispatch line has the fields"
  has "$line" "flag" || echo "or23-flag: OR23 must check an over-flag agent has a reason"
  marker_line="$(grep -nxF '<!-- session-context: slot -->' "$o" | cut -d: -f1)"
  [ "$(grep -c 'detail: `dispatch-economy`' "$o")" = 1 ] || echo "skill-pointer: the core must name 'detail: \`dispatch-economy\`' exactly once"
  [ "$(grep -n 'detail: `dispatch-economy`' "$o" | cut -d: -f1)" -lt "${marker_line:-0}" ] 2>/dev/null || echo "skill-pointer-part: the skill pointer belongs in part 1"
}

[ -r "$H" ] && [ -r "$ORCH" ] && [ -r "$TSV" ] || { fail "S317 — harness, core or inventory is missing"; test_done; }

harness "$ORCH" "$TSV" "$SCEN"
[ "$st" = 0 ] || fail "S317/real — structure check failed:
$out"
real="$(cc "$ORCH" "$TSV")"
[ -z "$real" ] || fail "S317/real — content assertions failed:
$real"

# The core with the skill file absent still passes the structure check.
nos="$SANDBOX/no-skill"
mkdir -p "$nos"
(cd "$R" && tar --exclude='./.git' --exclude='./wip' -cf - .) | (cd "$nos" && tar -xf -)
rm -rf "$nos/skills/dispatch-economy"
harness "$nos/skills/role-contracts/ORCHESTRATOR.md" "$nos/skills/role-contracts/orchestrator-rules.tsv" "$nos/test/behavior/orchestrator-scenarios.md" "$nos"
[ "$st" = 0 ] || fail "S317/skill-absent — the core needs the skill to pass the structure check:
$out"

# --- negative controls: each must fail by its own name ----------------------
d="$SANDBOX"
negc() { # name expected-prefix orch tsv
  local got
  got="$(cc "$3" "$4")"
  grep -q "^$2" <<<"$got" || fail "S317/neg-$1 — expected a '$2' failure, got: ${got:-nothing}"
}
negh() { # name expected-harness-error orch tsv
  harness "$3" "$4" "$SCEN"
  grep -q "^ERROR $2:" <<<"$out" || fail "S317/neg-$1 — expected ERROR $2, got: $out"
}
grep -v '^- OR46 ' "$ORCH" > "$d/o-no46.md"
negc or46-removed missing-item "$d/o-no46.md" "$TSV"
negh or46-removed-harness id-missing "$d/o-no46.md" "$TSV"

awk '/^- OR47 /{hold=$0; next} {print} /^- OR45 /{print hold}' "$ORCH" > "$d/o-p1.md"
negh or47-in-part1 wrong-part "$d/o-p1.md" "$TSV"

awk '/^- OR13 /{print $0 " Not decided here (#412)."; next} {print}' "$ORCH" | sed 's/Not decided/not decided/' > "$d/o-undec.md"
negc or13-undecided or13-undecided "$d/o-undec.md" "$TSV"

awk '/^- OR46 /{print $0 " (e) edit any file."; next} {print}' "$ORCH" > "$d/o-5th.md"
negc or46-fifth or46-fifth "$d/o-5th.md" "$TSV"

awk -F'\t' -v OFS='\t' '$1=="OR46"{$5=""} {print}' "$TSV" > "$d/t-nocov.tsv"
negh or46-uncovered judgment-no-ob "$ORCH" "$d/t-nocov.tsv"
negc or46-uncovered-cc row-or46 "$ORCH" "$d/t-nocov.tsv"

sed 's/^OR13\tcontinuation-rule/OR13\tcontinuing-other-roles-undecided/' "$TSV" > "$d/t-name.tsv"
negc or13-oldname row-or13 "$ORCH" "$d/t-name.tsv"

sed '/^- OR48 /s/pre-commit/precommit/' "$ORCH" > "$d/o-nodoc.md"
negc or48-no-doc-only or48-doc-only "$d/o-nodoc.md" "$TSV"

sed '/^- OR13 /s/100k/200k/' "$ORCH" > "$d/o-200k.md"
negc or13-threshold or13-100k "$d/o-200k.md" "$TSV"

test_done
