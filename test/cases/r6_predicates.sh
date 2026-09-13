#!/usr/bin/env bash
# R6 — Predicate behavior identical and demonstrably correct.
# Covers: F3

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

table="$TEST_REPO_ROOT/test/fixtures/predicaten/waarheidstabel.txt"
[ -f "$table" ] || { fail "R6 — truth table is missing"; test_done; }

seen_ci_true=0
seen_deploy_true=0

while IFS='|' read -r name has_pkg content expected_ci expected_deploy; do
  case "$name" in ''|'#'*) continue ;; esac

  # Given: a fresh project according to this combination. No WORKFLOW-ADOPTIE.md,
  # so every applicable entry is also open - which makes a predicate that became
  # too strict visible here.
  project="$(fresh_project "$name")"
  [ "$has_pkg" = "ja" ] && printf '%s\n' "$content" > "$project/package.json"

  before="$SANDBOX/$name-before.txt"
  pending_ids "$project" > "$before"

  # Then: the outcome per combination is exactly what the table specifies.
  for pair in "ci-convention:$expected_ci" "ci-on-pr-and-main:$expected_ci" "ci-link-3-hard-block:$expected_ci" "ci-detects-main-outside-pr:$expected_ci" "deploy-guards:$expected_deploy"; do
    id="${pair%%:*}"; expected="${pair#*:}"
    if grep -qx "$id" "$before"; then actual=ja; else actual=nee; fi
    if [ "$actual" != "$expected" ]; then
      fail "R6 — $name: $id applicable=$actual, table says $expected"
    fi
  done

  [ "$expected_ci" = "ja" ] && seen_ci_true=1
  [ "$expected_deploy" = "ja" ] && seen_deploy_true=1

  adopt "$project"
  after="$SANDBOX/$name-after.txt"
  union="$SANDBOX/$name-union.txt"
  seeded="$SANDBOX/$name-seeded.txt"
  pending_ids "$project" > "$after"
  seeded_ids "$project" > "$seeded"
  { cat "$seeded" "$after"; } | sort -u > "$union"

  # And: what adopt.sh seeds is checked directly against the table. This is
  # the only check that sees when adopt.sh is MISSING something. The union below
  # cannot do that by construction: what adopt.sh does not seed simply stays
  # open, so the union remains unchanged. Both predicate
  # entries have `Default: yes`, so applicable here means seeded.
  for pair in "ci-convention:$expected_ci" "ci-on-pr-and-main:$expected_ci" "ci-link-3-hard-block:$expected_ci" "ci-detects-main-outside-pr:$expected_ci" "deploy-guards:$expected_deploy"; do
    id="${pair%%:*}"; expected="${pair#*:}"
    if grep -qx "$id" "$seeded"; then actual=ja; else actual=nee; fi
    if [ "$actual" != "$expected" ]; then
      fail "R6 — $name: adopt.sh seeded $id=$actual, table says $expected"
    fi
  done

  # And the total: 21 entries always apply, plus every applicable
  # predicate entry. `has-package-json` now contributes four -
  # `ci-convention` (what the workflow does), `ci-on-pr-and-main` (when it
  # runs), `ci-link-3-hard-block` (PR without issue) and
  # `ci-detects-main-outside-pr` (commit on main without PR). Catches
  # seed logic that is bulk-wrong.
  expected_count=21
  [ "$expected_ci" = "ja" ] && expected_count=$((expected_count + 4))
  [ "$expected_deploy" = "ja" ] && expected_count=$((expected_count + 1))
  seeded_count="$(grep -c . "$seeded")"
  if [ "$seeded_count" -ne "$expected_count" ]; then
    fail "R6 — $name: $seeded_count rows seeded, expected $expected_count"
  fi

  # And: both scripts arrive at the same answer. adopt.sh seeds the applicable
  # `Default: yes` entries; what remains open afterward are the
  # `Default: question` entries. Together exactly what was open before the adoption.
  assert_ids_equal "R6 — $name: seed logic versus applicability" "$before" "$union"
done < "$table"

# And: for every predicate there is at least one case where it is true and
# the entry unanswered. Without that requirement a predicate that became too
# strict stays invisible, since the difference then lands in no open set.
[ "$seen_ci_true" -eq 1 ] || fail "R6 — no case at all where has-package-json is true and unanswered"
[ "$seen_deploy_true" -eq 1 ] || fail "R6 — no case at all where has-deploy-script is true and unanswered"

test_done
