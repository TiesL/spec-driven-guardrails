#!/usr/bin/env bash
# S28 — pre-merge-review places a machine-recognizable marker in its findings
# comment, which the future merge guard (W10b/F8) keys on.
# Dekt: F11
#
# The merge guard does not exist yet (W10b) and actually placing a PR comment
# requires gh/network — so this is a document-contract test, in the style of
# s29: it checks that SKILL.md prescribes one fixed, grep-able marker, instead
# of simulating runtime behavior.

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
  fail "S28 — SKILL.md does not prescribe the marker '$marker'"
fi

# Machine-recognizable also means: one fixed text, not phrased differently per
# project or per review. Exactly one definition in the skill register.
aantal="$(grep -rlF "$marker" "$repo/skills" | wc -l | tr -d ' ')"
if [ "$aantal" -ne 1 ]; then
  fail "S28 — marker '$marker' should appear in exactly one skill, appeared in $aantal"
fi

test_klaar
