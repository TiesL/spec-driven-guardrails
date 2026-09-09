#!/usr/bin/env bash
# install.sh — Pin deze checkout op een getagde release, voor een consument
# die niet Ties' eigen multi-machine, altijd-main-volgende gebruik wil (W37,
# #79). Draai dit ná het klonen van dit repo, vanuit de kloon zelf.
#
# Gebruik:
#   ./install.sh          # pint op de laatste tag
#   ./install.sh <tag>     # pint op een specifieke tag
#
# Dit script adopteert geen project — dat blijft adopt.sh's taak, met
# SPEC_DRIVEN_GUARDRAILS_DIR gezet naar déze kloon. install.sh vervangt
# alleen de "kloon + checkout + env-var"-stappen uit README.md's "One-time
# setup per machine", met een gepinde tag in plaats van een live `main`.
#
# Geen curl-naar-bash: dit repo draait op auditeerbare scripts, en een kloon
# is voor deze doelgroep (iemand die al Claude Code + git gebruikt) een
# redelijke vraag.
#
# Bash 3.2-compatibel: geen declare -A, geen mapfile, geen ${var,,}.

set -euo pipefail

eigen_map="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$eigen_map"

if [ ! -f "$eigen_map/WORKFLOW.md" ] || [ ! -f "$eigen_map/adopt.sh" ] || [ ! -d "$eigen_map/.git" ]; then
  echo "Fout: '$eigen_map' lijkt geen kloon van spec-driven-guardrails (WORKFLOW.md, adopt.sh of .git ontbreekt)." >&2
  exit 1
fi

# Bij twijfel niets aanraken. `git checkout <tag>` gooit lokale,
# niet-gecommitte wijzigingen anders stilzwijgend weg — precies de fout die
# een pin-actie nooit mag maken.
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
