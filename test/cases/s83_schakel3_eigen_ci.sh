#!/usr/bin/env bash
# S83 — Schakel 3 (PR verwijst naar issue) draait in dit repo's eigen CI.
# Dekt: F17

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

pad="$TEST_REPO_ROOT/.github/workflows/ci.yml"
[ -f "$pad" ] || { fail "S83 — $pad ontbreekt"; test_klaar; }

# Then: een stap die check-pr-issue-link.sh aanroept, alleen op het
# pull_request-event — dezelfde vorm als "Commit op main komt uit een PR"
# hieronder gebruikt voor het push-event. grep -A4: genoeg regels om if/env/
# GITHUB_TOKEN/run te vangen zonder de volgende stap mee te pakken.
stap="$(grep -A4 'name: PR verwijst naar issue' "$pad")"
[ -n "$stap" ] || fail "S83 — $pad heeft geen 'PR verwijst naar issue'-stap"

case "$stap" in
  *"if: github.event_name == 'pull_request'"*) ;;
  *) fail "S83 — de schakel-3-stap is niet aan het pull_request-event gekoppeld" ;;
esac

case "$stap" in
  *check-pr-issue-link.sh*) ;;
  *) fail "S83 — de schakel-3-stap roept check-pr-issue-link.sh niet aan" ;;
esac

# And: de job heeft nog steeds pull-requests: read (issue #85/#91) — zonder
# die scope blokkeert deze stap elke PR, niet incidenteel.
grep -qE '^\s*pull-requests:\s*read\s*$' "$pad" \
  || fail "S83 — de check-job mist pull-requests: read"

# And: issues: read. closingIssuesReferences — waar check-pr-issue-link.sh op
# leest — is een veld over het gekoppelde issue zelf, niet over de PR.
# Zonder issues:read levert de opvraging onder het CI-token stilzwijgend een
# lege lijst op, ook als de koppeling echt bestaat: precies wat er op PR #105
# gebeurde (run 34234378780) vóórdat deze regel er stond. pull-requests:read
# alleen bleek dus niet genoeg voor schakel 3, in weerwil van wat #85/#91
# aannam.
grep -qE '^\s*issues:\s*read\s*$' "$pad" \
  || fail "S83 — de check-job mist issues: read"

test_klaar
