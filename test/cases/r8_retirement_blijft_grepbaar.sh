#!/usr/bin/env bash
# R8 — Retirement blijft werken na herstructurering van CHANGES.md.
# Dekt: F5

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

changes="$TEST_REPO_ROOT/CHANGES.md"
archief="$TEST_REPO_ROOT/CHANGES-ARCHIEF.md"

if [ ! -f "$archief" ]; then
  fail "R8 — CHANGES-ARCHIEF.md ontbreekt"
  test_klaar
fi

# Given: een geretireerde entry die ooit beantwoord is, verhuisd naar het archief.
geretireerd="prd-testscenarios-issue-templates"

grep -q "^## $geretireerd\$" "$archief" || fail "R8 — $geretireerd staat niet in het archief"
if grep -q "^## $geretireerd\$" "$changes"; then
  fail "R8 — $geretireerd staat nog in CHANGES.md; retirement betekent verhuizen"
fi

# And: mét de reden van retirement, anders is het archief een graf zonder opschrift.
if ! awk -v id="## $geretireerd" '$0==id{gevonden=1;next} gevonden&&/^## /{exit} gevonden&&/[Rr]eden/{print;found=1} END{exit !found}' "$archief" >/dev/null; then
  fail "R8 — het archief noemt geen reden bij $geretireerd"
fi

# When: adopt.sh en pending-changes.sh draaien tegen een vers project.
project="$(vers_project doelproject)"
adopteer "$project"

# Then: de entry wordt nergens geseed of gevraagd.
if grep -q "$geretireerd" "$project/WORKFLOW-ADOPTIE.md"; then
  fail "R8 — $geretireerd is geseed in de adoptietabel"
fi
if openstaande_ids "$project" | grep -qx "$geretireerd"; then
  fail "R8 — $geretireerd wordt nog gevraagd"
fi

# And: het ID blijft vindbaar via grep over beide bestanden samen — een project
# dat de entry ooit beantwoordde kan nazoeken waar die rij vandaan komt.
if ! grep -h "$geretireerd" "$changes" "$archief" >/dev/null 2>&1; then
  fail "R8 — $geretireerd is niet meer terug te vinden over beide bestanden"
fi

test_klaar
