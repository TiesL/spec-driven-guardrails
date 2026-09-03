#!/usr/bin/env bash
# S12 — Push naar main wordt geblokkeerd, ook via refspec.
# Dekt: F7

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

guard="$TEST_REPO_ROOT/hooks/git-guardrails"
if [ ! -x "$guard" ]; then
  fail "S12 — hooks/git-guardrails ontbreekt"
  test_klaar
fi

# Twee werkmappen: één op een feature-branch, één op main. De guard moet de
# huidige branch raadplegen, want `git push origin HEAD` betekent iets anders
# afhankelijk van waar je staat.
op_feature="$(vers_project op-feature)"
git -C "$op_feature" commit -q --allow-empty -m start
git -C "$op_feature" checkout -q -b feature/werk

op_main="$(vers_project op-main)"
git -C "$op_main" commit -q --allow-empty -m start
git -C "$op_main" branch -M main

langs_guard() {
  local commando="$1" map="$2"
  printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"%s","tool_input":{"command":%s}}' \
    "$map" "$(printf '%s' "$commando" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
    | "$guard" >/dev/null 2>&1
  echo $?
}

geblokkeerd() {
  local omschrijving="$1" commando="$2" map="$3"
  if [ "$(langs_guard "$commando" "$map")" != "2" ]; then
    fail "S12 — niet geblokkeerd: $omschrijving ($commando)"
  fi
}
toegestaan() {
  local omschrijving="$1" commando="$2" map="$3"
  if [ "$(langs_guard "$commando" "$map")" = "2" ]; then
    fail "S12 — ten onrechte geblokkeerd: $omschrijving ($commando)"
  fi
}

# Expliciete refspecs die main raken — vanaf welke branch dan ook.
geblokkeerd "push origin main"        "git push origin main"        "$op_feature"
geblokkeerd "push origin HEAD:main"   "git push origin HEAD:main"   "$op_feature"
geblokkeerd "push met --force"        "git push --force origin main" "$op_feature"
geblokkeerd "push met +main"          "git push origin +main"       "$op_feature"
geblokkeerd "push die main verwijdert" "git push origin :main"      "$op_feature"

# --all en --mirror pushen alle branches, dus ook main - ongeacht waar je staat.
geblokkeerd "push --all"              "git push --all origin"       "$op_feature"
geblokkeerd "push --mirror"           "git push --mirror origin"    "$op_feature"
geblokkeerd "push met env-prefix"     "FOO=1 git push origin main"  "$op_feature"

# De toestandsafhankelijke kale push: alleen op de huidige branch keyen mist de
# categorie hierboven, en alleen op refspecs keyen mist deze.
geblokkeerd "kale push op main"       "git push"                    "$op_main"
geblokkeerd "push origin HEAD op main" "git push origin HEAD"       "$op_main"

# Legitiem werk moet blijven werken — de SessionEnd-hook doet precies dit.
toegestaan "push origin HEAD op feature" "git push origin HEAD"     "$op_feature"
toegestaan "kale push op feature"        "git push"                 "$op_feature"
toegestaan "push -u origin HEAD"         "git push -u origin HEAD"  "$op_feature"
toegestaan "push naar een feature-branch" "git push origin feature/werk" "$op_feature"
toegestaan "push naar maintenance"        "git push origin maintenance"  "$op_feature"

test_klaar
