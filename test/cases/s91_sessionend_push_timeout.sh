#!/usr/bin/env bash
# S91 — The SessionEnd push hook carries an explicit, realistic timeout.
# Covers: F18

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

haal_veld() {
  local veld="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -r ".hooks.SessionEnd[0].hooks[0].$veld // empty" "$TEST_REPO_ROOT/settings/session-hooks.json"
  else
    python3 -c '
import json, sys
h = json.load(open(sys.argv[1]))["hooks"]["SessionEnd"][0]["hooks"][0]
v = h.get(sys.argv[2], "")
# Match jq -r output for a JSON boolean (lowercase), not Python repr
# (True/False) — a naive print() here would silently defeat the "async"
# check whenever jq is absent, since "True" != "true".
if isinstance(v, bool):
    v = "true" if v else "false"
print(v if v != "" else "")
' "$TEST_REPO_ROOT/settings/session-hooks.json" "$veld"
  fi
}

timeout_waarde="$(haal_veld timeout)"
async_waarde="$(haal_veld async)"

# Given/When: the checked-in SessionEnd push hook, as it stands today.
# Then: it carries an explicit `timeout`, generous enough for a network
# push (#133 — the default 1.5s SessionEnd budget cancels a real `git
# push` more often than it succeeds), and comfortably within Claude
# Code's documented 60s ceiling for that shared budget.
[ -n "$timeout_waarde" ] || fail "S91 — the SessionEnd push hook has no explicit 'timeout' field"
if [ -n "$timeout_waarde" ]; then
  case "$timeout_waarde" in
    ''|*[!0-9]*) fail "S91 — 'timeout' is not a plain number: $timeout_waarde" ;;
    *)
      [ "$timeout_waarde" -ge 10 ] || fail "S91 — timeout ($timeout_waarde s) is not generous enough for a network push"
      [ "$timeout_waarde" -le 60 ] || fail "S91 — timeout ($timeout_waarde s) exceeds Claude Code's 60s SessionEnd ceiling"
      ;;
  esac
fi

# And: `async` is explicitly not `true` — a silent, backgrounded push
# failure is exactly the failure mode this repo avoids elsewhere (F6).
[ "$async_waarde" != "true" ] || fail "S91 — the push hook is 'async': true, which hides a real push failure instead of surfacing it"

test_klaar
