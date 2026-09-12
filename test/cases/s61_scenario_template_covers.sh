#!/usr/bin/env bash
# S61 — The scenario template carries the coverage field and the grammar.
# Covers: F13
#
# A template that models the form without naming it does not teach the
# exception. Then the first `S2b` runs into an enforcement nobody saw
# coming - and a2t-emails already has that S2b today.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

template="$TEST_REPO_ROOT/templates/TEST-SCENARIOS.md"
[ -f "$template" ] || { fail "S61 — templates/TEST-SCENARIOS.md is missing"; test_done; }

# Then: every example scenario shows a **Covers:** field directly under its heading.
#
# The check remembers the previous line instead of looking ahead. A
# look-ahead variant loses a heading as soon as a new one directly follows -
# the heading pattern then fires before the check on the previous heading can
# run - and it never sees the file's last heading, since no line follows it
# anymore. Both cases produced a green result while the field was missing.
ontbreekt="$(awk '
  vorige_kop != "" && $0 !~ /^\*\*Covers:\*\*/ { print vorige_kop }
  { vorige_kop = "" }
  /^### [A-Z]{1,2}[0-9]+[a-z]?( |$)/ { vorige_kop = $2 }
  END { if (vorige_kop != "") print vorige_kop }
' "$template")"
[ -z "$ontbreekt" ] \
  || fail "S61 — scenarios without **Covers:** directly under the heading: $(echo "$ontbreekt" | tr '\n' ' ')"

# And: there is at least one example scenario, otherwise the check above is
# empty and green at the same time.
count="$(grep -cE '^### [A-Z]{1,2}[0-9]+[a-z]?( |$)' "$template")"
[ "$count" -ge 1 ] \
  || fail "S61 — not a single example scenario in the template"

# And: every scenario heading carries an ID. Counting only what has an ID
# leaves a heading without an ID untouched, and then the template does
# exactly what the convention forbids.
without_id="$(grep -E '^### ' "$template" | grep -vE '^### [A-Z]{1,2}[0-9]+[a-z]?( |$)' || true)"
[ -z "$without_id" ] \
  || fail "S61 — scenario heading without an ID: $(printf '%s' "$without_id" | tr '\n' ' ')"

# And: the grammar is stated explicitly, with S2b as an example.
grep -q '\^\[A-Z\]{1,2}\[0-9\]+\[a-z\]?\$' "$template" \
  || fail "S61 — the token grammar is not stated literally in the template"
grep -q 'S2b' "$template" \
  || fail "S61 — S2b is not present as an example alongside the grammar"

# And: the field shows a placeholder, not a made-up ID. A template with a
# real-looking `F3` invites copying it, and then the first scenario of every
# new project refers to functionality that does not exist.
fabricated="$(grep '^\*\*Covers:\*\*' "$template" | grep -v '<' || true)"
[ -z "$fabricated" ] \
  || fail "S61 — **Covers:** without a placeholder: $(printf '%s' "$fabricated" | tr '\n' ' ')"

test_done "S61"
