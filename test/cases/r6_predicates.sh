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

while IFS='|' read -r name heeft_pkg content expected_ci expected_deploy; do
  case "$name" in ''|'#'*) continue ;; esac

  # Given: a fresh project according to this combination. No WORKFLOW-ADOPTIE.md,
  # so every applicable entry is also open - which makes a predicate that became
  # too strict visible here.
  project="$(fresh_project "$name")"
  [ "$heeft_pkg" = "ja" ] && printf '%s\n' "$content" > "$project/package.json"

  before="$SANDBOX/$name-before.txt"
  pending_ids "$project" > "$before"

  # Then: the outcome per combination is exactly what the table specifies.
  for paar in "ci-conventie:$expected_ci" "ci-op-pr-en-main:$expected_ci" "ci-schakel-3-hard-slot:$expected_ci" "ci-detecteert-main-buiten-pr:$expected_ci" "deploy-guards:$expected_deploy"; do
    id="${paar%%:*}"; verwacht="${paar#*:}"
    if grep -qx "$id" "$before"; then actual=ja; else actual=nee; fi
    if [ "$actual" != "$verwacht" ]; then
      fail "R6 — $name: $id applicable=$actual, table says $verwacht"
    fi
  done

  [ "$expected_ci" = "ja" ] && seen_ci_true=1
  [ "$expected_deploy" = "ja" ] && seen_deploy_true=1

  adopt "$project"
  na="$SANDBOX/$name-na.txt"
  samen="$SANDBOX/$name-samen.txt"
  geseed="$SANDBOX/$name-geseed.txt"
  pending_ids "$project" > "$na"
  seeded_ids "$project" > "$geseed"
  { cat "$geseed" "$na"; } | sort -u > "$samen"

  # And: what adopt.sh seeds is checked directly against the table. This is
  # the only check that sees when adopt.sh is MISSING something. The union below
  # cannot do that by construction: what adopt.sh does not seed simply stays
  # open, so the union remains unchanged. Both predicate
  # entries have `Default: yes`, so applicable here means seeded.
  for paar in "ci-conventie:$expected_ci" "ci-op-pr-en-main:$expected_ci" "ci-schakel-3-hard-slot:$expected_ci" "ci-detecteert-main-buiten-pr:$expected_ci" "deploy-guards:$expected_deploy"; do
    id="${paar%%:*}"; verwacht="${paar#*:}"
    if grep -qx "$id" "$geseed"; then actual=ja; else actual=nee; fi
    if [ "$actual" != "$verwacht" ]; then
      fail "R6 — $name: adopt.sh seeded $id=$actual, table says $verwacht"
    fi
  done

  # And the total: 21 entries always apply, plus every applicable
  # predicate entry. `heeft-package-json` now contributes four -
  # `ci-conventie` (what the workflow does), `ci-op-pr-en-main` (when it
  # runs), `ci-schakel-3-hard-slot` (PR without issue) and
  # `ci-detecteert-main-buiten-pr` (commit on main without PR). Catches
  # seed logic that is bulk-wrong.
  verwacht_aantal=21
  [ "$expected_ci" = "ja" ] && verwacht_aantal=$((verwacht_aantal + 4))
  [ "$expected_deploy" = "ja" ] && verwacht_aantal=$((verwacht_aantal + 1))
  aantal_geseed="$(grep -c . "$geseed")"
  if [ "$aantal_geseed" -ne "$verwacht_aantal" ]; then
    fail "R6 — $name: $aantal_geseed rows seeded, expected $verwacht_aantal"
  fi

  # And: both scripts arrive at the same answer. adopt.sh seeds the applicable
  # `Default: yes` entries; what remains open afterward are the
  # `Default: question` entries. Together exactly what was open before the adoption.
  assert_ids_equal "R6 — $name: seed logic versus van_toepassing()" "$before" "$samen"
done < "$table"

# And: for every predicate there is at least one case where it is true and
# the entry unanswered. Without that requirement a predicate that became too
# strict stays invisible, since the difference then lands in no open set.
[ "$seen_ci_true" -eq 1 ] || fail "R6 — no case at all where heeft-package-json is true and unanswered"
[ "$seen_deploy_true" -eq 1 ] || fail "R6 — no case at all where heeft-deploy-script is true and unanswered"

test_done
