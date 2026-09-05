#!/usr/bin/env bash
# S28 — pre-merge-review plaatst een machineherkenbare marker in zijn
# bevindingen-comment, waar de toekomstige merge-guard (W10b/F8) op keyt.
# Dekt: F11
#
# De merge-guard bestaat nog niet (W10b) en het echt plaatsen van een
# PR-comment vraagt gh/netwerk — dit is dus een documentcontract-test, in de
# stijl van s29: hij toetst dat SKILL.md één vaste, grep-bare marker
# voorschrijft, in plaats van runtime-gedrag te simuleren.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

repo="$(sandbox_copy_repo)"
skill="$repo/skills/pre-merge-review/SKILL.md"
marker='<!-- pre-merge-review:done -->'

if ! grep -qF "$marker" "$skill"; then
  fail "S28 — SKILL.md schrijft de marker '$marker' niet voor"
fi

# Machineherkenbaar betekent ook: één vaste tekst, niet per project of per
# review anders geformuleerd. Precies één definitie in het skill-register.
aantal="$(grep -rlF "$marker" "$repo/skills" | wc -l | tr -d ' ')"
if [ "$aantal" -ne 1 ]; then
  fail "S28 — marker '$marker' hoort in precies één skill te staan, stond in $aantal"
fi

test_klaar
