#!/usr/bin/env bash
# check-core-rule-copies.sh — #750 (A66 AC5 drift): the repo holds one copy
# of each orchestrator rule's text, skills/role-contracts/ORCHESTRATOR.md.
# Installed copies are a symlink (Claude) or status-checked bytes (Codex);
# an enforcing script quotes a rule by its OR ID and reads the line from
# ORCHESTRATOR.md at run time. This check fails when a scoped file carries
# a rule line's text anyway.
#
# Usage: ./check-core-rule-copies.sh [dir]   (default: this script's dir)
#
# Rule line: `- OR<n> <text>` in ORCHESTRATOR.md. Copy: that text, with
# whitespace normalized, inside a scoped file (also normalized), so a
# re-wrapped copy counts. Scope: every file under hooks/ and adapters/,
# every `hook:` and `gate:` path declared in CHANGES.md, and
# session-context.sh. ORCHESTRATOR.md itself and test fixtures are out of
# scope. Exit 0 clean; 1 with one line per copy naming the file and OR ID.

set -uo pipefail

root="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")}" && pwd)" || exit 2
orch="$root/skills/role-contracts/ORCHESTRATOR.md"
[ -f "$orch" ] || { echo "check-core-rule-copies: $orch is missing" >&2; exit 2; }

declared=()
if [ -f "$root/CHANGES.md" ] && [ -f "$root/lib/changes.sh" ]; then
  # shellcheck source=lib/changes.sh
  . "$root/lib/changes.sh"
  while IFS='|' read -r _ value _; do
    case "$value" in
      hook:*|gate:*)
        value="${value#*:}"
        value="$(printf '%s' "$value" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
        [ -z "$value" ] || declared+=("$value") ;;
    esac
  done < <(reaches_session_values "$root/CHANGES.md")
fi

python3 -I - "$root" "$orch" hooks adapters session-context.sh ${declared[@]+"${declared[@]}"} <<'PY'
import os, re, sys
root, orch, scope = sys.argv[1], sys.argv[2], sys.argv[3:]
rules = []
with open(orch, encoding='utf-8') as handle:
    for line in handle:
        m = re.match(r'^- (OR\d+) (.*\S)\s*$', line)
        if m:
            rules.append((m.group(1), ' '.join(m.group(2).split())))
files = set()
for rel in scope:
    path = os.path.join(root, rel)
    if os.path.isdir(path):
        for d, _, names in os.walk(path):
            files.update(os.path.join(d, n) for n in names)
    elif os.path.isfile(path):
        files.add(path)
copies = 0
for path in sorted(files):
    if os.path.realpath(path) == os.path.realpath(orch):
        continue
    with open(path, encoding='utf-8', errors='replace') as handle:
        text = ' '.join(handle.read().split())
    for rid, body in rules:
        if body in text:
            print('check-core-rule-copies: ' + os.path.relpath(path, root) + ' carries the text of ' + rid
                  + '; quote it by ID and read the line from ORCHESTRATOR.md instead')
            copies += 1
sys.exit(1 if copies else 0)
PY
