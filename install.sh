#!/usr/bin/env bash
# install.sh — Pins this checkout to a tagged release, for a consumer who
# doesn't want Ties' own multi-machine, always-follow-main usage (W37,
# #79). Run this after cloning this repo, from inside the clone itself.
#
# Usage:
#   ./install.sh          # pins to the latest tag
#   ./install.sh <tag>     # pins to a specific tag
#
# This script doesn't adopt a project — that stays adopt.sh's job, with
# SPEC_DRIVEN_GUARDRAILS_DIR set to this clone. install.sh only replaces
# the "clone + checkout + env var" steps from README.md's "One-time setup
# per machine", with a pinned tag instead of a live `main`.
#
# No curl-to-bash: this repo runs on auditable scripts, and a clone is a
# reasonable ask for this audience (someone already using Claude Code +
# git).
#
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

set -euo pipefail

eigen_map="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$eigen_map"

if [ ! -f "$eigen_map/WORKFLOW.md" ] || [ ! -f "$eigen_map/adopt.sh" ] || [ ! -d "$eigen_map/.git" ]; then
  echo "Fout: '$eigen_map' lijkt geen kloon van spec-driven-guardrails (WORKFLOW.md, adopt.sh of .git ontbreekt)." >&2
  exit 1
fi

# When in doubt, touch nothing. `git checkout <tag>` would otherwise
# silently discard local, uncommitted changes — exactly the mistake a pin
# action must never make.
vuil="$(git status --porcelain)"
if [ -n "$vuil" ]; then
  echo "Fout: deze checkout heeft niet-gecommitte wijzigingen — install.sh raakt ze niet aan, los dat eerst op:" >&2
  echo "$vuil" >&2
  exit 1
fi

git fetch --tags --quiet

tag="${1:-}"
if [ -z "$tag" ]; then
  if ! tag="$(git describe --tags --abbrev=0 2>/dev/null)"; then
    echo "Fout: geen tags gevonden om op te pinnen. Geef een expliciete tag mee, of gebruik main voor Ties' eigen doorlopende gebruik." >&2
    exit 1
  fi
  echo "Geen tag opgegeven — laatste tag gekozen: $tag"
fi

if ! git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  echo "Fout: tag '$tag' bestaat niet in deze checkout (na een verse \`git fetch --tags\`)." >&2
  exit 1
fi

git checkout --quiet "$tag"

echo "Klaar: deze checkout staat nu gepind op $tag."
echo "Zet in je shell-profiel (\`~/.zshrc\` of \`~/.bashrc\`), als dat nog niet zo is:"
echo "  export SPEC_DRIVEN_GUARDRAILS_DIR=\"$eigen_map\""
echo "Adopteer daarna een project zoals gebruikelijk: \"\$SPEC_DRIVEN_GUARDRAILS_DIR/adopt.sh\"."
