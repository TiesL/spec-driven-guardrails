#!/usr/bin/env bash
# S57 — Een mislukte commit of ontbrekend netwerk pusht niets.
# Dekt: F18

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

hook="$TEST_REPO_ROOT/hooks/push-na-commit"
[ -x "$hook" ] || { fail "S57 — hooks/push-na-commit ontbreekt"; test_klaar; }

# Geval 1: geen origin — de hook mag niets ophouden en niets op stderr geven
# dat als een fout oogt.
project="$(vers_project geen-origin)"
git -C "$project" commit -q --allow-empty -m start
git -C "$project" checkout -q -b feature/werk
git -C "$project" commit -q --allow-empty -m "werk zonder remote"

invoer1='{"hook_event_name":"PostToolUse","tool_name":"Bash","cwd":"'"$project"'","tool_input":{"command":"git commit -m x"}}'
status1=0
printf '%s' "$invoer1" | "$hook" >/dev/null 2>/dev/null || status1=$?
[ "$status1" -eq 0 ] || fail "S57/geval1 — geen origin gaf exit $status1 in plaats van 0"

# Geval 2: op main gebeurt sowieso niets, ook al bestaat de remote wél —
# dezelfde grens als de bestaande SessionEnd-hook.
project_main="$(vers_project op-main)"
remote="$SANDBOX/remote.git"
git init -q --bare "$remote"
git -C "$project_main" remote add origin "$remote"
git -C "$project_main" commit -q --allow-empty -m start

invoer2='{"hook_event_name":"PostToolUse","tool_name":"Bash","cwd":"'"$project_main"'","tool_input":{"command":"git commit -m x"}}'
printf '%s' "$invoer2" | "$hook" >/dev/null 2>&1

if git -C "$remote" rev-parse --verify --quiet main >/dev/null 2>&1; then
  fail "S57/geval2 — main werd toch gepusht vanuit push-na-commit"
fi

# Geval 3: een commando dat geen git commit is, pusht niets — geen enkele
# poging, ook al is er een remote en een feature-branch met unpushed werk.
project_ander="$(vers_project ander-commando)"
git -C "$project_ander" remote add origin "$remote"
git -C "$project_ander" commit -q --allow-empty -m start
git -C "$project_ander" checkout -q -b feature/iets
git -C "$project_ander" commit -q --allow-empty -m "nog niet gepusht"

invoer3='{"hook_event_name":"PostToolUse","tool_name":"Bash","cwd":"'"$project_ander"'","tool_input":{"command":"git status"}}'
printf '%s' "$invoer3" | "$hook" >/dev/null 2>&1

if git -C "$remote" rev-parse --verify --quiet feature/iets >/dev/null 2>&1; then
  fail "S57/geval3 — een niet-commit-commando triggerde toch een push"
fi

# Geval 4: het routinematige amend/rebase-geval, uit de review op PR #76.
# `git commit --amend` slaagt lokaal maar de daaropvolgende push wordt door
# origin geweigerd (non-fast-forward) — dat is geen netwerk- of
# toegangsprobleem, en de hook moet dat niet zo bestempelen, en zeker niet
# stilzwijgend forceren.
project_amend="$(vers_project amend)"
git -C "$project_amend" remote add origin "$remote"
git -C "$project_amend" commit -q --allow-empty -m start
git -C "$project_amend" checkout -q -b feature/amend
git -C "$project_amend" commit -q --allow-empty -m "eerste versie"
git -C "$project_amend" push -q -u origin feature/amend
git -C "$project_amend" commit -q --amend --allow-empty -m "herschreven versie"
sha_voor_amend_op_remote="$(git -C "$remote" rev-parse feature/amend)"

invoer4='{"hook_event_name":"PostToolUse","tool_name":"Bash","cwd":"'"$project_amend"'","tool_input":{"command":"git commit --amend -m x"}}'
uitvoer4="$(printf '%s' "$invoer4" | "$hook" 2>&1)"
status4=$?

[ "$status4" -eq 0 ] || fail "S57/geval4 — een geweigerde push (non-fast-forward) blokkeerde het commando (exit $status4)"
[ "$(git -C "$remote" rev-parse feature/amend)" = "$sha_voor_amend_op_remote" ] \
  || fail "S57/geval4 — de hook forceerde de push stilzwijgend, de remote-SHA veranderde"
case "$uitvoer4" in
  *"local history diverges"*) ;;
  *) fail "S57/geval4 — de melding noemt niet dat de lokale geschiedenis afwijkt (amend/rebase), maar: $uitvoer4" ;;
esac
case "$uitvoer4" in
  *"no network or no access"*)
    fail "S57/geval4 — de melding wijt het amend-geval ten onrechte aan netwerk/toegang: $uitvoer4" ;;
esac

test_klaar
