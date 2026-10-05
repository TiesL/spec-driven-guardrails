#!/usr/bin/env bash
# S214 — each finding class is routed to the role that owns the fix, from any stage.
# Covers: F42
#
# Issue #410, AC2 (Architect A28; the fresh Reviewer at the end is #414).
# Seam: the text a session loads. The route sits in BOTH role-contracts and
# ORCHESTRATOR.md, as one table row, list item or sentence per class, with
# the roles in order (a regex with the roles in order fails when they are
# swapped or one is dropped).
#
# Mutations that turn this red (tag in the message):
#  route-design   in either file, delete the Architect from the design route, or put it after the Developer
#  route-code     in either file, swap QA and Developer in the code route
#  route-test     in either file, drop QA from the test route
#  route-spec     in either file, drop Product from the spec route, or put it after QA
#  no-relay       change "never relays ... as a decision" to "relays ... as a decision"
#  no-downgrade   delete the "never downgrades a class" sentence
#  doubt          delete the "no class or doubt: dispatch the Architect" sentence
#  any-stage      delete the step "saves the attempted patch" from the Developer/QA paragraph, or "stops the change"

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/loopback-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/loopback-helpers.sh"

lb_files
for f in "$LB_ROLES" "$LB_ORCH"; do
  [ -f "$f" ] || { fail "S214 — ${f#"$TEST_REPO_ROOT"/} does not exist"; test_done; }
done

# A route belongs to its class when the class is the row's (or list item's)
# label, or is written in backticks: a bare word like "test" in the code
# route ("QA (a red test)") must not make that row the test route.
# shellcheck disable=SC2016  # the format string is a literal ERE
cls() { printf '`%s`|^P \\|[[:space:]]*%s[[:space:]]*\\||^L [-*][[:space:]]+`?%s`?[[:space:]]*[:—-]' "$1" "$1" "$1"; }
for f in "$LB_ROLES" "$LB_ORCH"; do
  n="${f#"$TEST_REPO_ROOT"/}"
  lb_any_has_all "$f" "$(cls design)" 'Architect.*QA.*Developer.*fresh Reviewer' \
    || fail "S214/route-design — no row or sentence in $n sends a design defect to Architect, QA, Developer, fresh Reviewer, in that order"
  lb_any_has_all "$f" "$(cls code)" 'QA.*Developer.*fresh Reviewer' \
    || fail "S214/route-code — no row or sentence in $n sends a code defect to QA, Developer, fresh Reviewer, in that order"
  lb_any_has_all "$f" "$(cls test)" 'QA.*Developer.*fresh Reviewer' \
    || fail "S214/route-test — no row or sentence in $n sends a test defect to QA, Developer, fresh Reviewer, in that order"
  lb_any_has_all "$f" "$(cls spec)" 'Product.*QA.*Developer.*fresh Reviewer' \
    || fail "S214/route-spec — no row or sentence in $n sends a spec defect to Product, then QA, Developer, fresh Reviewer, in that order"
done

# ORCHESTRATOR.md: what the orchestrator may not do.
lb_sentence_has_all "$LB_ORCH" '(never|must not)[^.]*relay' 'fix' 'decision' \
  || fail "S214/no-relay — ORCHESTRATOR.md does not say the orchestrator never relays a Reviewer's suggested fix as a decision"
lb_sentence_has_all "$LB_ORCH" '(never|must not|not)[^.]*(downgrad|lower|reclass)' 'class' \
  || fail "S214/no-downgrade — ORCHESTRATOR.md does not say the orchestrator never downgrades a finding's class"
lb_sentence_has_all "$LB_ORCH" '(doubt|no class|without a class|lacks? a class|has no class|missing class)' '(dispatch|send|goes? to)[^.]*Architect' \
  || fail "S214/doubt — ORCHESTRATOR.md does not send a doubtful design class, or a finding with no class, to the Architect"

# From any stage: a Developer or QA that finds a design defect stops the
# change, saves the attempted patch (A12) and reports class design; the
# orchestrator then routes it like any finding. The block is the unit naming
# the Developer, QA and the design defect, plus the list items right after it.
start='^[PL] [^|].*((Developer.*QA|QA.*Developer).*design|design.*(Developer.*QA|QA.*Developer))'
[ -n "$(lb_block "$LB_ORCH" "$start")" ] \
  || fail "S214/any-stage — ORCHESTRATOR.md has no unit saying a Developer or QA can find a design defect"
lb_block_has_all "$LB_ORCH" "$start" '(stops?|halts?)[^.]*(change|work)' \
  || fail "S214/any-stage — ORCHESTRATOR.md does not say a Developer or QA that finds a design defect stops the change"
lb_block_has_all "$LB_ORCH" "$start" '(saves?|keeps?)[^.]*(attempted )?patch|patch[^.]*(saved|kept)' \
  || fail "S214/any-stage — ORCHESTRATOR.md does not say the stopping role saves the attempted patch (A12)"
lb_block_has_all "$LB_ORCH" "$start" '(reports?|reporting) [^.]*(class[^.]*design|design[- ]class|as design)' \
  || fail "S214/any-stage — ORCHESTRATOR.md does not say the stopping role reports the finding with class design"

test_done
