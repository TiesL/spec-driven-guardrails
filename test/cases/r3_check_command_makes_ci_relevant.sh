#!/usr/bin/env bash
# R3 — an executable check makes ci-convention relevant, not package.json
# by itself (#248).
# Covers: F3

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

project="$(fresh_project empty)"
adopt "$project"

without="$SANDBOX/without.txt"
pending_ids "$project" > "$without"

if grep -qx 'ci-convention' "$without"; then
  fail "R3 — ci-convention was already open without an executable check"
fi

# Given: the same project, now with package.json alone — this must NOT be
# enough on its own (#248: the real precondition is an executable check,
# not the stack).
echo '{"name":"t"}' > "$project/package.json"
pkg_only="$SANDBOX/pkg-only.txt"
pending_ids "$project" > "$pkg_only"
if grep -qx 'ci-convention' "$pkg_only"; then
  fail "R3 — ci-convention appeared from package.json alone, without an executable check"
fi

# When/Then: adding an executable check makes ci-convention appear.
printf '#!/usr/bin/env bash\necho checked\n' > "$project/check"
chmod +x "$project/check"
with="$SANDBOX/with.txt"
pending_ids "$project" > "$with"

grep -qx 'ci-convention' "$with" || fail "R3 — ci-convention did not appear after adding an executable check"

# And nothing else changes: the difference is exactly the four IDs attached to
# `has-check-command`. `ci-convention` is about what the CI does,
# `ci-on-pr-and-main` about when it runs, `ci-link-3-hard-block` and
# `ci-detects-main-outside-pr` about extra steps it also carries out;
# answerable independently, but dependent on the same predicate.
difference="$(comm -13 "$pkg_only" "$with" | tr '\n' ' ')"
[ "$difference" = "ci-convention ci-detects-main-outside-pr ci-link-3-hard-block ci-on-pr-and-main " ] \
  || fail "R3 — difference is '$difference', expected 'ci-convention ci-detects-main-outside-pr ci-link-3-hard-block ci-on-pr-and-main'"

test_done
