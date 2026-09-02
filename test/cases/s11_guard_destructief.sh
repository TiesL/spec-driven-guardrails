#!/usr/bin/env bash
# S11 — Destructieve commando's worden geblokkeerd.
# Dekt: F7

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

guard="$TEST_REPO_ROOT/hooks/git-guardrails"
if [ ! -x "$guard" ]; then
  fail "S11 — hooks/git-guardrails ontbreekt of is niet uitvoerbaar"
  test_klaar
fi

werkmap="$(vers_project werkmap)"

# Voert het commando langs de guard, met dezelfde JSON-vorm die Claude Code op
# stdin aanlevert. Echoot de exitstatus: 2 betekent geblokkeerd.
langs_guard() {
  local commando="$1" map="${2:-$werkmap}"
  printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"%s","tool_input":{"command":%s}}' \
    "$map" "$(printf '%s' "$commando" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
    | "$guard" >/dev/null 2>&1
  echo $?
}

geblokkeerd() {
  local omschrijving="$1" commando="$2"
  if [ "$(langs_guard "$commando")" != "2" ]; then
    fail "S11 — niet geblokkeerd: $omschrijving ($commando)"
  fi
}

toegestaan() {
  local omschrijving="$1" commando="$2"
  if [ "$(langs_guard "$commando")" = "2" ]; then
    fail "S11 — ten onrechte geblokkeerd: $omschrijving ($commando)"
  fi
}

geblokkeerd "reset --hard"          "git reset --hard"
geblokkeerd "reset --hard HEAD~1"   "git reset --hard HEAD~1"
geblokkeerd "clean -fd"             "git clean -fd"
geblokkeerd "clean -f"              "git clean -f"
geblokkeerd "clean --force"         "git clean --force"
geblokkeerd "branch -D"             "git branch -D feature/oud"
geblokkeerd "checkout ."            "git checkout ."
geblokkeerd "checkout -- ."         "git checkout -- ."
geblokkeerd "restore ."             "git restore ."
geblokkeerd "in een keten"          "git add . && git reset --hard"

# Wat er níét geblokkeerd mag worden. Een vals positief blokkeert werk in vier
# projecten tegelijk, dus dit weegt zwaarder dan een gemist geval.
toegestaan "reset zonder --hard"    "git reset HEAD~1"
toegestaan "reset --soft"           "git reset --soft HEAD~1"
toegestaan "clean -n (dry run)"     "git clean -n"
toegestaan "branch -d (veilig)"     "git branch -d feature/klaar"
toegestaan "branch zonder vlag"     "git branch"
toegestaan "checkout van een branch" "git checkout main"
toegestaan "checkout -b"            "git checkout -b feature/nieuw"
toegestaan "restore van één bestand" "git restore src/app.ts"
toegestaan "checkout van één bestand" "git checkout -- src/app.ts"
toegestaan "status"                 "git status"
toegestaan "geen git-commando"      "rm -rf build"
toegestaan "de tekst in een string" "echo 'gebruik nooit git reset --hard'"

# Alleen segmenten die mét `git` beginnen worden beoordeeld. Zonder die eis zou
# elk commando waarvan het tweede woord toevallig een git-subcommando is worden
# geblokkeerd — en dat zijn gewone, dagelijkse commando's.
toegestaan "make clean met -f"      "make clean -f Makefile"
toegestaan "npm run clean"          "npm run clean -- --force"
toegestaan "docker restore"         "docker restore ."

# De bewuste uitweg. Een guard zonder uitweg wordt op den duur omzeild door het
# script aan te passen; die moet dus bestaan én luid zijn.
uit_fout="$SANDBOX/uitweg.txt"
printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"%s","tool_input":{"command":"git reset --hard"}}' \
  "$werkmap" | CLAUDE_WORKFLOW_GUARDRAILS_UIT=1 "$guard" >/dev/null 2>"$uit_fout"
uit_status=$?

[ "$uit_status" -ne 2 ] || fail "S11 — de uitweg werkt niet; het commando bleef geblokkeerd"
[ -s "$uit_fout" ] || fail "S11 — de uitweg meldt niets; een stille uitweg is een uitgezette guard"
grep -qi 'waarschuwing' "$uit_fout" || {
  fail "S11 — de melding bij de uitweg is niet als waarschuwing herkenbaar"
  cat "$uit_fout" >&2
}

test_klaar
