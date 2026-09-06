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

test_klaar
