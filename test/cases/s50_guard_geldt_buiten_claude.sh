#!/usr/bin/env bash
# S50 — De guard geldt ook buiten Claude om.
# Dekt: F17

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

project="$(vers_project native-hooks)"
adopteer "$project"

# Een echte bare remote, anders bereikt git push origin main de pre-push-hook
# nooit — git faalt dan al eerder op "geen remote", en dat zou deze test iets
# heel anders laten aantonen dan bedoeld.
remote="$SANDBOX/remote.git"
git init -q --bare "$remote"
git -C "$project" remote add origin "$remote"

# Given: main uitgecheckt, de git-hooks geïnstalleerd (door adopteer). Eerst
# één toegestane eerste commit — een repo zonder commits mag zijn allereerste
# commit op main krijgen (zelfde uitzondering als in hooks/git-guardrails) —
# zodat de tweede poging hieronder de regel echt op de proef stelt.
[ -L "$project/.git/hooks/pre-commit" ] || fail "S50 — pre-commit is geen symlink na adopt.sh"
[ -L "$project/.git/hooks/pre-push" ] || fail "S50 — pre-push is geen symlink na adopt.sh"
git -C "$project" commit -q --allow-empty -m "eerste commit, toegestaan op main" \
  || fail "S50 — de allereerste commit (uitzondering) werd onterecht geweigerd"

# When: git commit rechtstreeks in een shell, zonder Claude ertussen.
uitvoer="$(cd "$project" && git commit -q --allow-empty -m "rechtstreeks op main" 2>&1)"
status=$?

# Then: geweigerd, met dezelfde melding als de PreToolUse-guard.
[ "$status" -ne 0 ] || fail "S50 — commit op main via een rechtstreekse git-aanroep werd niet geweigerd"
assert_contains "S50 — de melding komt overeen met de PreToolUse-guard" "main krijgt zijn wijzigingen via een PR" "$uitvoer"

# And: op een feature-branch gaat het gewoon door — dezelfde regel, niet een
# blokkade van alles.
git -C "$project" checkout -q -b feature/iets
if ! git -C "$project" commit -q --allow-empty -m "op een branch" 2>&1; then
  fail "S50 — een legitieme commit op een feature-branch werd geblokkeerd"
fi

# En git push origin main rechtstreeks, ook zonder Claude.
git -C "$project" checkout -q main
git -C "$project" branch -q --unset-upstream 2>/dev/null || true
push_uitvoer="$(cd "$project" && git push origin main 2>&1)"
push_status=$?
[ "$push_status" -ne 0 ] || fail "S50 — git push origin main werd niet geweigerd"
assert_contains "S50 — de push-melding komt overeen met de PreToolUse-guard" "main krijgt zijn wijzigingen via een PR" "$push_uitvoer"

test_klaar
