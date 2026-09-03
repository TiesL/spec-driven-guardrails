#!/usr/bin/env bash
# S14 — De guard faalt naar toestaan als hij zelf stuk is.
# Dekt: F7

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

guard="$TEST_REPO_ROOT/hooks/git-guardrails"
[ -x "$guard" ] || { fail "S14 — hooks/git-guardrails ontbreekt"; test_klaar; }

project="$(vers_project werk)"
invoer='{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"'"$project"'","tool_input":{"command":"git reset --hard"}}'

# Given: geen jq en geen python3 in PATH. Een minimale bin-map met alleen de
# basisgereedschappen bootst een kale hook-omgeving na.
bin="$SANDBOX/minbin"
mkdir -p "$bin"
for t in bash sh sed grep cut tr git dirname basename cat head printf; do
  pad="$(command -v "$t" 2>/dev/null)" && ln -sf "$pad" "$bin/$t"
done

fout="$SANDBOX/stderr.txt"
printf '%s' "$invoer" | PATH="$bin" "$guard" >/dev/null 2>"$fout"
status=$?

# Zonder jq en python3 mag de guard best blokkeren als hij het commando alsnog
# kan lezen — maar hij mag nooit stilvallen zonder iets te zeggen.
if [ "$status" -ne 0 ] && [ "$status" -ne 2 ]; then
  fail "S14 — onverwachte exitstatus $status zonder jq/python3"
fi

# Given: helemaal geen bruikbaar gereedschap om de invoer te lezen.
kaal="$SANDBOX/kaal"
mkdir -p "$kaal"
for t in bash sh git; do
  pad="$(command -v "$t" 2>/dev/null)" && ln -sf "$pad" "$kaal/$t"
done

fout2="$SANDBOX/stderr2.txt"
printf '%s' "$invoer" | PATH="$kaal" "$guard" >/dev/null 2>"$fout2"
status2=$?

# Then: er verschijnt een luide waarschuwing, en het commando wordt toegestaan.
[ "$status2" -ne 2 ] || fail "S14 — de guard blokkeerde terwijl hij de invoer niet kon lezen"
[ -s "$fout2" ] || fail "S14 — geen waarschuwing toen de guard de invoer niet kon lezen"
grep -qi 'waarschuwing' "$fout2" || {
  fail "S14 — de melding is niet als waarschuwing herkenbaar"
  cat "$fout2" >&2
}

# En bij onleesbare invoer (geen geldige JSON) net zo: toestaan, niet raden.
printf 'dit is geen json' | "$guard" >/dev/null 2>/dev/null
[ $? -ne 2 ] || fail "S14 — de guard blokkeerde op invoer die geen JSON is"

# Lege invoer mag hem ook niet laten struikelen.
printf '' | "$guard" >/dev/null 2>/dev/null
[ $? -ne 2 ] || fail "S14 — de guard blokkeerde op lege invoer"

test_klaar
