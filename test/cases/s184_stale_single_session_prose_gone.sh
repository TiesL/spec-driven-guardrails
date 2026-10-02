#!/usr/bin/env bash
# S184 — No installed or always-loaded text tells an opted-in session that
# one session doing every stage is the norm, or that nothing applies the
# pipeline automatically.
# Covers: F38
#
# Issue #371, AC12 plus the Reviewer's note on PR #385 (README sentence and
# the entry's "Yes means" go stale once activation is automatic). Seam: the
# texts themselves; a phrase-level check, so it names the exact stale
# phrases found on the release branch rather than judging prose in general.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

root="$TEST_REPO_ROOT"
absent() { # file phrase label
  if grep -qiF -- "$2" "$root/$1"; then fail "S184 — $1 still says: $3 ('$2')"; fi
}
present() { # file phrase label
  if ! grep -qiF -- "$2" "$root/$1"; then fail "S184 — $1 is missing: $3 ('$2')"; fi
}

# model-choice: the "No behavior change" section is reconciled.
absent skills/model-choice/SKILL.md "No behavior change to single-agent-per-stage practice" "the stale section heading"
absent skills/model-choice/SKILL.md "doesn't require running each stage as a separate" "licence for single-session practice"
present skills/model-choice/SKILL.md "process-multi-agent-roles" "single session is the norm only unless the row is yes"
present skills/model-choice/SKILL.md "role-contracts" "pointer to the pipeline for opted-in projects"

# The gate's own header claimed a single session doing every stage is allowed.
absent skills/pre-merge-review/model-record-gate.sh "allows one session to do every stage" "the single-session allowance"

# README / CHANGES: activation is no longer "a separate work item".
absent README.md "Nothing starts the" "that nothing starts the pipeline"
absent README.md "not part of this offer" "that automatic activation is out of scope"
absent README.md "Making a session apply it automatically is a separate work item" "the pointer to a separate work item"
absent CHANGES.md "nothing applies the pipeline automatically" "the Yes means claim"
absent CHANGES.md "No orchestrator ships" "the Yes means claim"
present README.md "ORCHESTRATOR.md" "how a session gets the rules"
present CHANGES.md "session start" "Yes means says the rules load at session start"

test_done
