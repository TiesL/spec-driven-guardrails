#!/usr/bin/env bash
# R8 — Retirement keeps working after restructuring CHANGES.md.
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
  fail "R8 — CHANGES-ARCHIEF.md is missing"
  test_klaar
fi

# Given: a retired entry that was once answered, moved to the archive.
geretireerd="prd-testscenarios-issue-templates"

grep -q "^## $geretireerd\$" "$archief" || fail "R8 — $geretireerd is not in the archive"
if grep -q "^## $geretireerd\$" "$changes"; then
  fail "R8 — $geretireerd is still in CHANGES.md; retirement means moving it"
fi

# And: with the reason for retirement, otherwise the archive is a grave without an inscription.
if ! awk -v id="## $geretireerd" '$0==id{gevonden=1;next} gevonden&&/^## /{exit} gevonden&&/[Rr]eden/{print;found=1} END{exit !found}' "$archief" >/dev/null; then
  fail "R8 — the archive names no reason for $geretireerd"
fi

# When: adopt.sh and pending-changes.sh run against a fresh project.
project="$(vers_project doelproject)"
adopteer "$project"

# Then: the entry is seeded or asked nowhere.
if grep -q "$geretireerd" "$project/WORKFLOW-ADOPTIE.md"; then
  fail "R8 — $geretireerd is seeded in the adoption table"
fi
if openstaande_ids "$project" | grep -qx "$geretireerd"; then
  fail "R8 — $geretireerd is still being asked"
fi

# And: the ID remains findable via grep across both files together — a project
# that once answered the entry can trace where that row came from.
if ! grep -h "$geretireerd" "$changes" "$archief" >/dev/null 2>&1; then
  fail "R8 — $geretireerd can no longer be found across both files"
fi

test_klaar
