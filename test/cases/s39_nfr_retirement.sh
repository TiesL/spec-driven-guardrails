#!/usr/bin/env bash
# S39 — A retired attribute disappears from both consumers.
# Covers: F4

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

repo="$(sandbox_copy_repo)"
project="$(fresh_project target-project)"

# spec-portability has `Default: question`, so it is left open after a fresh
# adoption. That is the control value.
SPEC_DRIVEN_GUARDRAILS_DIR="$repo" "$repo/adopt.sh" "$project" >/dev/null 2>&1
# Capture the output first: `... | grep -q` closes the pipe at the first hit,
# after which the producer gets SIGPIPE and the pipeline under `pipefail`
# returns non-zero even though the hit did occur.
before="$SANDBOX/before.txt"
"$repo/pending-changes.sh" "$project" > "$before" 2>/dev/null
if ! grep -q 'spec-portability' "$before"; then
  fail "S39 — spec-portability was not open; setup is flawed"
  test_done
fi

# Given: that attribute gets status: retired.
sed -i.bak 's/^status: active$/status: retired/' "$repo/nfr/spec-portability.md"
rm -f "$repo/nfr/spec-portability.md.bak"

# When/Then: it is no longer asked.
after="$SANDBOX/after.txt"
"$repo/pending-changes.sh" "$project" > "$after" 2>/dev/null
if grep -q 'spec-portability' "$after"; then
  fail "S39 — spec-portability is still being asked after retirement"
fi

# And the question text should be present as long as the attribute is active:
# without a question, an open notification is unusable for whoever has to answer it.
if ! grep -q 'spec-portability — .' "$before"; then
  fail "S39 — spec-portability was reported without a question text"
  grep 'spec-portability' "$before" >&2
fi

# And: it is no longer in the generated block.
# shellcheck source=../../lib/nfr.sh
. "$repo/lib/nfr.sh"
block="$SANDBOX/block.txt"
nfr_block "$repo/nfr" > "$block"
if grep -q 'spec-portability' "$block"; then
  fail "S39 — spec-portability is still in the generated block"
fi

# And: after regenerating, check no longer complains about drift.
if "$repo/check" --no-tests "$repo" >/dev/null 2>&1; then
  fail "S39 — check did not complain, while the template still holds the old block"
fi
(cd "$repo" && ./generate-prd-block >/dev/null 2>&1)
if ! "$repo/check" --no-tests "$repo" >/dev/null 2>&1; then
  fail "S39 — check still complains after regenerating"
  "$repo/check" --no-tests "$repo" 2>&1 | grep -E 'ERROR|regarding' >&2
fi

test_done
