#!/usr/bin/env bash
# find-shared-vocabulary.sh — Generates candidates for layer B (W33/#57, W38):
# every literal string that a script from this repo matches in a file or
# GitHub issue/PR of a different (adopted) repo. Doesn't replace human
# judgment — surfaces candidates, the curation lives in issue #110.
#
# Two parts:
#   1. Regression check: does every already-confirmed layer-B token still
#      exist where it was found? If it silently disappears (e.g. through a
#      refactor), this inventory itself is out of date.
#   2. Candidate scan: greps the same scripts for new combinations of a
#      project_dir-like variable and a literal, quoted string after it —
#      possible new layer-B candidates not covered by part 1.
#
# Usage: ./find-shared-vocabulary.sh
# Re-run whenever adopt.sh, pending-changes.sh, the skills/pre-merge-review
# scripts, templates/check-*.sh, hooks/git-guardrails, or lib/*.sh change.
#
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

set -uo pipefail

eigen_map="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$eigen_map"

fout=0

echo "=== Part 1: regression check on confirmed layer-B tokens ==="

controleer() {
  local omschrijving="$1" bestand="$2" patroon="$3"
  if [ ! -f "$bestand" ]; then
    echo "MISSING: $omschrijving — $bestand no longer exists" >&2
    fout=1
    return
  fi
  if grep -qE -- "$patroon" "$bestand"; then
    echo "ok — $omschrijving ($bestand)"
  else
    echo "MISSING: $omschrijving — pattern no longer found in $bestand" >&2
    fout=1
  fi
}

controleer "WORKFLOW-ADOPTION.md as the filename" pending-changes.sh 'WORKFLOW-ADOPTION\.md'
controleer "WORKFLOW-ADOPTIE.md as the pre-migration fallback (W42/#114)" pending-changes.sh 'WORKFLOW-ADOPTIE\.md'
controleer "yes/no answer values (seed, W42/#114)" adopt.sh '\| yes \|'
controleer "the 'requires substantiation' stamp (W42/#114)" adopt.sh 'requires substantiation'
controleer "the 'vereist onderbouwing' stamp as the pre-migration fallback (W42/#114)" pending-changes.sh 'vereist onderbouwing'
controleer ".gitignore-managed block marker" adopt.sh 'claude-workflow: begin'
controleer "issue templates (cp -f)" adopt.sh 'cp -f "\$template_src"'
controleer "entry ID process-context-document as a logic gate (W42/#114)" adopt.sh 'process-context-document'
controleer "entry ID proces-context-document as the pre-migration fallback (W42/#114)" adopt.sh 'proces-context-document'
controleer "entry ID quality-review-before-merge as a logic gate (W42/#114)" hooks/git-guardrails 'quality-review-before-merge'
controleer "entry ID kwaliteitsreview-voor-merge as the pre-migration fallback (W42/#114)" hooks/git-guardrails 'kwaliteitsreview-voor-merge'
controleer "the \\*\\*Covers:\\*\\*-field as a logic gate (project-owned PRD/TEST-SCENARIOS, W42/#114)" templates/check-traceability.sh 'Covers:'
controleer "the \\*\\*Dekt:\\*\\*-field as pre-migration detection (project-owned PRD/TEST-SCENARIOS, W42/#114)" templates/check-traceability.sh 'Dekt:'
controleer "the \\*\\*Covers:\\*\\*-field as a logic gate (external issue bodies, W42/#114)" skills/pre-merge-review/scenario-poort.sh 'Covers:'
controleer "the \\*\\*Dekt:\\*\\*-field as a permanent exception (external issue bodies, historical, W42/#114)" skills/pre-merge-review/scenario-poort.sh 'Dekt:'
controleer "the <!-- nfr: <id> --> anchor" lib/nfr.sh 'nfr: \$id'
controleer "the <!-- pre-merge-review:done --> marker (external PR comments)" hooks/git-guardrails 'pre-merge-review:done'

echo
echo "=== Part 2: candidate scan (new combinations, needs manual review) ==="

kandidaat_scripts="adopt.sh pending-changes.sh hooks/git-guardrails lib/changes.sh lib/nfr.sh skills/pre-merge-review/scope.sh skills/pre-merge-review/scenario-poort.sh templates/check-traceability.sh templates/check-pr-issue-link.sh templates/check-main-via-pr.sh"

for script in $kandidaat_scripts; do
  [ -f "$script" ] || continue
  # Lines with a project_dir/antwoorden/prd/scenarios-like variable followed
  # by grep/case on a quoted string — the shape every layer-B token found so
  # far shares.
  treffers="$(grep -nE '\$(project_dir|antwoorden|prd|scenarios)' "$script" \
    | grep -E "grep |case |==|~" \
    | grep -vE '^\s*#')"
  if [ -n "$treffers" ]; then
    echo "--- $script ---"
    echo "$treffers"
  fi
done

echo
if [ "$fout" -eq 0 ]; then
  echo "find-shared-vocabulary.sh: all confirmed layer-B tokens still present."
else
  echo "find-shared-vocabulary.sh: inventory is out of date — see MISSING above." >&2
fi
exit "$fout"
