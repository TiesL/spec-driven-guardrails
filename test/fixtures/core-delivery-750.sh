#!/usr/bin/env bash
# shellcheck disable=SC2034 # the constants are used by the cases that source this file
# test/fixtures/core-delivery-750.sh — shared helpers for the #750 (A66)
# scenarios S732-S735 and the changed S309/S708/S713. Source after
# test/lib.sh. Not a test case.
#
# Bash 3.2-compatible: no declare -A, no mapfile, no ${var,,}.

CORE750_LINK='.claude/rules/sdg-orchestrator-core.md'
CORE750_BEGIN='<!-- spec-driven-guardrails: orchestrator-core begin -->'
CORE750_END='<!-- spec-driven-guardrails: orchestrator-core end -->'
CORE750_WF_BEGIN='<!-- spec-driven-guardrails: begin -->'
CORE750_WF_END='<!-- spec-driven-guardrails: end -->'
CORE750_ORCH_REL='skills/role-contracts/ORCHESTRATOR.md'

# core750_rule_hits <ORCHESTRATOR.md> <file>...: one "<ORn> <file>" line for
# every live rule line (`- OR<n> <text>`) of the core whose text, whitespace
# normalized, appears in a file (also whitespace normalized). Nothing when no
# file carries rule text.
core750_rule_hits() {
  python3 -I - "$@" <<'PY'
import re, sys
orch, files = sys.argv[1], sys.argv[2:]
rules = []
for line in open(orch, encoding='utf-8'):
    m = re.match(r'^- (OR\d+) (.*\S)\s*$', line)
    if m:
        rules.append((m.group(1), ' '.join(m.group(2).split())))
for f in files:
    try:
        text = ' '.join(open(f, encoding='utf-8', errors='replace').read().split())
    except OSError:
        continue
    for rid, body in rules:
        if body in text:
            print(rid, f)
PY
}

# core750_tree_digest <dir>: one line per entry under dir (path, type, link
# target or content hash), sorted; empty for a missing dir. Equal digests
# mean the tree was not written.
core750_tree_digest() {
  [ -e "$1" ] || return 0
  python3 -I - "$1" <<'PY'
import hashlib, os, sys
root = sys.argv[1]
out = []
for d, dirs, files in os.walk(root):
    for n in sorted(dirs + files):
        p = os.path.join(d, n)
        rel = os.path.relpath(p, root)
        if os.path.islink(p):
            out.append(rel + ' L ' + os.readlink(p))
        elif os.path.isdir(p):
            out.append(rel + ' D')
        else:
            with open(p, 'rb') as h:
                out.append(rel + ' F ' + hashlib.sha256(h.read()).hexdigest())
print('\n'.join(sorted(out)))
PY
}

# core750_physical <path>: the fully resolved physical path (realpath), or
# empty when it does not resolve.
core750_physical() {
  python3 -I -c 'import os,sys; p=os.path.realpath(sys.argv[1]); print(p if os.path.exists(p) else "")' "$1"
}

# core750_adopt <clone> <project> [args...]: run the clone's adopt.sh with the
# clone as SPEC_DRIVEN_GUARDRAILS_DIR; output in $SANDBOX/adopt.out.
core750_adopt() {
  local wf="$1" p="$2"
  shift 2
  SPEC_DRIVEN_GUARDRAILS_DIR="$wf" "$wf/adopt.sh" "$@" "$p" >"$SANDBOX/adopt.out" 2>&1
}

# core750_block <AGENTS.md>: the bytes between the orchestrator-core begin
# line (after its newline) and the end marker, written to stdout; exit 1 when
# the block is not present exactly once.
core750_block() {
  python3 -I - "$1" "$CORE750_BEGIN" "$CORE750_END" <<'PY'
import sys
data = open(sys.argv[1], 'rb').read()
b, e = sys.argv[2].encode(), sys.argv[3].encode()
if data.count(b) != 1 or data.count(e) != 1:
    sys.exit(1)
start = data.index(b) + len(b)
if data[start:start + 1] != b'\n':
    sys.exit(1)
stop = data.index(e)
if stop < start:
    sys.exit(1)
sys.stdout.buffer.write(data[start + 1:stop])
PY
}

# core750_toml_top <config.toml> <key>: the raw value of a top-level key
# (before the first table header), or nothing.
core750_toml_top() {
  awk -v k="$2" '
    /^[ \t]*\[/ { exit }
    {
      line = $0
      sub(/^[ \t]+/, "", line)
      if (index(line, k) == 1) {
        rest = substr(line, length(k) + 1)
        if (rest ~ /^[ \t]*=/) { sub(/^[ \t]*=[ \t]*/, "", rest); sub(/[ \t]*(#.*)?$/, "", rest); print rest; exit }
      }
    }
  ' "$1" 2>/dev/null
}
