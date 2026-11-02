#!/usr/bin/env bash
# S530 — S314 and its fixture describe the hook input as transcript-derived with a rebuilt envelope (#620)
# Covers: F38
#
# Seam: the S314 section of TEST-SCENARIOS.md, the header comment of the S314
# test and the files in test/fixtures/agent-dispatch/, read as text. A text
# that says "captured real" or "real captured" must also say "envelope
# rebuilt"; the S314 section must say "transcript-derived".

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

R="$TEST_REPO_ROOT"

# wording_ok <label> <file> : prints a reason and returns 1 on a violation.
wording_ok() {
  if grep -qiE 'captured real|real captured' "$2" && ! grep -qi 'envelope rebuilt' "$2"; then
    echo "$1 says captured real without envelope rebuilt"; return 1
  fi
  return 0
}
# section_ok <file> : the S314 section must also say transcript-derived.
section_ok() {
  wording_ok "S314 section" "$1" || return 1
  grep -qi 'transcript-derived' "$1" || { echo "S314 section lacks transcript-derived"; return 1; }
}
# Collapse a text to one line, so a phrase wrapped over two lines still matches.
flat() { tr '\n' ' ' <"$1" | sed -e 's/  */ /g' >"$2"; }

sec="$SANDBOX/sec.txt"
awk '/^### S314 /{p=1;next} /^### /{p=0} p' "$R/TEST-SCENARIOS.md" >"$sec.raw"
# The heading is part of the scenario text.
{ grep -m1 '^### S314 ' "$R/TEST-SCENARIOS.md"; cat "$sec.raw"; } >"$sec.full"
[ -s "$sec.raw" ] || fail "S530 — no S314 section in TEST-SCENARIOS.md"
flat "$sec.full" "$sec"

# Real files.
msg="$(section_ok "$sec")" || fail "S530 — $msg"
hdr="$SANDBOX/hdr.txt"
sed -n '/^#/!q;p' "$R/test/cases/s314_agent_dispatch_wiring_and_real_input.sh" | tr '\n' ' ' >"$hdr"
msg="$(wording_ok "S314 test header" "$hdr")" || fail "S530 — $msg"
for f in "$R"/test/fixtures/agent-dispatch/*; do
  [ -f "$f" ] || continue
  msg="$(wording_ok "fixture $(basename "$f")" "$f")" || fail "S530 — $msg"
done

# Control: the corrected wording passes.
good="$SANDBOX/good.txt"
printf '%s\n' '### S314 a transcript-derived Agent input (envelope rebuilt in the documented shape)' >"$good"
section_ok "$good" >/dev/null || fail "S530/control — the corrected wording was rejected"

# Mutant 1: captured real without envelope rebuilt.
bad="$SANDBOX/bad1.txt"
printf '%s\n' '### S314 a transcript-derived captured real Agent input' >"$bad"
section_ok "$bad" >/dev/null && fail "S530/mutant — 'captured real' without 'envelope rebuilt' passed"
# Mutant 2: the good text minus transcript-derived.
sed 's/transcript-derived/derived/' "$good" >"$SANDBOX/bad2.txt"
section_ok "$SANDBOX/bad2.txt" >/dev/null && fail "S530/mutant — the section without transcript-derived passed"
# Mutant 3: 'real captured' in a fixture description without the envelope phrase.
printf '%s\n' 'a real captured hook input' >"$SANDBOX/bad3.txt"
wording_ok "fixture" "$SANDBOX/bad3.txt" >/dev/null && fail "S530/mutant — 'real captured' without 'envelope rebuilt' passed in a fixture"
test_done
