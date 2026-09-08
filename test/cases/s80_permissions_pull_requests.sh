#!/usr/bin/env bash
# S80 — De check-job heeft leestoegang tot pull requests.
# Dekt: F17

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

# Is "pull-requests: read" ergens in dit bestand van kracht voor de check-job —
# op job-niveau (onder "check:") of op workflow-niveau (vóór "jobs:")? Beide
# tellen: een workflow-brede permissions:-sleutel geldt voor elke job eronder.
heeft_pull_requests_read() {
  grep -qE '^[[:space:]]*pull-requests:[[:space:]]*read[[:space:]]*$' "$1"
}

# check-pr-issue-link.sh (schakel 3, hard slot) en check-main-via-pr.sh
# hebben allebei die scope nodig om PR's op te vragen; zonder expliciete
# permissions krijgen ze het default, minimale tokenscope, waaronder beide
# falen — niet incidenteel, zoals issue #83 en #85 allebei lieten zien.
for bestand in templates/ci.yml .github/workflows/ci.yml; do
  pad="$TEST_REPO_ROOT/$bestand"

  if [ ! -f "$pad" ]; then
    fail "S80 — $bestand ontbreekt"
    continue
  fi

  heeft_pull_requests_read "$pad" \
    || fail "S80 — $bestand geeft de check-job geen pull-requests: read"
done

test_klaar
