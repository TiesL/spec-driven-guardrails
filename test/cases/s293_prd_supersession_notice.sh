#!/usr/bin/env bash
# S293 — PRD.md F44 states the supersession of #415 decision 1; the adopter notice exists (#488). Covers: F44
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
NOTICE_FILE=CHANGELOG.md   # maintainer decision on Q-A, option a
python3 -I - "$TEST_REPO_ROOT" "$NOTICE_FILE" <<'PY' || fail "S293 supersession or notice"
import re, sys
root, notice = sys.argv[1], sys.argv[2]
prd = open(f"{root}/PRD.md").read()
m = re.search(r"(?ms)^### F44\b.*?(?=^### F)", prd)
if not m:
    sys.exit("S293: no F44 section")
f44 = re.sub(r"\s+", " ", m.group(0))
i = f44.find("Low-severity default")
if i < 0:
    sys.exit("S293: no Low-severity default paragraph")
para = f44[i:]
for needle in ("#415", "decision 1", "#488"):
    if needle not in para:
        sys.exit(f"S293: F44 default paragraph lacks {needle}")
if not re.search(r"supersed", para):
    sys.exit("S293: F44 default paragraph lacks supersede")
if re.search(r"low = issue by default|never in a low-only round|a low finding is filed as an issue;", para):
    sys.exit("S293: F44 still states the old default as current")
cl = open(f"{root}/{notice}").read()
sec = re.search(r"(?ms)^## Unreleased\s*$(.*?)(?=^## )", cl)
if not sec:
    sys.exit("S293: no Unreleased section")
entries = re.split(r"(?m)^(?=- )", sec.group(1))
hits = [e for e in entries if "#488" in e and "Fix cost" in e]
if len(hits) != 1:
    sys.exit(f"S293: expected exactly one #488 notice entry in {notice}, found {len(hits)}")
if "#488" in open(f"{root}/CHANGES.md").read():
    sys.exit("S293: CHANGES.md must carry no #488 entry")
PY
test_done
