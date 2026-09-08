#!/usr/bin/env bash
# S75 — De merge-guard blokkeert niet als er geen checks gerapporteerd zijn.
# Dekt: F8
#
# Een project zonder CI-workflow (CI is optioneel bij adoptie, zie ci-conventie
# in CHANGES.md) mag niet vastlopen op een controle die voor dat project niets
# te controleren heeft. Geen checks is geen rode vlag.
#
# Gevonden bij het reviewen van PR #82: gh geeft dit geval niet terug als een
# lege JSON-lijst, ook niet met --json. Zelfs dan blijft het zijn platte
# tekstmelding op stderr geven, met exitstatus 1 (geverifieerd tegen een
# echte PR zonder checks). De fake hieronder bootst dat exact na — een fake
# die "[]" teruggaf zou een pad testen dat in het echt niet bestaat.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

project="$(vers_project geen-ci)"
git -C "$project" commit -q --allow-empty -m start
git -C "$project" checkout -q -b feature/werk

fakebin="$(fake_gh_merge_bin "pre-merge-review:done" "NO_CHECKS_STDERR")"

invoer='{"tool_name":"Bash","cwd":"'"$project"'","tool_input":{"command":"gh pr merge"}}'
uitvoer="$(printf '%s' "$invoer" | PATH="$fakebin:$PATH" "$TEST_REPO_ROOT/hooks/git-guardrails" 2>&1)"
status=$?

[ "$status" -eq 0 ] || fail "S75 — verwacht doorgang (exit 0) zonder gerapporteerde checks, kreeg $status. Uitvoer: $uitvoer"

test_klaar
