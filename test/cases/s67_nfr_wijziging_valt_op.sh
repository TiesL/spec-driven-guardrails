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
nulmeting="$repo/test/fixtures/nulmeting"

cat > "$repo/nfr/spec-mutatietest.md" <<'EOF'
---
id: spec-mutatietest
heading: Mutatietest
order: 16
default: yes
applies-if: always
production-gate: no
status: active
---

## Question

Is dit een test-mutatie?

## Yes means

Dit bestand bestaat alleen om S67 aan te tonen.

## Guidance

Niet van toepassing.
EOF

# Overwriting TEST_REPO_ROOT would affect other tests; this test calls
# pending-changes.sh directly in the mutated copy, instead of via the
# openstaande_ids() helper that relies on TEST_REPO_ROOT.
#
# All four must diverge, not "at least one": every nfr file carries
# applies-if: always (LEESMIJ.md), so a mutation that does not stand
# out for all four points to a project that does not pick up the nfr source
# after all.
for project in $NULMETING_PROJECTEN; do
  gouden="$nulmeting/$project/verwacht-openstaand.txt"
  if [ ! -f "$gouden" ]; then
    fail "S67 — golden set missing: $project"
    continue
  fi

  huidig="$SANDBOX/$project-gemuteerd.txt"
  "$repo/pending-changes.sh" "$nulmeting/$project" 2>/dev/null \
    | grep '^  - ' | sed 's/^  - //; s/ —.*//' | sort > "$huidig"

  if diff -q "$gouden" "$huidig" >/dev/null 2>&1; then
    fail "S67 — $project did not diverge from a new always-applicable nfr file; the mutation went unnoticed there"
  elif ! grep -qx 'spec-mutatietest' "$huidig"; then
    fail "S67 — $project diverged, but did not name spec-mutatietest as the new ID"
  fi
done

test_klaar
