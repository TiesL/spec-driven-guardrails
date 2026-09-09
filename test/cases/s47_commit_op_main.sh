#!/usr/bin/env bash
# S47 — Committen op main wordt geblokkeerd, met een begaanbare uitweg.
# Dekt: F7

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

guard="$TEST_REPO_ROOT/hooks/git-guardrails"
[ -x "$guard" ] || { fail "S47 — hooks/git-guardrails ontbreekt"; test_klaar; }

langs_guard() {
  printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"%s","tool_input":{"command":%s}}' \
    "$1" "$(printf '%s' "$2" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
    | "$guard" >/dev/null 2>&1
  echo $?
}

op_main="$(vers_project op-main)"
git -C "$op_main" commit -q --allow-empty -m start
git -C "$op_main" branch -M main

op_feature="$(vers_project op-feature)"
git -C "$op_feature" commit -q --allow-empty -m start
git -C "$op_feature" checkout -q -b feature/werk

# Een repo zonder ook maar één commit: HEAD bestaat nog niet.
vers="$(vers_project vers)"

# Then: committen op main wordt geblokkeerd.
[ "$(langs_guard "$op_main" 'git commit -m "iets"')" = "2" ] \
  || fail "S47 — committen op main werd niet geblokkeerd"
[ "$(langs_guard "$op_main" 'git commit --amend')" = "2" ] \
  || fail "S47 — amenden op main werd niet geblokkeerd"

# And: de melding noemt de uitweg én dat er niets kwijtraakt. Zonder die twee
# blijft het werk ongecommit, en dat is onveiliger dan wat je net tegenhield.
melding="$SANDBOX/melding.txt"
printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"%s","tool_input":{"command":"git commit -m x"}}' \
  "$op_main" | "$guard" >/dev/null 2>"$melding"

grep -q 'checkout -b' "$melding" || {
  fail "S47 — de melding noemt niet hoe je een branch maakt"
  cat "$melding" >&2
}
grep -qi 'come along unchanged\|nothing gets lost' "$melding" \
  || fail "S47 — de melding zegt niet dat de wijzigingen meegaan"

# And: op een feature-branch gaat committen gewoon door.
[ "$(langs_guard "$op_feature" 'git commit -m "iets"')" != "2" ] \
  || fail "S47 — committen op een feature-branch werd geblokkeerd"

# And: de allereerste commit van een nieuw project staat per definitie op main.
[ "$(langs_guard "$vers" 'git commit -m "eerste commit"')" != "2" ] \
  || fail "S47 — de eerste commit van een leeg repo werd geblokkeerd"

# En vertakken blijft natuurlijk gewoon mogelijk — anders is de uitweg dicht.
[ "$(langs_guard "$op_main" 'git checkout -b feature/nieuw')" != "2" ] \
  || fail "S47 — vertakken vanaf main werd geblokkeerd; de uitweg is dan dicht"

test_klaar
