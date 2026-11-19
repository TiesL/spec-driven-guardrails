#!/usr/bin/env bash
# S712 — Live smoke test through the real proxy: protocol checked mechanically, execution UNRUN (#707; AC12)
# Covers: F75
#
# Seam: the structure of test/behavior/model-routing-smoke.md only. Nothing
# real runs here: no claude, codex, curl to the proxy, sqlite3 or network
# call. The claim "routed children are metered and arrive uncut" is not
# established by any scenario in this repository until the live run is
# recorded in that file.

set -uo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

sandbox_create
trap sandbox_destroy EXIT

P="$TEST_REPO_ROOT/test/behavior/model-routing-smoke.md"
[ -f "$P" ] || { fail "S712 — test/behavior/model-routing-smoke.md does not exist"; test_done; }

# check <file>: one line per structural problem; empty when the protocol holds.
check() {
  python3 -I - "$1" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
flat = re.sub(r"\s+", " ", text)
problems = []
m = re.search(r"^Status: \*\*([A-Z]+)\*\*", text, re.M)
if not m:
    problems.append("no 'Status: **...**' line")
    status = None
else:
    status = m.group(1)
    if text.find(m.group(0)) > 400:
        problems.append("Status line is not among the first lines")
if status not in ("UNRUN", "PASS", "FAIL"):
    problems.append("status is not UNRUN, PASS or FAIL: %s" % status)
record = {}
for field in ("Date", "Head SHA", "Proxy version", "Row ids"):
    r = re.search(r"^- %s: *(.*)$" % re.escape(field), text, re.M)
    if not r:
        problems.append("record field '%s' is missing" % field)
    record[field] = (r.group(1).strip() if r else "")
filled = [f for f, v in record.items() if v and v.lower() not in ("none", "-", "n/a")]
if status in ("PASS", "FAIL") and len(filled) != 4:
    problems.append("status %s claimed without date, head SHA, proxy version and row ids" % status)
if status == "UNRUN" and filled:
    problems.append("UNRUN but evidence is recorded: %s" % ", ".join(filled))
# The steps, in this order.
steps = [
    ("precondition: routing on", r"process-model-routing.{0,40}\byes\b"),
    ("precondition: proxy listening", r"proxy.{0,60}listen"),
    ("contract file", r"copy of `?skills/role-contracts/SKILL\.md"),
    ("claude child", r"route-child\.sh\"? claude -- claude -p --model haiku"),
    ("codex child", r"route-child\.sh\"? codex -- codex exec --ephemeral"),
    ("codex off", r"SDG_MODEL_ROUTE=off \"?\$?[A-Za-z_{}\"/]*route-child\.sh\"? codex -- codex exec"),
    ("read-only counts", r"read-only.{0,80}caveman\.db.{0,80}requests"),
]
pos = 0
for name, rx in steps:
    s = re.search(rx, flat[pos:], re.I)
    if not s:
        problems.append("step missing or out of order: " + name)
    else:
        pos += s.end()
for name, rx in [
    ("no contents", r"never read request or response contents"),
    ("provider anthropic", r"provider `?anthropic`?"),
    ("provider chatgpt-subscription", r"provider `?chatgpt-subscription`?"),
    ("eligibility", r"compression_eligible ?= ?0"),
    ("equal hashes", r"raw_request_sha256.{0,40}equals.{0,40}transformed_request_sha256"),
    ("no orchestrator row", r"no row for the Orchestrator"),
    ("off adds zero rows", r"off.{0,60}adds zero rows"),
    ("no elision marker", r"no elision marker"),
    ("not in check", r"not run by `?\./check`? or CI"),
]:
    if not re.search(rx, flat, re.I):
        problems.append("pass condition or rule missing: " + name)
if re.search(r"select \*|request_body|response_body", flat, re.I):
    problems.append("the protocol reads contents")
print("\n".join(problems))
PY
}

got="$(check "$P")"
[ -z "$got" ] || fail "S712 — the protocol does not hold:
$got"
grep -q '^Status: \*\*UNRUN\*\*' "$P" || fail "S712 — the protocol is not UNRUN (no recorded run is expected in this work item)"

# Negative controls: each one must be caught.
mutant() { # <label> <python expression over text t>
  python3 -I - "$P" "$SANDBOX/m.md" "$2" <<'PY'
import sys
t = open(sys.argv[1], encoding="utf-8").read()
t = eval(sys.argv[3])
open(sys.argv[2], "w", encoding="utf-8").write(t)
PY
  [ -n "$(check "$SANDBOX/m.md")" ] || fail "S712/neg — '$1' was not caught"
}
mutant pass-without-evidence 't.replace("Status: **UNRUN**", "Status: **PASS**")'
mutant drop-off-zero 't.replace("adds zero rows", "adds rows")'
mutant drop-orchestrator 't.replace("no row for the Orchestrator", "rows")'
mutant drop-hashes 't.replace("equals", "and")'
mutant drop-marker 't.replace("no elision marker", "nothing")'
mutant reads-contents 't + "\nSELECT * FROM requests;\n"'
mutant drop-no-contents 't.replace("Never read request or response contents", "read anything")'

# No case of this work item starts a real model, Codex or the proxy.
for f in "$TEST_REPO_ROOT"/test/cases/s70[0-9]_*.sh "$TEST_REPO_ROOT"/test/cases/s71[0-3]_*.sh; do
  hit="$(grep -nE '(^|[;&|(]|\$\()[[:space:]]*(claude|codex|caveman|caveman-proxy|sqlite3)([[:space:]]|$)' "$f" | grep -v '^[0-9]*:[[:space:]]*#')"
  [ -z "$hit" ] || fail "S712 — ${f#"$TEST_REPO_ROOT"/} starts a real model, Codex, the proxy or sqlite3: $hit"
done

test_done
