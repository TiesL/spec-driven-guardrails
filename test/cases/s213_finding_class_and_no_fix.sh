#!/usr/bin/env bash
# S213 — a finding names its class and a falsifying check; a Reviewer never gives a fix.
# Covers: F42
#
# Issue #410, AC1 (Architect A28). Seam: the text a session loads. Asserts
# what the rule SAYS: negation placed before the thing it negates, so an
# inverted rule goes red (a bag-of-words test survives inversion).
#
# Mutations that turn this red (one per check; the tag is in the message):
#  class-field    delete the Class bullet, or drop one of the four values
#  falsify-field  delete the Falsifying check bullet, or its "correct fix" clause
#  never-fix      turn "Never a fix, a patch or code" into "Always a fix"
#  no-typo        change "no exception, not even for a typo" to "a typo may carry a fix"
#  same-for       delete the sentence that applies the rule to QA and the Developer
#  pmr            reword the pre-merge-review sentence to "names a fix", or drop its class

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
# shellcheck source=../fixtures/loopback-helpers.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/loopback-helpers.sh"

lb_files
for f in "$LB_ROLES" "$LB_PMR"; do
  [ -f "$f" ] || { fail "S213 — ${f#"$TEST_REPO_ROOT"/} does not exist"; test_done; }
done

# Class field: a bullet of the finding structure whose label is Class, naming
# all four values.
for v in design code test spec; do
  lb_unit_has_all "$LB_ROLES" '^L [-*] \*\*Class\*\*' "\`$v\`" \
    || fail "S213/class-field — no bullet '- **Class** ...' in role-contracts names the class \`$v\`"
done

# Falsifying check field: the observable condition a correct fix must meet.
lb_unit_has_all "$LB_ROLES" '^L [-*] \*\*Falsifying check\*\*' 'observable|condition' 'correct fix|a fix must' \
  || fail "S213/falsify-field — no bullet '- **Falsifying check** ...' in role-contracts says what a correct fix must meet"

# The prohibition: a sentence in which the negation comes BEFORE "fix" and
# "patch", in the role contracts and in pre-merge-review.
lb_sentence_has_all "$LB_ROLES" 'reviewer|finding' '(never|must not|do(es)? not)[^.]*(fix)[^.]*(patch)' \
  || fail "S213/never-fix — role-contracts has no sentence saying a finding never gives a fix or a patch"
lb_sentence_has_all "$LB_ROLES" '(never|must not|do(es)? not)[^.]*\bcode\b' '(fix)[^.]*(patch)|(patch)[^.]*(fix)' \
  || fail "S213/never-fix — role-contracts' prohibition does not also cover code"

# No typo exception (maintainer default 3, #408): the sentence that says so
# says "no exception" or "not even", never grants one.
lb_sentence_has_all "$LB_ROLES" 'typo|trivial|one-line' '(no exception|not even|without exception|never)' \
  || fail "S213/no-typo — role-contracts does not say the never-a-fix rule has no exception for a typo-level finding"
if lb_sentence_has_all "$LB_ROLES" 'typo|trivial' '\b(may|can|is allowed|are allowed)\b[^.]*(fix|patch|suggest)' \
  && ! lb_sentence_has_all "$LB_ROLES" 'typo|trivial' '(no exception|not even|without exception)'; then
  fail "S213/no-typo — role-contracts lets a typo-level finding carry a fix"
fi

# The same rule for QA and the Developer's findings.
lb_sentence_has_all "$LB_ROLES" '\bQA\b' 'Developer' '(same|also|too|likewise|alike|applies|holds)' 'fix|finding' \
  || fail "S213/same-for — role-contracts does not apply the never-a-fix rule to the findings of QA and the Developer"

# pre-merge-review: the Reviewer's own skill says it too.
lb_sentence_has_all "$LB_PMR" 'class' 'falsifying check' \
  || fail "S213/pmr — pre-merge-review does not say a finding names its class and a falsifying check"
lb_sentence_has_all "$LB_PMR" '(never|not|no)[^.]*\b(fix|fixes|patch)\b' 'finding|reviewer|class' 'class|falsifying|name' \
  || fail "S213/pmr — pre-merge-review does not say a finding gives no fix (it says findings, not fixes, but names no class or check)"

test_done
