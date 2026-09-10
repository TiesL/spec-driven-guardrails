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
project="$(vers_project doelproject)"

# spec-portability has `Standaard: vraag`, so it is left open after a fresh
# adoption. That is the control value.
SPEC_DRIVEN_GUARDRAILS_DIR="$repo" "$repo/adopt.sh" "$project" >/dev/null 2>&1
# Capture the output first: `... | grep -q` closes the pipe at the first hit,
# after which the producer gets SIGPIPE and the pipeline under `pipefail`
# returns non-zero even though the hit did occur.
voor="$SANDBOX/voor.txt"
"$repo/pending-changes.sh" "$project" > "$voor" 2>/dev/null
if ! grep -q 'spec-portability' "$voor"; then
  fail "S39 — spec-portability was not open; setup is flawed"
  test_klaar
fi

# Given: that attribute gets status: geretireerd.
sed -i.bak 's/^status: actief$/status: geretireerd/' "$repo/nfr/spec-portability.md"
rm -f "$repo/nfr/spec-portability.md.bak"

# When/Then: it is no longer asked.
na="$SANDBOX/na.txt"
"$repo/pending-changes.sh" "$project" > "$na" 2>/dev/null
if grep -q 'spec-portability' "$na"; then
  fail "S39 — spec-portability is still being asked after retirement"
fi

# And the question text should be present as long as the attribute is active:
# without a question, an open notification is unusable for whoever has to answer it.
if ! grep -q 'spec-portability — .' "$voor"; then
  fail "S39 — spec-portability was reported without a question text"
  grep 'spec-portability' "$voor" >&2
fi

# And: it is no longer in the generated block.
# shellcheck source=../../lib/nfr.sh
. "$repo/lib/nfr.sh"
blok="$SANDBOX/blok.txt"
nfr_blok "$repo/nfr" > "$blok"
if grep -q 'spec-portability' "$blok"; then
  fail "S39 — spec-portability is still in the generated block"
fi

# And: after regenerating, check no longer complains about drift.
if "$repo/check" --no-tests "$repo" >/dev/null 2>&1; then
  fail "S39 — check did not complain, while the template still holds the old block"
fi
(cd "$repo" && ./genereer-prd-blok >/dev/null 2>&1)
if ! "$repo/check" --no-tests "$repo" >/dev/null 2>&1; then
  fail "S39 — check still complains after regenerating"
  "$repo/check" --no-tests "$repo" 2>&1 | grep -E 'FOUT|betreft' >&2
fi

test_klaar
