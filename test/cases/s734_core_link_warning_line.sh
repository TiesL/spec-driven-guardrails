#!/usr/bin/env bash
# S734 — Session start prints one warning line, without rule text, when an opted-in project's core link is missing or wrong or a not-opted-in project still has it; enforcement follows the answer at once (#750 AC3, AC6; A66 D2, D3, D5)
# Covers: F38
#
# Seam: `session-context.sh --runtime claude <project>` output from a sandbox
# clone, for fixture projects whose CLAUDE.md links to that clone's
# WORKFLOW.md (so only the core-link state can add a line), plus
# hooks/agent-dispatch run with CLAUDE_PROJECT_DIR for the D5 enforcement
# check. The warning reads the `opt-in-loaded:` declaration, not a literal path.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"
# shellcheck source=../fixtures/core-delivery-750.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/core-delivery-750.sh"
# shellcheck source=../fixtures/agent-dispatch-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/agent-dispatch-helpers.sh"

sandbox_create
trap sandbox_destroy EXIT

wf="$(sandbox_copy_repo wf)"
ORCH="$wf/$CORE750_ORCH_REL"
other="$(sandbox_copy_repo other)"

# project <name> <answer|nofile> <link-state>: a project in a given state.
# link-state: ok | none | broken | other-clone | copy
project() {
  local p
  p="$(fresh_project "$1")"
  ln -s "$wf/WORKFLOW.md" "$p/CLAUDE.md"
  [ "$2" = nofile ] || write_adoption "$p/WORKFLOW-ADOPTION.md" process-multi-agent-roles "$2"
  mkdir -p "$p/.claude/rules"
  case "$3" in
    ok) ln -s "$ORCH" "$p/$CORE750_LINK" ;;
    broken) ln -s "$SANDBOX/nowhere/ORCHESTRATOR.md" "$p/$CORE750_LINK" ;;
    other-clone) ln -s "$other/$CORE750_ORCH_REL" "$p/$CORE750_LINK" ;;
    copy) cp "$ORCH" "$p/$CORE750_LINK" ;;
    none) ;;
  esac
  echo "$p"
}
sc() { # clone project -> stdout into $out, exit into $rc
  out="$("$1/session-context.sh" --runtime claude "$2" 2>"$SANDBOX/sc.err"; printf x)"
  rc=$?
  out="${out%x}"
}
no_rule_text() { # label
  printf '%s' "$out" > "$SANDBOX/out.txt"
  [ -z "$(core750_rule_hits "$ORCH" "$SANDBOX/out.txt")" ] || fail "S734/$1 — the output carries core rule text"
  grep -q '^# Multi-agent pipeline run rules' <<<"$out" && fail "S734/$1 — the output carries a core part heading"
  grep -qE '\bOR[0-9]+\b' <<<"$out" && fail "S734/$1 — the output names a rule ID"
  return 0
}
expect_silent() { # label project
  sc "$wf" "$2"
  [ "$rc" = 0 ] || fail "S734/$1 — exit $rc"
  [ -z "$out" ] || fail "S734/$1 — expected no output, got: $(head -n 2 <<<"$out" | tr '\n' ' ' | cut -c1-200)"
  no_rule_text "$1"
}
expect_warning() { # label project
  sc "$wf" "$2"
  [ "$rc" = 0 ] || fail "S734/$1 — exit $rc"
  [ "$(printf '%s' "$out" | grep -c .)" = 1 ] || fail "S734/$1 — expected exactly one line, got $(printf '%s' "$out" | grep -c .)"
  case "$out" in
    Warning:*) ;;
    *) fail "S734/$1 — the line does not start with 'Warning:': $(head -n 1 <<<"$out" | cut -c1-160)" ;;
  esac
  case "$out" in *sdg-orchestrator-core.md*) ;; *) fail "S734/$1 — the warning does not name sdg-orchestrator-core.md" ;; esac
  case "$out" in *adopt.sh*) ;; *) fail "S734/$1 — the warning does not name the adopt.sh remedy" ;; esac
  no_rule_text "$1"
}

# --- opted in --------------------------------------------------------------------
expect_silent yes-ok "$(project yes-ok yes ok)"
expect_warning yes-missing "$(project yes-missing yes none)"
expect_warning yes-broken "$(project yes-broken yes broken)"
expect_warning yes-other-clone "$(project yes-other yes other-clone)"
expect_warning yes-copy "$(project yes-copy yes copy)"
# --- not opted in (D5 lag: link still present until adopt.sh re-runs) -----------
expect_warning no-link-present "$(project no-link no ok)"
expect_warning pending-link-present "$(project pending-link pending ok)"
expect_warning nofile-link-present "$(project nofile-link nofile ok)"
expect_silent no-no-link "$(project no-none no none)"
expect_silent nofile-no-link "$(project nofile-none nofile none)"

# --- the warning reads the declaration ------------------------------------------
alt="$(sandbox_copy_repo alt)"
cp "$alt/$CORE750_ORCH_REL" "$alt/skills/role-contracts/ALT-750.md"
sed -i.bak "s#opt-in-loaded: $CORE750_ORCH_REL#opt-in-loaded: skills/role-contracts/ALT-750.md#" "$alt/CHANGES.md"
p="$(fresh_project declared)"
ln -s "$alt/WORKFLOW.md" "$p/CLAUDE.md"
write_adoption "$p/WORKFLOW-ADOPTION.md" process-multi-agent-roles yes
mkdir -p "$p/.claude/rules"
ln -s "$alt/skills/role-contracts/ALT-750.md" "$p/$CORE750_LINK"
sc "$alt" "$p"
[ -z "$out" ] || fail "S734/declared — a link to the declared path warns (a literal path is used): $(head -n 1 <<<"$out" | cut -c1-160)"
rm -f "$p/$CORE750_LINK"; ln -s "$alt/$CORE750_ORCH_REL" "$p/$CORE750_LINK"
sc "$alt" "$p"
[ "$(printf '%s' "$out" | grep -c '^Warning:')" = 1 ] || fail "S734/declared — a link to an undeclared file does not warn"

# --- D5: enforcement follows the answer at once ------------------------------------
bad="$(ad_input "Please do QA.
$(ad_prompt QA | tail -n +2)")"
for v in yes no; do
  p="$(project "enforce-$v" "$v" ok)"
  printf '%s' "$bad" | CLAUDE_PROJECT_DIR="$p" "$wf/hooks/agent-dispatch" >/dev/null 2>&1
  st=$?
  if [ "$v" = yes ]; then
    [ "$st" = 2 ] || fail "S734/enforce-yes — a dispatch without the prefix was not denied (exit $st; control)"
  else
    [ "$st" = 0 ] || fail "S734/enforce-no — a no answer with the core link still present is enforced (exit $st)"
  fi
done

test_done
