#!/usr/bin/env bash
# templates/check-pr-issue-link.sh — Schakel 3 als hard slot in CI (W19b,
# F13 besluit d): faalt als de PR die deze CI-run triggert naar geen enkel
# issue verwijst.
#
# Aanroepen vanuit CI, met het PR-nummer als argument:
#
#   ./check-pr-issue-link.sh "$PR_NUMMER"
#
# Alleen de huidige PR wordt beoordeeld — geen audit over de geschiedenis: een
# audit over de 27 issueloze PR's van vóór dit werkitem zou eeuwig blijven
# falen en dus binnen een week uitgezet worden (zie F13).
#
# Vereist gh + een token met leestoegang; op GitHub Actions is GITHUB_TOKEN
# gratis beschikbaar. Bewust geen onderdeel van het lokale, offline `check` —
# dat is schakel 1 (check-traceability.sh). Schakels 2 en 3 hebben netwerk
# nodig en zitten daarom hier en in de poort van `pre-merge-review`.
#
# Geen faal-open hier: dit is het hárde slot juist omdat GITHUB_TOKEN op CI
# gegarandeerd is. Kan gh de PR niet raadplegen, dan is dat een echt
# CI-infraprobleem en hoort de check hardop te falen, niet stil door te laten.
#
# Bash 3.2-compatibel: geen declare -A, geen mapfile, geen ${var,,}.

set -uo pipefail

pr_nummer="${1:?gebruik: check-pr-issue-link.sh <pr-nummer>}"

if ! command -v gh >/dev/null 2>&1; then
  echo "check-pr-issue-link: gh ontbreekt — kan schakel 3 niet controleren." >&2
  exit 1
fi

aantal="$(gh pr view "$pr_nummer" --json closingIssuesReferences \
  --jq '.closingIssuesReferences | length' 2>/dev/null)"

if [ -z "$aantal" ]; then
  echo "check-pr-issue-link: kon PR #$pr_nummer niet raadplegen." >&2
  exit 1
fi

if [ "$aantal" -eq 0 ]; then
  echo "check-pr-issue-link: PR #$pr_nummer verwijst naar geen enkel issue (schakel 3) — voeg 'Closes #<issue>' toe of link het issue in de PR-sidebar." >&2
  exit 1
fi

exit 0
