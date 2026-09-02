#!/usr/bin/env bash
# S46 — De branch wordt bepaald in de repo waar het commando over gaat.
# Dekt: F7

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

guard="$TEST_REPO_ROOT/hooks/git-guardrails"
[ -x "$guard" ] || { fail "S46 — hooks/git-guardrails ontbreekt"; test_klaar; }

op_main="$(vers_project op-main)"
git -C "$op_main" commit -q --allow-empty -m start
git -C "$op_main" branch -M main

op_feature="$(vers_project op-feature)"
git -C "$op_feature" commit -q --allow-empty -m start
git -C "$op_feature" checkout -q -b feature/werk

langs_guard() {
  printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"%s","tool_input":{"command":%s}}' \
    "$1" "$(printf '%s' "$2" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
    | "$guard" >/dev/null 2>&1
  echo $?
}

# Given: de sessie staat op main, het commando gaat over een repo op een
# feature-branch. Zou de guard naar de sessiemap kijken, dan blokkeert hij
# legitiem werk in een andere repo.
if [ "$(langs_guard "$op_main" "git -C $op_feature push origin HEAD")" = "2" ]; then
  fail "S46 — push in een andere repo geblokkeerd op grond van de sessiemap"
fi

# En omgekeerd: de sessie staat op een feature-branch, het commando gaat over een
# repo op main. Dat hoort wél geblokkeerd te worden.
if [ "$(langs_guard "$op_feature" "git -C $op_main push origin HEAD")" != "2" ]; then
  fail "S46 — push naar main in een andere repo doorgelaten"
fi

# --git-dir en --work-tree tellen net zo mee; git rekent zelf uit hoe ze zich
# verhouden. Hier alleen dat de guard ze niet meer als gewone vlag wegslikt,
# want dan verdween het subcommando uit beeld.
if [ "$(langs_guard "$op_feature" "git --git-dir $op_main/.git --work-tree $op_main push origin HEAD")" != "2" ]; then
  fail "S46 — --git-dir/--work-tree worden niet meegenomen in de branchbepaling"
fi
if [ "$(langs_guard "$op_feature" "git --git-dir /tmp/bestaat-niet reset --hard")" != "2" ]; then
  fail "S46 — een destructief commando met --git-dir wordt niet meer herkend"
fi

# Bestaat het pad niet of is het geen repo, dan komt er geen branch uit. Niet
# blokkeren: bij twijfel toestaan.
geen_repo="$SANDBOX/geen-repo"
mkdir -p "$geen_repo"
if [ "$(langs_guard "$op_feature" "git -C $geen_repo push origin HEAD")" = "2" ]; then
  fail "S46 — geblokkeerd terwijl het doelpad geen git-repo is"
fi
if [ "$(langs_guard "$op_feature" "git -C /bestaat/echt/niet push origin HEAD")" = "2" ]; then
  fail "S46 — geblokkeerd terwijl het doelpad niet bestaat"
fi

test_klaar
