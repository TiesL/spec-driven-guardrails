#!/usr/bin/env bash
# S713 — The opt-in row exists, asks only projects that run the multi-agent roles, and injects no session text (#707; Scope: opt-in, AC10 second half)
# Covers: F75
#
# Seam: CHANGES.md through lib/changes.sh (predicate_true, the parser
# adopt.sh and pending-changes.sh share), pending-changes.sh, adopt.sh and
# session-context.sh on fixture projects, whole outputs compared byte for byte.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/pipeline-371-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pipeline-371-helpers.sh"
# shellcheck source=../../lib/changes.sh
. "$TEST_REPO_ROOT/lib/changes.sh"
# shellcheck source=../../lib/context-budget.sh
. "$TEST_REPO_ROOT/lib/context-budget.sh"

sandbox_create
trap sandbox_destroy EXIT

R="$TEST_REPO_ROOT"
C="$R/CHANGES.md"
id=process-model-routing

# --- the entry ---------------------------------------------------------------------
[ "$(grep -c "^## $id\$" "$C")" = 1 ] || fail "S713 — CHANGES.md has no single '## $id' entry"
entry="$(awk -v h="## $id" '$0==h{on=1; next} on && /^(## |---)/{exit} on{print}' "$C")"
q="$(grep -m1 '^- \*\*Question:\*\*' <<<"$entry")"
grep -q '?$' <<<"$q" || fail "S713 — the Question is not one closed line ending in '?': $q"
grep -qx -- '- \*\*Default:\*\* question' <<<"$entry" || fail "S713 — Default is not 'question'"
grep -qx -- '- \*\*Applies if:\*\* uses-multi-agent-roles' <<<"$entry" || fail "S713 — Applies if is not 'uses-multi-agent-roles'"
grep -qx -- '- \*\*Reaches session:\*\* none' <<<"$entry" || fail "S713 — Reaches session is not 'none'"
grep -q '^- \*\*PR:\*\* https://' <<<"$entry" || fail "S713 — no PR link"
grep -q '^- \*\*Meaning version:\*\*' <<<"$entry" && fail "S713 — a new entry carries a Meaning version (that is the maintainer's call)"
yes_means="$(awk '/^- \*\*Yes means:\*\*/{on=1} on && /^- \*\*Reaches session:\*\*/{exit} on{print}' <<<"$entry" | tr '\n' ' ' | tr -s ' ')"
grep -qF 'route-child.sh' <<<"$yes_means" || fail "S713 — Yes means does not say route-child.sh reads this answer"
grep -qiF 'session-context' <<<"$yes_means" && fail "S713 — Yes means promises session text"
grep -qE '127\.0\.0\.1:8787|ANTHROPIC_BASE_URL|x-cave-transforms' <<<"$entry" && fail "S713 — the entry names the route URL, the base-URL variable or the header"

# --- the predicate ---------------------------------------------------------------
grep -qE '^[[:space:]]+uses-multi-agent-roles\)' "$R/lib/changes.sh" || fail "S713 — predicate_true has no 'uses-multi-agent-roles)' arm"
pa="$SANDBOX/a"; pb="$SANDBOX/b"; pc="$SANDBOX/c"
for p in "$pa" "$pb" "$pc"; do mkdir -p "$p"; git -C "$p" init -q -b main; done
write_adoption "$pa/WORKFLOW-ADOPTION.md" process-multi-agent-roles yes
write_adoption "$pb/WORKFLOW-ADOPTION.md" process-multi-agent-roles no
predicate_true uses-multi-agent-roles "$pa" || fail "S713 — the predicate is false for a project that answered the roles yes"
predicate_true uses-multi-agent-roles "$pb" && fail "S713 — the predicate is true for a project that answered the roles no"
predicate_true uses-multi-agent-roles "$pc" && fail "S713 — the predicate is true for a project without an answer file"
predicate_true uses-multi-agent-role "$pa" && fail "S713 — a misspelled predicate evaluated true"

# --- pending-changes.sh and adopt.sh ----------------------------------------------
grep -qx "$id" <<<"$(pending_ids "$pa")" || fail "S713 — pending-changes.sh does not list $id for a roles-yes project"
grep -qx "$id" <<<"$(pending_ids "$pb")" && fail "S713 — pending-changes.sh lists $id for a roles-no project"
grep -qx "$id" <<<"$(pending_ids "$pc")" && fail "S713 — pending-changes.sh lists $id for a project without answers"
fresh="$(fresh_project fresh)"
adopt "$fresh" || fail "S713 — adopt.sh failed"
grep -qx "$id" <<<"$(seeded_ids "$fresh")" && fail "S713 — adopt.sh seeded $id (Default: question must not seed)"
grep -q . <<<"$(seeded_ids "$fresh")" || fail "S713 — adopt.sh seeded nothing (the seeding check checked nothing)"

# --- no session text: byte-identical output for every answer -------------------
compare_answers() { # <workflow clone> <project> <label> [extra adoption rows...]
  local wf="$1" proj="$2" label="$3" rt answer first out
  shift 3
  for rt in claude codex; do
    first=""
    for answer in yes no pending absent; do
      if [ "$answer" = absent ]; then
        write_adoption "$proj/WORKFLOW-ADOPTION.md" "$@"
      else
        write_adoption "$proj/WORKFLOW-ADOPTION.md" "$@" "$id" "$answer"
      fi
      out="$("$wf/session-context.sh" --runtime "$rt" "$proj" 2>&1; printf x)"
      if [ -z "$first" ]; then first="$out"
      elif [ "$out" != "$first" ]; then fail "S713/$label/$rt — output for '$answer' differs from 'yes'"; fi
    done
  done
}
plain="$SANDBOX/plain"
mkdir -p "$plain"
git -C "$plain" init -q -b main
compare_answers "$R" "$plain" plain process-multi-agent-roles yes

long="$(printf 'p%.0s' $(seq 1 100))"
wf="$SANDBOX/clone-$long"
mkdir -p "$wf"
(cd "$R" && tar --exclude='./.git' --exclude='./wip' --exclude='./CLAUDE.md' \
  --exclude='./.claude/settings.json' --exclude='./.claude/skills' -cf - .) | (cd "$wf" && tar -xf -)
wproj="$SANDBOX/project-$long"
mkdir -p "$wproj"
git -C "$wproj" init -q -b main
ln -s "$SANDBOX/nowhere/WORKFLOW.md" "$wproj/CLAUDE.md"
ids=()
while IFS='|' read -r sid value _; do
  case "$value" in session-context:*) ids+=("$sid" yes) ;; esac
done < <(reaches_session_values "$wf/CHANGES.md")
compare_answers "$wf" "$wproj" worst "${ids[@]}"
write_adoption "$wproj/WORKFLOW-ADOPTION.md" "${ids[@]}" "$id" yes
for n in 1 2; do
  size="$("$wf/session-context.sh" --runtime claude --slot "$n" "$wproj" 2>/dev/null | context_chars)"
  [ "$size" -le "$CONTEXT_BUDGET_CHARS" ] || fail "S713/budget — slot $n is $size characters with $id yes"
done

test_done
