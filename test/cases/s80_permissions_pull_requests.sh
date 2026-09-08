#!/usr/bin/env bash
# S80 — De check-job heeft leestoegang tot pull requests en issues.
# Dekt: F17

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# Is "<sleutel>: read" ergens in dit bestand van kracht voor de check-job —
# op job-niveau (onder "check:") of op workflow-niveau (vóór "jobs:")? Beide
# tellen: een workflow-brede permissions:-sleutel geldt voor elke job eronder.
heeft_read_permissie() {
  local sleutel="$1" pad="$2"
  grep -qE "^[[:space:]]*${sleutel}:[[:space:]]*read[[:space:]]*\$" "$pad"
}

# check-pr-issue-link.sh (schakel 3, hard slot) en check-main-via-pr.sh
# hebben allebei pull-requests:read nodig om PR's op te vragen; zonder
# expliciete permissions krijgen ze het default, minimale tokenscope,
# waaronder beide falen — niet incidenteel, zoals issue #83 en #85 allebei
# lieten zien.
#
# issues:read is een apart gat: closingIssuesReferences (waar
# check-pr-issue-link.sh op leest) gaat over het gekoppelde issue zelf, niet
# over de PR. Zonder issues:read levert de opvraging stilzwijgend een lege
# lijst op, ook als de koppeling echt bestaat — geverifieerd op PR #105
# (issue #99, dit repo's eigen workflow) vóór hetzelfde gat hier voor
# templates/ci.yml werd gedicht (issue #106).
for bestand in templates/ci.yml .github/workflows/ci.yml; do
  pad="$TEST_REPO_ROOT/$bestand"

  if [ ! -f "$pad" ]; then
    fail "S80 — $bestand ontbreekt"
    continue
  fi

  heeft_read_permissie pull-requests "$pad" \
    || fail "S80 — $bestand geeft de check-job geen pull-requests: read"
  heeft_read_permissie issues "$pad" \
    || fail "S80 — $bestand geeft de check-job geen issues: read"
done

test_klaar
