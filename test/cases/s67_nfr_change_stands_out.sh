#!/usr/bin/env bash
# S67 — A change in the nfr register that affects the question set stands out.
# Covers: F2
#
# Demonstrated with a mutation, same style as R6/S41: a new nfr file with
# `applies-if: always` must make R9 diverge for every fixture, and
# that difference must name the new ID — not something silently resolvable
# by only adjusting the golden set.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

repo="$(sandbox_copy_repo)"
baseline="$repo/test/fixtures/baseline"

cat > "$repo/nfr/spec-mutation-test.md" <<'EOF'
---
id: spec-mutation-test
heading: Mutation test
order: 16
default: yes
applies-if: always
production-gate: no
status: active
---

## Question

Is this a test mutation?

## Yes means

This file exists only to demonstrate S67.

## Guidance

Not applicable.
EOF

# Overwriting TEST_REPO_ROOT would affect other tests; this test calls
# pending-changes.sh directly in the mutated copy, instead of via the
# pending_ids() helper that relies on TEST_REPO_ROOT.
#
# All four must diverge, not "at least one": every nfr file carries
# applies-if: always (LEESMIJ.md), so a mutation that does not stand
# out for all four points to a project that does not pick up the nfr source
# after all.
for project in $BASELINE_PROJECTS; do
  golden="$baseline/$project/verwacht-openstaand.txt"
  if [ ! -f "$golden" ]; then
    fail "S67 — golden set missing: $project"
    continue
  fi

  current="$SANDBOX/$project-mutated.txt"
  "$repo/pending-changes.sh" "$baseline/$project" 2>/dev/null \
    | grep '^  - ' | sed 's/^  - //; s/ —.*//' | sort > "$current"

  if diff -q "$golden" "$current" >/dev/null 2>&1; then
    fail "S67 — $project did not diverge from a new always-applicable nfr file; the mutation went unnoticed there"
  elif ! grep -qx 'spec-mutation-test' "$current"; then
    fail "S67 — $project diverged, but did not name spec-mutation-test as the new ID"
  fi
done

test_done
