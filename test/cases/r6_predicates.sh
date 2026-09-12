#!/usr/bin/env bash
# R6 — Predicate behavior identical and demonstrably correct.
# Covers: F3

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

tabel="$TEST_REPO_ROOT/test/fixtures/predicaten/waarheidstabel.txt"
[ -f "$tabel" ] || { fail "R6 — truth table is missing"; test_klaar; }

gezien_ci_waar=0
gezien_deploy_waar=0

while IFS='|' read -r naam heeft_pkg inhoud verwacht_ci verwacht_deploy; do
  case "$naam" in ''|'#'*) continue ;; esac

  # Given: a fresh project according to this combination. No WORKFLOW-ADOPTIE.md,
  # so every applicable entry is also open - which makes a predicate that became
  # too strict visible here.
  project="$(vers_project "$naam")"
  [ "$heeft_pkg" = "ja" ] && printf '%s\n' "$inhoud" > "$project/package.json"

  voor="$SANDBOX/$naam-voor.txt"
  openstaande_ids "$project" > "$voor"

  # Then: the outcome per combination is exactly what the table specifies.
  for paar in "ci-conventie:$verwacht_ci" "ci-op-pr-en-main:$verwacht_ci" "ci-schakel-3-hard-slot:$verwacht_ci" "ci-detecteert-main-buiten-pr:$verwacht_ci" "deploy-guards:$verwacht_deploy"; do
    id="${paar%%:*}"; verwacht="${paar#*:}"
    if grep -qx "$id" "$voor"; then feitelijk=ja; else feitelijk=nee; fi
    if [ "$feitelijk" != "$verwacht" ]; then
      fail "R6 — $naam: $id applicable=$feitelijk, table says $verwacht"
    fi
  done

  [ "$verwacht_ci" = "ja" ] && gezien_ci_waar=1
  [ "$verwacht_deploy" = "ja" ] && gezien_deploy_waar=1

  adopteer "$project"
  na="$SANDBOX/$naam-na.txt"
  samen="$SANDBOX/$naam-samen.txt"
  geseed="$SANDBOX/$naam-geseed.txt"
  openstaande_ids "$project" > "$na"
  geseede_ids "$project" > "$geseed"
  { cat "$geseed" "$na"; } | sort -u > "$samen"

  # And: what adopt.sh seeds is checked directly against the table. This is
  # the only check that sees when adopt.sh is MISSING something. The union below
  # cannot do that by construction: what adopt.sh does not seed simply stays
  # open, so the union remains unchanged. Both predicate
  # entries have `Default: yes`, so applicable here means seeded.
  for paar in "ci-conventie:$verwacht_ci" "ci-op-pr-en-main:$verwacht_ci" "ci-schakel-3-hard-slot:$verwacht_ci" "ci-detecteert-main-buiten-pr:$verwacht_ci" "deploy-guards:$verwacht_deploy"; do
    id="${paar%%:*}"; verwacht="${paar#*:}"
    if grep -qx "$id" "$geseed"; then feitelijk=ja; else feitelijk=nee; fi
    if [ "$feitelijk" != "$verwacht" ]; then
      fail "R6 — $naam: adopt.sh seeded $id=$feitelijk, table says $verwacht"
    fi
  done

  # And the total: 21 entries always apply, plus every applicable
  # predicate entry. `heeft-package-json` now contributes four -
  # `ci-conventie` (what the workflow does), `ci-op-pr-en-main` (when it
  # runs), `ci-schakel-3-hard-slot` (PR without issue) and
  # `ci-detecteert-main-buiten-pr` (commit on main without PR). Catches
  # seed logic that is bulk-wrong.
  verwacht_aantal=21
  [ "$verwacht_ci" = "ja" ] && verwacht_aantal=$((verwacht_aantal + 4))
  [ "$verwacht_deploy" = "ja" ] && verwacht_aantal=$((verwacht_aantal + 1))
  aantal_geseed="$(grep -c . "$geseed")"
  if [ "$aantal_geseed" -ne "$verwacht_aantal" ]; then
    fail "R6 — $naam: $aantal_geseed rows seeded, expected $verwacht_aantal"
  fi

  # And: both scripts arrive at the same answer. adopt.sh seeds the applicable
  # `Default: yes` entries; what remains open afterward are the
  # `Default: question` entries. Together exactly what was open before the adoption.
  assert_ids_gelijk "R6 — $naam: seed logic versus van_toepassing()" "$voor" "$samen"
done < "$tabel"

# And: for every predicate there is at least one case where it is true and
# the entry unanswered. Without that requirement a predicate that became too
# strict stays invisible, since the difference then lands in no open set.
[ "$gezien_ci_waar" -eq 1 ] || fail "R6 — no case at all where heeft-package-json is true and unanswered"
[ "$gezien_deploy_waar" -eq 1 ] || fail "R6 — no case at all where heeft-deploy-script is true and unanswered"

test_klaar
