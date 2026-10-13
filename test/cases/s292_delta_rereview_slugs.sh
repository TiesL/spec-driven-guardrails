#!/usr/bin/env bash
# S292 — pre-merge-review/SKILL.md: a delta re-review carries every earlier slug (#488). Covers: F28
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
python3 -I - "$TEST_REPO_ROOT/skills/pre-merge-review/SKILL.md" <<'PY' || fail "S292 delta re-review sentence"
import re, sys
text = re.sub(r"\s+", " ", open(sys.argv[1]).read())
sentences = re.split(r"(?<=\.) ", text)
hits = [s for s in sentences if re.search(r"\bdelta\b", s) and re.search(r"\bslug", s)]
if len(hits) != 1:
    sys.exit(f"S292: expected one sentence with delta and slug, found {len(hits)}")
s = hits[0]
for lit in ("status=resolved", "status=open"):
    if lit not in s:
        sys.exit(f"S292: sentence lacks {lit}")
if not re.search(r"new findings", s) or not re.search(r"\bearlier\b", s):
    sys.exit("S292: sentence lacks new-findings limit or earlier slugs")
PY
test_done
