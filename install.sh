#!/usr/bin/env bash
# install.sh — Pins this checkout to a tagged release, for a consumer who
# doesn't want TiesL's own multi-machine, always-follow-main usage (W37,
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

own_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$own_dir"

if [ ! -f "$own_dir/WORKFLOW.md" ] || [ ! -f "$own_dir/adopt.sh" ] || [ ! -d "$own_dir/.git" ]; then
  echo "Error: '$own_dir' doesn't look like a spec-driven-guardrails clone (WORKFLOW.md, adopt.sh, or .git is missing)." >&2
  exit 1
fi

# When in doubt, touch nothing. `git checkout <tag>` would otherwise
# silently discard local, uncommitted changes — exactly the mistake a pin
# action must never make.
dirty="$(git status --porcelain)"
if [ -n "$dirty" ]; then
  echo "Error: this checkout has uncommitted changes — install.sh won't touch them, resolve that first:" >&2
  echo "$dirty" >&2
  exit 1
fi

git fetch --tags --quiet

tag="${1:-}"
if [ -z "$tag" ]; then
  if ! tag="$(git describe --tags --abbrev=0 2>/dev/null)"; then
    echo "Error: no tags found to pin to. Pass an explicit tag, or use main for TiesL's own ongoing usage." >&2
    exit 1
  fi
  echo "No tag given — picked the latest tag: $tag"
fi

if ! git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  echo "Error: tag '$tag' doesn't exist in this checkout (after a fresh \`git fetch --tags\`)." >&2
  exit 1
fi

git checkout --quiet "$tag"

echo "Done: this checkout is now pinned to $tag."
echo "Add this to your shell profile (\`~/.zshrc\` or \`~/.bashrc\`), if it isn't already there:"
echo "  export SPEC_DRIVEN_GUARDRAILS_DIR=\"$own_dir\""
echo "Then adopt a project as usual: \"\$SPEC_DRIVEN_GUARDRAILS_DIR/adopt.sh\"."
