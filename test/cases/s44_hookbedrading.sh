#!/usr/bin/env bash
# S44 — De hookbedrading laat de blokkade door.
# Dekt: F7

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# Given: een project waarvan .claude/settings.json naar dit repo symlinkt.
project="$(vers_project bedraad)"
mkdir -p "$project/.claude"
ln -s "$TEST_REPO_ROOT/settings/session-hooks.json" "$project/.claude/settings.json"

opdracht="$(
  if command -v jq >/dev/null 2>&1; then
    jq -r '.hooks.PreToolUse[0].hooks[0].command' "$TEST_REPO_ROOT/settings/session-hooks.json"
  else
    python3 -c '
import json, sys
h = json.load(open(sys.argv[1]))["hooks"]["PreToolUse"][0]["hooks"][0]
print(h["command"])
' "$TEST_REPO_ROOT/settings/session-hooks.json"
  fi
)"

if [ -z "$opdracht" ]; then
  fail "S44 — geen PreToolUse-opdracht gevonden in session-hooks.json"
  test_klaar
fi

invoer='{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"'"$project"'","tool_input":{"command":"git reset --hard"}}'

# When/Then: de bedrading levert exit 2 op — de blokkade komt er echt uit.
printf '%s' "$invoer" | (cd "$project" && bash -c "$opdracht") >/dev/null 2>&1
status=$?
[ "$status" -eq 2 ] || fail "S44 — de bedrading gaf $status in plaats van 2; de guard blokkeert niet"

# And: de vorm met && en || doet dat níét. Deze controle staat er zodat die
# vorm niet ooit terugsluipt: hij ziet er werkend uit, maar de || vangt exit 2
# op en meldt succes.
fout_vorm='wf=$(dirname "$(dirname "$(readlink .claude/settings.json 2>/dev/null)")") && [ -x "$wf/hooks/git-guardrails" ] && "$wf/hooks/git-guardrails" || exit 0'
printf '%s' "$invoer" | (cd "$project" && bash -c "$fout_vorm") >/dev/null 2>&1
if [ $? -eq 2 ]; then
  fail "S44 — de aanname klopt niet meer: de &&/||-vorm laat exit 2 wél door"
fi

# En de geconfigureerde opdracht gebruikt die vorm dus niet.
case "$opdracht" in
  *'|| exit 0'*) fail "S44 — de hookopdracht gebruikt de vorm die exit 2 opslokt" ;;
esac
case "$opdracht" in
  *'exec '*) ;;
  *) fail "S44 — de hookopdracht gebruikt geen exec; de exitstatus komt dan niet door" ;;
esac

# Legitiem werk moet er ook via de bedrading doorheen komen.
git -C "$project" commit -q --allow-empty -m start
git -C "$project" checkout -q -b feature/werk
ok='{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"'"$project"'","tool_input":{"command":"git push origin HEAD"}}'
printf '%s' "$ok" | (cd "$project" && bash -c "$opdracht") >/dev/null 2>&1
[ $? -ne 2 ] || fail "S44 — de bedrading blokkeert een legitieme push"

test_klaar
